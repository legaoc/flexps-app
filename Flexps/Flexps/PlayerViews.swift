import SwiftUI

// MARK: - Mini player (barra inferior sobre el TabView)
struct MiniPlayerView: View {
    var onTap: () -> Void
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var player: PlayerManager

    var body: some View {
        if let song = player.currentSong {
            Button(action: onTap) {
                HStack(spacing: 12) {
                    CoverView(song: song, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(song.displayTitle)
                            .lineLimit(1)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text(song.displayArtist)
                            .lineLimit(1)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        player.togglePlayPause()
                    } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    Button {
                        player.next()
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.body)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(radius: 4)
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Full player (con portada, seek, controles, cola y karaoke)
struct FullPlayerView: View {
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var player: PlayerManager
    @Environment(\.dismiss) private var dismiss
    @State private var showQueue = false
    @State private var karaokeOn = false
    @State private var lyricLines: [LyricLine] = []
    @State private var plainLyrics: String = ""
    @State private var lyricsLoading = false
    @State private var showSleepPicker = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let song = player.currentSong {
                        if karaokeOn {
                            karaokeSection(song: song)
                        } else {
                            CoverView(song: song, size: 300)
                                .padding(.top, 8)
                        }
                        VStack(spacing: 4) {
                            Text(song.displayTitle)
                                .font(.title2)
                                .fontWeight(.bold)
                                .multilineTextAlignment(.center)
                            Text(song.displayArtist)
                                .font(.title3)
                                .foregroundStyle(.secondary)
                            Text(song.displayAlbum)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 6) {
                                if !song.qualityLabel.isEmpty {
                                    Text(song.qualityLabel)
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Color.secondary.opacity(0.2))
                                        .clipShape(Capsule())
                                }
                                if let releaseDate = song.releaseDate {
                                    Text(releaseDate)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        seekSection
                        controlsSection(song: song)
                        HStack(spacing: 24) {
                            Button {
                                karaokeOn.toggle()
                                if karaokeOn { Task { await loadLyrics(for: song) } }
                            } label: {
                                Label("Karaoke", systemImage: "mic.fill")
                            }
                            .buttonStyle(.bordered)
                            .tint(karaokeOn ? .accentColor : .secondary)
                            Button {
                                showQueue = true
                            } label: {
                                Label("Cola", systemImage: "list.bullet")
                            }
                            .buttonStyle(.bordered)
                            Button {
                                showSleepPicker = true
                            } label: {
                                Label(
                                    player.sleepTimer == .off ? "Dormir" : player.sleepTimer.label,
                                    systemImage: "moon.fill"
                                )
                            }
                            .buttonStyle(.bordered)
                        }
                        if !karaokeOn, !plainLyrics.isEmpty, lyricLines.isEmpty {
                            Text(plainLyrics)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                        }
                    } else {
                        Text("No hay nada sonando.")
                            .foregroundStyle(.secondary)
                            .padding(.top, 60)
                    }
                }
                .padding()
            }
            .navigationTitle("Reproduciendo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    if let song = player.currentSong {
                        Button {
                            store.toggleSongFavorite(song)
                        } label: {
                            Image(systemName: song.favorite ? "heart.fill" : "heart")
                                .foregroundStyle(song.favorite ? .red : .primary)
                        }
                    }
                }
            }
            .sheet(isPresented: $showQueue) {
                QueueView()
            }
            .confirmationDialog("Detener automáticamente", isPresented: $showSleepPicker) {
                ForEach(SleepTimerOption.allCases) { option in
                    Button(option.label) {
                        player.setSleepTimer(option)
                    }
                }
                Button("Cancelar", role: .cancel) { }
            } message: {
                if let remaining = player.sleepRemaining, player.sleepTimer != .off, player.sleepTimer != .endOfSong {
                    Text("Quedan \(Int(remaining / 60)) min \(Int(remaining.truncatingRemainder(dividingBy: 60))) s.")
                } else {
                    Text("La música se detendrá sola.")
                }
            }
            .onAppear {
                if let song = player.currentSong {
                    Task { await loadLyrics(for: song) }
                }
            }
            .onChange(of: player.currentSong) { _, newSong in
                karaokeOn = false
                lyricLines = []
                plainLyrics = ""
                if let newSong {
                    Task { await loadLyrics(for: newSong) }
                }
            }
        }
    }

    private var seekSection: some View {
        VStack(spacing: 4) {
            Slider(
                value: Binding(
                    get: { player.currentTime },
                    set: { player.seek(to: $0) }
                ),
                in: 0...max(player.duration, 1)
            )
            HStack {
                Text(FlexpsFormat.time(player.currentTime))
                Spacer()
                Text(FlexpsFormat.time(player.duration))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func controlsSection(song: Song) -> some View {
        HStack(spacing: 36) {
            Button {
                player.isShuffle.toggle()
            } label: {
                Image(systemName: "shuffle")
                    .font(.title2)
                    .foregroundStyle(player.isShuffle ? .accentColor : .primary)
            }
            Button {
                player.previous()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.title)
            }
            Button {
                player.togglePlayPause()
            } label: {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 68))
            }
            Button {
                player.next()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.title)
            }
            Button {
                player.repeatMode = nextRepeatMode(after: player.repeatMode)
            } label: {
                Image(systemName: player.repeatMode.icon)
                    .font(.title2)
                    .foregroundStyle(player.repeatMode == .off ? .primary : .accentColor)
            }
        }
        .foregroundStyle(.primary)
    }

    private func nextRepeatMode(after mode: RepeatMode) -> RepeatMode {
        switch mode {
        case .off: return .all
        case .all: return .one
        case .one: return .off
        }
    }

    // MARK: - Karaoke (letra a pantalla completa con línea activa)
    private func karaokeSection(song: Song) -> some View {
        VStack(spacing: 12) {
            if lyricsLoading {
                ProgressView("Buscando letra…")
                    .padding(.vertical, 40)
            } else if !lyricLines.isEmpty {
                let active = LyricsService.activeLineIndex(lines: lyricLines, at: player.currentTime)
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 14) {
                            ForEach(Array(lyricLines.enumerated()), id: \.offset) { index, line in
                                Text(line.text)
                                    .font(index == active ? .title3.bold() : .title3)
                                    .foregroundStyle(index == active ? .primary : .secondary)
                                    .multilineTextAlignment(.center)
                                    .id(index)
                            }
                        }
                        .padding(.vertical, 20)
                    }
                    .frame(height: 320)
                    .onChange(of: active) { _, newActive in
                        if let newActive {
                            withAnimation {
                                proxy.scrollTo(newActive, anchor: .center)
                            }
                        }
                    }
                }
            } else if !plainLyrics.isEmpty {
                ScrollView {
                    Text(plainLyrics)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 320)
            } else {
                Text("No se encontró letra para esta canción.")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 40)
            }
        }
    }

    private func loadLyrics(for song: Song) async {
        lyricsLoading = true
        if let cached = await store.fetchLyrics(for: song) {
            lyricLines = LyricsService.parseLRC(cached.syncedLyrics)
            plainLyrics = cached.plainLyrics
        } else {
            lyricLines = []
            plainLyrics = ""
        }
        lyricsLoading = false
    }
}

// MARK: - Cola ("A continuación")
struct QueueView: View {
    @EnvironmentObject var player: PlayerManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let current = player.currentSong {
                    Section("Sonando ahora") {
                        SongRowView(song: current, showArtist: true) { }
                    }
                }
                Section("A continuación") {
                    if player.upcomingQueue.isEmpty {
                        Text("No hay más canciones en la cola.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(player.upcomingQueue) { song in
                        SongRowView(song: song) {
                            player.play(song: song, in: player.queue)
                        }
                    }
                    .onDelete { offsets in
                        // Los índices de upcomingQueue corresponden a queueIndex+1...
                        let mapped = IndexSet(offsets.map { $0 + player.queueIndex + 1 })
                        player.removeFromQueue(at: mapped)
                    }
                }
            }
            .navigationTitle("Cola")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
    }
}
