import SwiftUI

// MARK: - Canciones (renderSongsView en la web, index.html:3414)
// Con búsqueda global y los 7 órdenes de applySort().
struct SongsListView: View {
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var player: PlayerManager
    @State private var searchText = ""
    @State private var sortMode: SortMode = .name

    private var filteredSongs: [Song] {
        var list = store.songs
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            list = list.filter {
                $0.displayTitle.lowercased().contains(q) ||
                $0.displayArtist.lowercased().contains(q)
            }
        }
        return sortMode.sort(list)
    }

    var body: some View {
        List {
            if filteredSongs.isEmpty {
                Text(store.songs.isEmpty ? "No hay canciones todavía. Impórtalas desde Inicio." : "Sin resultados para \"\(searchText)\".")
                    .foregroundStyle(.secondary)
            }
            ForEach(filteredSongs) { song in
                SongRowView(song: song) {
                    player.play(song: song, in: filteredSongs)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Canciones")
        .searchable(text: $searchText, prompt: "Buscar canciones o artistas")
        .toolbar {
            Menu {
                Picker("Ordenar por", selection: $sortMode) {
                    ForEach(SortMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
            } label: {
                Label("Ordenar", systemImage: "arrow.up.arrow.down")
            }
        }
    }
}

// MARK: - Artistas (renderGroupList en la web, index.html:3333)
struct ArtistsListView: View {
    @EnvironmentObject var store: LibraryStore

    var body: some View {
        List {
            ForEach(store.artists, id: \.self) { artist in
                let artistSongs = store.songsByArtist(artist)
                NavigationLink {
                    ArtistDetailView(artist: artist)
                } label: {
                    HStack(spacing: 12) {
                        CoverView(song: store.coverForSongs(artistSongs), size: 52)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(artist)
                                .lineLimit(1)
                            Text("\(artistSongs.count) canciones")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if store.isEntityFavorite(type: .artist, key: artist) {
                            Image(systemName: "heart.fill")
                                .foregroundStyle(.red)
                                .font(.caption)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Artistas")
    }
}

// MARK: - Álbumes
struct AlbumsListView: View {
    @EnvironmentObject var store: LibraryStore

    var body: some View {
        List {
            ForEach(store.albums, id: \.self) { album in
                let albumSongs = store.songsByAlbum(album)
                NavigationLink {
                    AlbumDetailView(album: album)
                } label: {
                    HStack(spacing: 12) {
                        CoverView(song: store.coverForSongs(albumSongs), size: 52)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(album)
                                .lineLimit(1)
                            Text(albumSongs.first?.displayArtist ?? "")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Text("\(albumSongs.count) canciones")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if store.isEntityFavorite(type: .album, key: album) {
                            Image(systemName: "heart.fill")
                                .foregroundStyle(.red)
                                .font(.caption)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Álbumes")
    }
}

// MARK: - Detalle de artista (detailHero en la web, index.html:3118)
struct ArtistDetailView: View {
    var artist: String
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var player: PlayerManager

    private var artistSongs: [Song] { store.songsByArtist(artist) }
    private var artistImage: String? { artistSongs.first { $0.artistImage != nil }?.artistImage }

    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    CoverView(song: store.coverForSongs(artistSongs), imageURL: artistImage, size: 160)
                    Text(artist)
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("\(artistSongs.count) canciones")
                        .foregroundStyle(.secondary)
                    HStack(spacing: 16) {
                        Button {
                            player.playShuffled(artistSongs)
                        } label: {
                            Label("Aleatorio", systemImage: "shuffle")
                        }
                        .buttonStyle(.borderedProminent)
                        Button {
                            store.toggleEntityFavorite(type: .artist, key: artist)
                        } label: {
                            Label(
                                store.isEntityFavorite(type: .artist, key: artist) ? "Quitar de favoritos" : "Marcar favorito",
                                systemImage: store.isEntityFavorite(type: .artist, key: artist) ? "heart.fill" : "heart"
                            )
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }
            ForEach(artistSongs) { song in
                SongRowView(song: song, showArtist: false) {
                    player.play(song: song, in: artistSongs)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(artist)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Detalle de álbum
struct AlbumDetailView: View {
    var album: String
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var player: PlayerManager

    private var albumSongs: [Song] { store.songsByAlbum(album) }

    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    CoverView(song: store.coverForSongs(albumSongs), size: 160)
                    Text(album)
                        .font(.title2)
                        .fontWeight(.bold)
                    Text(albumSongs.first?.displayArtist ?? "")
                        .foregroundStyle(.secondary)
                    if let releaseDate = albumSongs.first(where: { $0.releaseDate != nil })?.releaseDate {
                        Text("Lanzamiento: \(releaseDate)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Text("\(albumSongs.count) canciones")
                        .foregroundStyle(.secondary)
                    HStack(spacing: 16) {
                        Button {
                            player.playShuffled(albumSongs)
                        } label: {
                            Label("Aleatorio", systemImage: "shuffle")
                        }
                        .buttonStyle(.borderedProminent)
                        Button {
                            store.toggleEntityFavorite(type: .album, key: album)
                        } label: {
                            Label("Favorito", systemImage: store.isEntityFavorite(type: .album, key: album) ? "heart.fill" : "heart")
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }
            ForEach(albumSongs) { song in
                SongRowView(song: song) {
                    player.play(song: song, in: albumSongs)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(album)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            store.markAlbumRecent(album)
        }
    }
}

// MARK: - Favoritos (tab del dock)
// Canciones favoritas + playlists, álbumes y artistas favoritos.
struct FavoritesView: View {
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var player: PlayerManager

    private var favoriteSongs: [Song] {
        store.songs.filter { $0.favorite }
            .sorted { ($0.favoritedAt ?? 0) > ($1.favoritedAt ?? 0) }
    }

    var body: some View {
        List {
            Section("Canciones") {
                if favoriteSongs.isEmpty {
                    Text("Aún no tienes canciones favoritas. Toca el corazón en una canción.")
                        .foregroundStyle(.secondary)
                }
                ForEach(favoriteSongs) { song in
                    SongRowView(song: song) {
                        player.play(song: song, in: favoriteSongs)
                    }
                }
            }
            Section("Playlists favoritas") {
                let favs = store.meta.favoritePlaylists.compactMap { id in store.playlists.first { $0.id == id } }
                if favs.isEmpty {
                    Text("Sin playlists favoritas.")
                        .foregroundStyle(.secondary)
                }
                ForEach(favs) { playlist in
                    NavigationLink(playlist.name) {
                        PlaylistDetailView(playlist: playlist)
                    }
                }
            }
            Section("Álbumes favoritos") {
                if store.meta.favoriteAlbums.isEmpty {
                    Text("Sin álbumes favoritos.")
                        .foregroundStyle(.secondary)
                }
                ForEach(store.meta.favoriteAlbums, id: \.self) { album in
                    NavigationLink(album) {
                        AlbumDetailView(album: album)
                    }
                }
            }
            Section("Artistas favoritos") {
                if store.meta.favoriteArtists.isEmpty {
                    Text("Sin artistas favoritos.")
                        .foregroundStyle(.secondary)
                }
                ForEach(store.meta.favoriteArtists, id: \.self) { artist in
                    NavigationLink(artist) {
                        ArtistDetailView(artist: artist)
                    }
                }
            }
        }
        .navigationTitle("Favoritos")
    }
}
