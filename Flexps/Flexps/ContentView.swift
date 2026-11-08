import SwiftUI
import UniformTypeIdentifiers

// MARK: - Raíz de la app
// La web usa un dock inferior: Inicio / Playlists / Buscar / Favoritos
// (dockGoTo en index.html:2646). Aquí es un TabView nativo con esos 4 tabs.
struct ContentView: View {
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var player: PlayerManager
    @AppStorage("flexps.theme") private var themeRaw: String = AppTheme.system.rawValue
    @State private var showFullPlayer = false
    @State private var showImporter = false
    @State private var showSettings = false

    private var theme: AppTheme { AppTheme(rawValue: themeRaw) ?? .system }

    var body: some View {
        TabView {
            HomeView(showImporter: $showImporter, showSettings: $showSettings)
            .tabItem { Label("Inicio", systemImage: "house.fill") }
            .tag(0)

            NavigationStack {
                PlaylistsView()
            }
            .tabItem { Label("Playlists", systemImage: "music.note.list") }
            .tag(1)

            NavigationStack {
                SearchView()
            }
            .tabItem { Label("Buscar", systemImage: "magnifyingglass") }
            .tag(2)

            NavigationStack {
                FavoritesView()
            }
            .tabItem { Label("Favoritos", systemImage: "heart.fill") }
            .tag(3)
        }
        .appTheme(theme)
        .safeAreaInset(edge: .bottom) {
            if player.currentSong != nil {
                MiniPlayerView(onTap: { showFullPlayer = true })
            }
        }
        .sheet(isPresented: $showFullPlayer) {
            FullPlayerView()
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack { SettingsView() }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.mp3, .mpeg4Audio, .wav, .flac, .aac, .audio],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                Task { await store.importFiles(urls) }
            case .failure:
                break
            }
        }
        .alert("Importando", isPresented: $store.isImporting) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(store.importStatus)
        }
        .onAppear {
            player.store = store
            player.crossfadeOn = store.meta.crossfadeOn
            player.crossfadeSeconds = store.meta.crossfadeSeconds
        }
        .onChange(of: store.meta.crossfadeOn) { _, newValue in
            player.crossfadeOn = newValue
        }
        .onChange(of: store.meta.crossfadeSeconds) { _, newValue in
            player.crossfadeSeconds = newValue
        }
    }
}

// MARK: - Portada de canción / álbum / artista
struct CoverView: View {
    var song: Song?
    var imageURL: String?
    var size: CGFloat = 56

    @EnvironmentObject var store: LibraryStore

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.2))
            if let song, let data = store.coverImageData(for: song), let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else if let imageURL, let url = URL(string: imageURL) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Image(systemName: "music.note")
                        .foregroundStyle(.secondary)
                }
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Image(systemName: "music.note")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Fila de canción (songRow en la web, index.html:2953)
struct SongRowView: View {
    var song: Song
    var showArtist: Bool = true
    var onTap: (() -> Void)?

    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var player: PlayerManager
    @State private var showAddToPlaylist = false
    @State private var showDeleteConfirm = false

    var body: some View {
        HStack(spacing: 12) {
            CoverView(song: song, size: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text(song.displayTitle)
                    .lineLimit(1)
                    .font(.body)
                if showArtist {
                    Text(song.displayArtist)
                        .lineLimit(1)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    if !song.qualityLabel.isEmpty {
                        Text(song.qualityLabel)
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.2))
                            .clipShape(Capsule())
                    }
                    Text(song.formattedDuration)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if song.favorite {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
            }
            if player.currentSong?.id == song.id {
                Image(systemName: player.isPlaying ? "waveform" : "pause.fill")
                    .foregroundStyle(.accentColor)
                    .font(.caption)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
        .contextMenu {
            Button {
                player.play(song: song)
            } label: {
                Label("Reproducir", systemImage: "play.fill")
            }
            Button {
                store.toggleSongFavorite(song)
            } label: {
                Label(song.favorite ? "Quitar de favoritos" : "Agregar a favoritos",
                      systemImage: song.favorite ? "heart.slash" : "heart")
            }
            Button {
                showAddToPlaylist = true
            } label: {
                Label("Agregar a playlist", systemImage: "music.note.list")
            }
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("Eliminar de la biblioteca", systemImage: "trash")
            }
        }
        .sheet(isPresented: $showAddToPlaylist) {
            AddToPlaylistSheet(song: song)
        }
        .alert("Eliminar canción", isPresented: $showDeleteConfirm) {
            Button("Eliminar", role: .destructive) {
                if player.currentSong?.id == song.id { player.pause() }
                store.deleteSong(song)
            }
            Button("Cancelar", role: .cancel) { }
        } message: {
            Text("Se eliminará \"\(song.displayTitle)\" de tu biblioteca.")
        }
    }
}

// MARK: - Hoja "Agregar a playlist"
struct AddToPlaylistSheet: View {
    var song: Song
    @EnvironmentObject var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var newPlaylistName = ""
    @State private var showNewPlaylistField = false

    var body: some View {
        NavigationStack {
            List {
                if showNewPlaylistField {
                    HStack {
                        TextField("Nombre de la playlist", text: $newPlaylistName)
                        Button("Crear") {
                            guard !newPlaylistName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                            let playlist = store.createPlaylist(name: newPlaylistName)
                            store.addSong(song, to: playlist)
                            dismiss()
                        }
                    }
                }
                ForEach(store.playlists) { playlist in
                    Button {
                        store.addSong(song, to: playlist)
                        dismiss()
                    } label: {
                        HStack {
                            Text(playlist.name)
                            Spacer()
                            if playlist.songIds.contains(song.id) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.accentColor)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
            .navigationTitle("Agregar a playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Nueva") { showNewPlaylistField = true }
                }
            }
        }
    }
}
