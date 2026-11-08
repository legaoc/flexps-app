import SwiftUI

// MARK: - Buscar (búsqueda global de la web: canciones y artistas)
struct SearchView: View {
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var player: PlayerManager
    @State private var searchText = ""

    private var matchingSongs: [Song] {
        guard !searchText.isEmpty else { return [] }
        let q = searchText.lowercased()
        return store.songs.filter {
            $0.displayTitle.lowercased().contains(q) ||
            $0.displayArtist.lowercased().contains(q) ||
            $0.displayAlbum.lowercased().contains(q)
        }
    }

    private var matchingArtists: [String] {
        guard !searchText.isEmpty else { return [] }
        let q = searchText.lowercased()
        return store.artists.filter { $0.lowercased().contains(q) }
    }

    private var matchingAlbums: [String] {
        guard !searchText.isEmpty else { return [] }
        let q = searchText.lowercased()
        return store.albums.filter { $0.lowercased().contains(q) }
    }

    var body: some View {
        List {
            if searchText.isEmpty {
                Section {
                    Text("Busca canciones, artistas o álbumes de tu biblioteca.")
                        .foregroundStyle(.secondary)
                }
                if !store.songs.isEmpty {
                    Section("Recién agregadas") {
                        ForEach(store.songs.sorted { $0.addedAt > $1.addedAt }.prefix(5)) { song in
                            SongRowView(song: song) {
                                player.play(song: song, in: store.songs)
                            }
                        }
                    }
                }
            } else {
                if matchingSongs.isEmpty && matchingArtists.isEmpty && matchingAlbums.isEmpty {
                    Text("Sin resultados para \"\(searchText)\".")
                        .foregroundStyle(.secondary)
                }
                if !matchingSongs.isEmpty {
                    Section("Canciones") {
                        ForEach(matchingSongs) { song in
                            SongRowView(song: song) {
                                player.play(song: song, in: matchingSongs)
                            }
                        }
                    }
                }
                if !matchingArtists.isEmpty {
                    Section("Artistas") {
                        ForEach(matchingArtists, id: \.self) { artist in
                            NavigationLink(artist) {
                                ArtistDetailView(artist: artist)
                            }
                        }
                    }
                }
                if !matchingAlbums.isEmpty {
                    Section("Álbumes") {
                        ForEach(matchingAlbums, id: \.self) { album in
                            NavigationLink(album) {
                                AlbumDetailView(album: album)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Buscar")
        .searchable(text: $searchText, prompt: "Canciones, artistas, álbumes")
    }
}

// MARK: - YouTube (renderYouTubeView en la web, index.html:4548)
// Busca con tu clave de YouTube Data API v3 (Ajustes) o pega un enlace,
// que funciona sin clave vía oEmbed. Reproduce con el IFrame oficial.
struct YouTubeView: View {
    @EnvironmentObject var store: LibraryStore
    @AppStorage("flexps.youtubeApiKey") private var apiKey: String = ""
    @State private var query = ""
    @State private var results: [YouTubeTrack] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var selectedTrack: YouTubeTrack?
    @State private var showPlayer = false

    var body: some View {
        List {
            Section {
                Text("Busca en YouTube o pega un enlace. Suena con el reproductor oficial. Para la búsqueda hace falta tu clave de YouTube Data API v3 (la pegas en Ajustes); el enlace funciona sin esa clave.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Section {
                HStack {
                    TextField("Canción, artista o enlace", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit { search() }
                    if isSearching {
                        ProgressView()
                    } else {
                        Button("Buscar") { search() }
                            .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.subheadline)
                }
            }
            if !results.isEmpty {
                Section("Resultados") {
                    ForEach(results) { track in
                        youTubeRow(track)
                    }
                }
            }
            if !store.recentYouTube.isEmpty {
                Section("Recientes en YouTube") {
                    ForEach(store.recentYouTube) { track in
                        youTubeRow(track)
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("YouTube")
        .sheet(isPresented: $showPlayer) {
            if let selectedTrack {
                YouTubePlayerSheet(track: selectedTrack, onEnded: playNextYouTube)
            }
        }
    }

    private func youTubeRow(_ track: YouTubeTrack) -> some View {
        Button {
            store.rememberYouTube(track)
            selectedTrack = track
            showPlayer = true
        } label: {
            HStack(spacing: 12) {
                AsyncImage(url: track.cover.flatMap(URL.init(string:))) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.2))
                        Image(systemName: "play.fill").foregroundStyle(.red)
                    }
                }
                .frame(width: 72, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .lineLimit(2)
                        .foregroundStyle(.primary)
                    Text(track.artist)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func search() {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        errorMessage = nil
        // Si parece un enlace, resolverlo directo (sin clave).
        if YouTubeService.parseVideoId(text) != nil {
            isSearching = true
            Task {
                if let track = await YouTubeService.trackFromLink(text) {
                    results = [track]
                    store.rememberYouTube(track)
                    selectedTrack = track
                    showPlayer = true
                } else {
                    errorMessage = "No se pudo abrir ese enlace de YouTube."
                }
                isSearching = false
            }
            return
        }
        guard !apiKey.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = YouTubeService.YouTubeError.noAPIKey.errorDescription
            return
        }
        isSearching = true
        Task {
            do {
                results = try await YouTubeService.search(query: text, apiKey: apiKey)
                if results.isEmpty {
                    errorMessage = "Sin resultados para \"\(text)\"."
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isSearching = false
        }
    }

    /// Al terminar un video, pasa al siguiente de los resultados/recientes.
    private func playNextYouTube() {
        let list = !results.isEmpty ? results : store.recentYouTube
        guard let current = selectedTrack,
              let index = list.firstIndex(where: { $0.videoId == current.videoId }),
              index + 1 < list.count else {
            showPlayer = false
            return
        }
        selectedTrack = list[index + 1]
        store.rememberYouTube(list[index + 1])
    }
}

// Hoja con el reproductor IFrame de YouTube.
struct YouTubePlayerSheet: View {
    var track: YouTubeTrack
    var onEnded: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                YouTubePlayerView(videoId: track.videoId) { state in
                    if state == .ended { onEnded() }
                }
                .frame(height: 240)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 4) {
                    Text(track.title)
                        .font(.headline)
                    Text(track.artist)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Spacer()
                Text("El audio suena con el reproductor oficial de YouTube. YouTube no permite extraer el audio.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .navigationTitle("YouTube")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
    }
}
