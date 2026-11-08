import SwiftUI

// MARK: - Ajustes (hoja de ajustes de la web, index.html:4158-4264)
// Tema, crossfade + duración, sleep timer, actualizar info, actualizar
// letras, ver almacenamiento, borrar biblioteca, versión.
struct SettingsView: View {
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var player: PlayerManager
    @Environment(\.dismiss) private var dismiss
    @AppStorage("flexps.theme") private var themeRaw: String = AppTheme.system.rawValue
    @AppStorage("flexps.youtubeApiKey") private var apiKey: String = ""
    @State private var showClearConfirm = false
    @State private var statusMessage: String?
    @State private var isUpdatingInfo = false
    @State private var isUpdatingLyrics = false
    @State private var showVersionHistory = false

    var body: some View {
        List {
            Section("Apariencia") {
                // theme es una computed var sobre themeRaw (@AppStorage):
                // asignarla dentro del set de un Binding escapaba como
                // 'self' inmutable. El Binding opera sobre themeRaw
                // directamente, con el mismo comportamiento.
                Picker("Tema", selection: Binding(
                    get: { AppTheme(rawValue: themeRaw) ?? .system },
                    set: { themeRaw = $0.rawValue }
                )) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.label).tag(theme)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Reproducción") {
                Toggle("Crossfade", isOn: Binding(
                    get: { store.meta.crossfadeOn },
                    set: {
                        store.meta.crossfadeOn = $0
                        store.save()
                    }
                ))
                if store.meta.crossfadeOn {
                    Stepper(
                        "Duración del crossfade: \(store.meta.crossfadeSeconds) s",
                        value: Binding(
                            get: { store.meta.crossfadeSeconds },
                            set: {
                                store.meta.crossfadeSeconds = $0
                                store.save()
                            }
                        ),
                        in: 1...12
                    )
                    Text("El crossfade mezcla el final de una canción con el inicio de la siguiente.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Picker("Detener automáticamente", selection: Binding(
                    get: { player.sleepTimer },
                    set: { player.setSleepTimer($0) }
                )) {
                    ForEach(SleepTimerOption.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                if let remaining = player.sleepRemaining,
                   player.sleepTimer != .off, player.sleepTimer != .endOfSong {
                    Text("Se detendrá en \(Int(remaining / 60)) min \(Int(remaining.truncatingRemainder(dividingBy: 60))) s.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("YouTube") {
                SecureField("Clave de YouTube Data API v3", text: $apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Text("La búsqueda de YouTube necesita tu clave de YouTube Data API v3. Se guarda solo en este teléfono, nunca sale de aquí. Pegar un enlace funciona sin clave.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Biblioteca") {
                Button {
                    Task {
                        isUpdatingInfo = true
                        let result = await store.updateAllInfo()
                        statusMessage = "Información actualizada: \(result.updated) de \(result.total) canciones con datos de Deezer."
                        isUpdatingInfo = false
                    }
                } label: {
                    Label("Actualizar información", systemImage: "info.circle")
                }
                .disabled(isUpdatingInfo || store.songs.isEmpty)
                Button {
                    Task {
                        isUpdatingLyrics = true
                        let result = await store.updateAllLyrics()
                        statusMessage = "Letras encontradas: \(result.found) de \(result.total) canciones."
                        isUpdatingLyrics = false
                    }
                } label: {
                    Label("Actualizar letras", systemImage: "music.mic")
                }
                .disabled(isUpdatingLyrics || store.songs.isEmpty)
                if isUpdatingInfo || isUpdatingLyrics {
                    ProgressView()
                }
                HStack {
                    Text("Almacenamiento")
                    Spacer()
                    Text(store.formattedStorageSize())
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Canciones")
                    Spacer()
                    Text("\(store.songs.count)")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Playlists")
                    Spacer()
                    Text("\(store.playlists.count)")
                        .foregroundStyle(.secondary)
                }
                Button(role: .destructive) {
                    showClearConfirm = true
                } label: {
                    Label("Borrar biblioteca", systemImage: "trash")
                }
            }

            Section("Acerca de") {
                HStack {
                    Text("iPlayerPod")
                    Spacer()
                    Text("v\(VersionHistory.current)")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Versión web original")
                    Spacer()
                    Text("v\(VersionHistory.webVersion)")
                        .foregroundStyle(.secondary)
                }
                Button("Historial de versiones") {
                    showVersionHistory = true
                }
            }

            if let statusMessage {
                Section {
                    Text(statusMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Ajustes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cerrar") { dismiss() }
            }
        }
        .alert("Borrar biblioteca", isPresented: $showClearConfirm) {
            Button("Borrar todo", role: .destructive) {
                player.pause()
                store.clearLibrary()
                dismiss()
            }
            Button("Cancelar", role: .cancel) { }
        } message: {
            Text("Se eliminarán todas las canciones, playlists y letras de este teléfono. Esta acción no se puede deshacer.")
        }
        .sheet(isPresented: $showVersionHistory) {
            NavigationStack {
                List(VersionHistory.entries) { entry in
                    Section("v\(entry.version) · \(entry.date)") {
                        ForEach(entry.notes, id: \.self) { note in
                            Text("• \(note)")
                                .font(.subheadline)
                        }
                    }
                }
                .navigationTitle("Historial de versiones")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cerrar") { showVersionHistory = false }
                    }
                }
            }
        }
    }
}
