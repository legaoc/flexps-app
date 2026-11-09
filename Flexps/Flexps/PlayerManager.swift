import AVFoundation
import Foundation
import MediaPlayer
import SwiftUI

// MARK: - Reproductor
// Web: <audio> + crossAudio (index.html:1671), mini player y full player,
// seek, prev/next, shuffle, repeat off/all/one, cola "A continuación",
// crossfade 1-12 s (default 4), sleep timer (no persistente), MediaSession.
// Aquí: AVPlayer principal + segundo AVPlayer solo para el crossfade,
// AVAudioSession playback, MPNowPlayingInfoCenter + MPRemoteCommandCenter.
@MainActor
final class PlayerManager: ObservableObject {

    @Published var currentSong: Song?
    @Published var queue: [Song] = []
    @Published var queueIndex: Int = 0
    @Published var isPlaying: Bool = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var isShuffle: Bool = false
    @Published var repeatMode: RepeatMode = .off
    @Published var crossfadeOn: Bool = false
    @Published var crossfadeSeconds: Int = 4
    @Published var sleepTimer: SleepTimerOption = .off
    @Published var sleepRemaining: TimeInterval?

    /// Visualizador de audio: energía real por MTAudioProcessingTap
    /// (solo lectura) o respiración por seno sin tap. Lo usa el fondo
    /// que respira del reproductor completo.
    let visualizer = AudioVisualizer()

    weak var store: LibraryStore?

    private var player: AVPlayer?
    private var fadePlayer: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var crossfadeTimer: Timer?
    private var crossfadeTriggered = false
    private var sleepTimerHandle: Timer?
    private var sleepEndDate: Date?
    private var fadeTimer: Timer?

    init() {
        setupAudioSession()
        setupRemoteCommands()
    }

    deinit {
        if let observer = timeObserver { player?.removeTimeObserver(observer) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        sleepTimerHandle?.invalidate()
        crossfadeTimer?.invalidate()
        fadeTimer?.invalidate()
    }

    // MARK: - Sesión de audio y controles del sistema

    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            // Sin sesión de audio no hay reproducción en segundo plano.
        }
    }

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.resume() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.next() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previous() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self, let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self.seek(to: event.positionTime) }
            return .success
        }
    }

    // MARK: - Cola y reproducción

    /// Reproduce una lista empezando por una canción (playSongList en la web).
    func playList(_ list: [Song], startingAt song: Song) {
        guard let index = list.firstIndex(where: { $0.id == song.id }) else { return }
        queue = list
        queueIndex = index
        playCurrent()
    }

    func play(song: Song, in list: [Song]? = nil) {
        if let list {
            playList(list, startingAt: song)
        } else {
            queue = [song]
            queueIndex = 0
            playCurrent()
        }
    }

    /// Mezcla una lista y la reproduce (botón shuffle de los detalles).
    func playShuffled(_ list: [Song]) {
        guard !list.isEmpty else { return }
        queue = list.shuffled()
        queueIndex = 0
        playCurrent()
    }

    private func playCurrent() {
        guard queue.indices.contains(queueIndex) else { return }
        let song = queue[queueIndex]
        crossfadeTriggered = false
        currentSong = song
        duration = song.duration
        currentTime = 0
        store?.songs.firstIndex(where: { $0.id == song.id }).map { index in
            store?.songs[index].playCount += 1
            store?.save()
        }
        guard let store, let url = songURL(song, in: store) else {
            visualizer.detach()
            return
        }
        startPlayer(with: url, song: song)
    }

    private func songURL(_ song: Song, in store: LibraryStore) -> URL? {
        let url = store.localFileURL(for: song)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func startPlayer(with url: URL, song: Song) {
        stopFadePlayer()
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        let item = AVPlayerItem(url: url)
        visualizer.attach(to: item)
        player = AVPlayer(playerItem: item)
        player?.volume = 1.0
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                self.currentTime = time.seconds.isFinite ? time.seconds : 0
                if let itemDuration = self.player?.currentItem?.duration.seconds, itemDuration.isFinite, itemDuration > 0 {
                    self.duration = itemDuration
                }
                self.checkCrossfade()
                self.updateNowPlaying()
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleTrackEnded() }
        }
        player?.play()
        isPlaying = true
        visualizer.isPlaying = true
        if sleepTimer == .endOfSong {
            // El temporizador "al terminar la canción" se resuelve en handleTrackEnded.
        }
        updateNowPlaying()
    }

    func togglePlayPause() {
        isPlaying ? pause() : resume()
    }

    func pause() {
        player?.pause()
        fadePlayer?.pause()
        isPlaying = false
        visualizer.isPlaying = false
        updateNowPlaying()
    }

    func resume() {
        if player == nil, let song = currentSong { play(song: song) ; return }
        player?.play()
        isPlaying = true
        visualizer.isPlaying = true
        updateNowPlaying()
    }

    func seek(to seconds: Double) {
        let time = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        player?.seek(to: time)
        currentTime = seconds
        updateNowPlaying()
    }

    func next() {
        guard !queue.isEmpty else { return }
        if isShuffle {
            queueIndex = Int.random(in: 0..<queue.count)
        } else if queueIndex + 1 < queue.count {
            queueIndex += 1
        } else if repeatMode == .all {
            queueIndex = 0
        } else {
            pause()
            return
        }
        playCurrent()
    }

    func previous() {
        // Si ya pasaron 3 segundos, vuelve al inicio de la canción.
        if currentTime > 3 {
            seek(to: 0)
            return
        }
        guard !queue.isEmpty else { return }
        if queueIndex > 0 {
            queueIndex -= 1
        } else if repeatMode == .all {
            queueIndex = queue.count - 1
        } else {
            seek(to: 0)
            return
        }
        playCurrent()
    }

    private func handleTrackEnded() {
        if sleepTimer == .endOfSong {
            pause()
            clearSleepTimer()
            return
        }
        if repeatMode == .one {
            playCurrent()
            return
        }
        next()
    }

    /// Canciones que vienen después en la cola ("A continuación").
    var upcomingQueue: [Song] {
        guard !queue.isEmpty, queueIndex + 1 < queue.count else { return [] }
        return Array(queue[(queueIndex + 1)...])
    }

    func moveQueueItem(from source: IndexSet, to destination: Int) {
        queue.move(fromOffsets: source, toOffset: destination)
    }

    func removeFromQueue(at offsets: IndexSet) {
        // No permitir borrar la canción que suena.
        let filtered = offsets.filter { $0 != queueIndex }
        queue.remove(atOffsets: IndexSet(filtered))
        if queueIndex >= queue.count { queueIndex = max(0, queue.count - 1) }
    }

    // MARK: - Crossfade

    private func checkCrossfade() {
        guard crossfadeOn, !crossfadeTriggered, duration > 0 else { return }
        let remaining = duration - currentTime
        guard remaining <= Double(crossfadeSeconds), remaining > 0 else { return }
        crossfadeTriggered = true
        startCrossfadeToNext()
    }

    private func startCrossfadeToNext() {
        guard let store else { return }
        let nextIndex: Int?
        if isShuffle {
            nextIndex = queue.isEmpty ? nil : Int.random(in: 0..<queue.count)
        } else if queueIndex + 1 < queue.count {
            nextIndex = queueIndex + 1
        } else if repeatMode == .all {
            nextIndex = 0
        } else {
            nextIndex = nil
        }
        guard let nextIndex, queue.indices.contains(nextIndex),
              let url = songURL(queue[nextIndex], in: store) else { return }
        let nextSong = queue[nextIndex]
        let item = AVPlayerItem(url: url)
        fadePlayer = AVPlayer(playerItem: item)
        fadePlayer?.volume = 0
        fadePlayer?.play()
        let steps = 20
        let stepDuration = Double(crossfadeSeconds) / Double(steps)
        var step = 0
        fadeTimer?.invalidate()
        fadeTimer = Timer.scheduledTimer(withTimeInterval: stepDuration, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            Task { @MainActor in
                step += 1
                let progress = min(1.0, Double(step) / Double(steps))
                self.fadePlayer?.volume = Float(progress)
                self.player?.volume = Float(1.0 - progress)
                if step >= steps {
                    timer.invalidate()
                    self.queueIndex = nextIndex
                    self.currentSong = nextSong
                    self.currentTime = 0
                    self.duration = nextSong.duration
                    self.crossfadeTriggered = false
                    // El fadePlayer pasa a ser el principal.
                    if let observer = self.timeObserver {
                        self.player?.removeTimeObserver(observer)
                        self.timeObserver = nil
                    }
                    self.player = self.fadePlayer
                    self.fadePlayer = nil
                    self.player?.volume = 1.0
                    self.attachObservers()
                    // El tap vivía en el ítem anterior: se engancha al nuevo.
                    if let item = self.player?.currentItem {
                        self.visualizer.attach(to: item)
                    }
                    self.updateNowPlaying()
                }
            }
        }
    }

    private func attachObservers() {
        guard let player, let item = player.currentItem else { return }
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                self.currentTime = time.seconds.isFinite ? time.seconds : 0
                self.checkCrossfade()
                self.updateNowPlaying()
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleTrackEnded() }
        }
    }

    private func stopFadePlayer() {
        fadeTimer?.invalidate()
        fadePlayer?.pause()
        fadePlayer = nil
        player?.volume = 1.0
    }

    // MARK: - Temporizador de apagado (sleep timer, NO persistente)

    func setSleepTimer(_ option: SleepTimerOption) {
        clearSleepTimer()
        sleepTimer = option
        switch option {
        case .off, .endOfSong:
            sleepRemaining = nil
        default:
            guard let minutes = Double(option.rawValue) else { return }
            let seconds = minutes * 60
            sleepEndDate = Date().addingTimeInterval(seconds)
            sleepRemaining = seconds
            sleepTimerHandle = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
                Task { @MainActor in
                    guard let self else { timer.invalidate(); return }
                    if let end = self.sleepEndDate {
                        self.sleepRemaining = max(0, end.timeIntervalSinceNow)
                        if self.sleepRemaining == 0 {
                            self.pause()
                            self.clearSleepTimer()
                        }
                    }
                }
            }
        }
    }

    func clearSleepTimer() {
        sleepTimerHandle?.invalidate()
        sleepTimerHandle = nil
        sleepEndDate = nil
        sleepRemaining = nil
        sleepTimer = .off
    }

    // MARK: - Now Playing (MediaSession de la web)

    private func updateNowPlaying() {
        guard let song = currentSong else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: song.displayTitle,
            MPMediaItemPropertyArtist: song.displayArtist,
            MPMediaItemPropertyAlbumTitle: song.displayAlbum,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        if let data = store?.coverImageData(for: song), let image = UIImage(data: data) {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
