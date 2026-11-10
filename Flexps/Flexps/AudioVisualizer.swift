import AVFoundation
import CoreMedia
import Foundation
import MediaToolbox
import os
import SwiftUI

// MARK: - Visualizador de audio (fiel a la web, index.html:4897–4944)
// La web NO son barras: la portada es estática y el movimiento vive en el
// fondo difuminado detrás, con escala/rotación/saturación/brillo movidos por
// la energía del analyser (fftSize 256, smoothingTimeConstant .78) y una
// deriva lenta por seno. Sin analyser, respiración por seno.
// En nativo el espectro real viene de un MTAudioProcessingTap de SOLO
// LECTURA sobre el AVPlayerItem: el audio pasa intacto (GetSourceAudio y
// se devuelve tal cual). NO se usa AVAudioEngine, para no tocar el
// crossfade (segundo AVPlayer) ni la reproducción en segundo plano.
// Sin tap (YouTube, que suena en WKWebView) o en pausa, respiración por
// seno, como en la web. Si el tap falla por cualquier motivo, la app sigue
// funcionando con la respiración: el visualizador nunca rompe la música.
@MainActor
final class AudioVisualizer: ObservableObject {

    /// Energía suavizada 0...1, como la de la web (media de frecuencias / 255).
    @Published var energy: Double = 0.08

    /// true mientras suena una canción local (el tap o el seno la mueven).
    var isPlaying = false

    /// RMS crudo escrito por el tap en el hilo de audio. Nonisolated para
    /// que el callback de audio (tiempo real) pueda escribir sin MainActor.
    nonisolated let rawEnergy = OSAllocatedUnfairLock(initialState: 0.0)

    private var hasTap = false
    /// nonisolated(unsafe) para poder invalidarlo en deinit sin tocar
    /// estado aislado al MainActor desde un contexto no aislado. Solo se
    /// toca en el hilo principal (init y deinit).
    nonisolated(unsafe) private var timer: Timer?
    private var startTime = Date()

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    deinit {
        timer?.invalidate()
    }

    /// Tick a 20 Hz: suaviza el RMS como la web (.78) o respira por seno.
    private func tick() {
        let elapsed = Date().timeIntervalSince(startTime)
        if hasTap && isPlaying {
            let raw = rawEnergy.withLock { $0 }
            energy = energy * 0.78 + min(1.0, raw * 3.0) * 0.22
        } else if isPlaying {
            energy = 0.08 + abs(sin(elapsed * 4)) * 0.08
        } else {
            energy = 0.08
        }
    }

    /// Engancha el tap de solo lectura al ítem. Se llama antes de darle play.
    /// Si no hay pista de audio o el tap no se puede crear, hasTap queda en
    /// false y el visualizador respira por seno.
    func attach(to item: AVPlayerItem) {
        hasTap = false
        guard let track = item.asset.tracks.first(where: { $0.mediaType == .audio }) else { return }
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: Unmanaged.passUnretained(self).toOpaque(),
            init: { _, clientInfo, tapStorageOut in
                guard let clientInfo else { return }
                let viz = Unmanaged<AudioVisualizer>.fromOpaque(clientInfo).takeUnretainedValue()
                let state = UnsafeMutablePointer<TapState>.allocate(capacity: 1)
                state.initialize(to: TapState(
                    visualizer: Unmanaged.passUnretained(viz),
                    isFloat: true,
                    bytesPerSample: 4
                ))
                tapStorageOut.pointee = UnsafeMutableRawPointer(state)
            },
            finalize: { tap in
                let state = MTAudioProcessingTapGetStorage(tap).assumingMemoryBound(to: TapState.self)
                state.deinitialize(count: 1)
                state.deallocate()
            },
            prepare: { tap, _, format in
                let state = MTAudioProcessingTapGetStorage(tap).assumingMemoryBound(to: TapState.self)
                let desc = format.pointee
                state.pointee.isFloat = (desc.mFormatFlags & kAudioFormatFlagIsFloat) != 0
                let channels = max(1, Int(desc.mChannelsPerFrame))
                state.pointee.bytesPerSample = max(1, Int(desc.mBytesPerFrame) / channels)
            },
            unprepare: { _ in },
            process: { tap, numberFrames, _, bufferListInOut, numberFramesOut, flagsOut in
                var sourceFlags = MTAudioProcessingTapFlags()
                let status = MTAudioProcessingTapGetSourceAudio(
                    tap, numberFrames, bufferListInOut, &sourceFlags, nil, nil
                )
                numberFramesOut.pointee = numberFrames
                flagsOut.pointee = sourceFlags
                guard status == noErr else { return }
                let state = MTAudioProcessingTapGetStorage(tap)
                    .assumingMemoryBound(to: TapState.self).pointee
                let viz = state.visualizer.takeUnretainedValue()
                var sum: Double = 0
                var count = 0
                let buffers = UnsafeMutableAudioBufferListPointer(bufferListInOut)
                for buffer in buffers {
                    guard let data = buffer.mData else { continue }
                    if state.isFloat {
                        let n = Int(buffer.mDataByteSize) / 4
                        let samples = data.assumingMemoryBound(to: Float.self)
                        for i in 0..<n {
                            let s = Double(samples[i])
                            sum += s * s
                        }
                        count += n
                    } else {
                        let bytes = max(2, state.bytesPerSample)
                        let n = Int(buffer.mDataByteSize) / bytes
                        let samples = data.assumingMemoryBound(to: Int16.self)
                        for i in 0..<n {
                            let s = Double(samples[i]) / 32768.0
                            sum += s * s
                        }
                        count += n
                    }
                }
                let rms = count > 0 ? sqrt(sum / Double(count)) : 0
                viz.rawEnergy.withLock { $0 = rms }
            }
        )
        // MTAudioProcessingTap es un CFType importado como clase: Create
        // devuelve el tap directo (MTAudioProcessingTap?), no un Unmanaged.
        var tap: MTAudioProcessingTap?
        let status = MTAudioProcessingTapCreate(
            kCFAllocatorDefault, &callbacks,
            kMTAudioProcessingTapCreationFlag_PreEffects, &tap
        )
        guard status == noErr, let tap else { return }
        let params = AVMutableAudioMixInputParameters(track: track)
        params.audioTapProcessor = tap
        let mix = AVMutableAudioMix()
        mix.inputParameters = [params]
        item.audioMix = mix
        // ARC lo gestiona y el audioMix lo retiene mientras suene el ítem.
        hasTap = true
    }

    /// Suelta el tap (al cambiar de canción sin audio local, por ejemplo).
    func detach() {
        hasTap = false
    }
}

// Estado por tap, guardado en el storage del propio tap. Solo lo toca el
// hilo de audio; el visualizador se guarda sin retener (vive en el
// PlayerManager mientras exista cualquier ítem).
private struct TapState {
    var visualizer: Unmanaged<AudioVisualizer>
    var isFloat: Bool
    var bytesPerSample: Int
}

// MARK: - Fondo que respira detrás de la portada
// Fórmulas exactas de la web (animateArtwork):
//   drift = sin(t*.22)*3.2 + sin(t*.09)*1.6
//   escala = 1.12 + min(.05, energía*.06)
//   rotación = drift + (energía-.25)*1.4
//   saturación = 1.18 + energía*.3
//   brillo = 1 + energía*.05
// La portada de encima es estática; solo este fondo se mueve.
struct BreathingCoverBackground: View {
    var song: Song?

    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var player: PlayerManager

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let energy = player.visualizer.energy
            let drift = sin(t * 0.22) * 3.2 + sin(t * 0.09) * 1.6
            let scale = 1.12 + min(0.05, energy * 0.06)
            let rotation = drift + (energy - 0.25) * 1.4
            let saturation = 1.18 + energy * 0.3
            let brightness = energy * 0.05
            ZStack {
                if let song,
                   let data = store.coverImageData(for: song),
                   let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    LinearGradient(
                        colors: [Color.accentColor.opacity(0.25), Color.secondary.opacity(0.15)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }
            .scaleEffect(scale)
            .rotationEffect(.degrees(rotation))
            .saturation(saturation)
            .brightness(brightness)
            .blur(radius: 36)
        }
        .ignoresSafeArea()
    }
}
