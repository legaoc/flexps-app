import SwiftUI

// MARK: - Para ti (renderForYou en la web, index.html:3234)
// Más reproducidas, favoritas de la semana, álbumes recién agregados,
// artistas recién agregados.
struct ForYouView: View {
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var player: PlayerManager

    private var mostPlayed: [Song] {
        store.songs
            .filter { $0.playCount > 0 }
            .sorted { $0.playCount > $1.playCount }
            .prefix(10)
            .map { $0 }
    }

    private var weekFavorites: [Song] {
        let weekAgo = Date().timeIntervalSince1970 * 1000 - 7 * 24 * 60 * 60 * 1000
        return store.songs
            .filter { $0.favorite && ($0.favoritedAt ?? 0) >= weekAgo }
            .sorted { ($0.favoritedAt ?? 0) > ($1.favoritedAt ?? 0) }
    }

    private var recentAlbums: [(name: String, latest: TimeInterval)] {
        var map: [String: TimeInterval] = [:]
        for song in store.songs {
            let album = song.displayAlbum
            map[album] = max(map[album] ?? 0, song.addedAt)
        }
        return map.map { (name: $0.key, latest: $0.value) }
            .sorted { $0.latest > $1.latest }
            .prefix(10)
            .map { $0 }
    }

    private var recentArtists: [(name: String, latest: TimeInterval)] {
        var map: [String: TimeInterval] = [:]
        for song in store.songs {
            let artist = song.displayArtist
            map[artist] = max(map[artist] ?? 0, song.addedAt)
        }
        return map.map { (name: $0.key, latest: $0.value) }
            .sorted { $0.latest > $1.latest }
            .prefix(10)
            .map { $0 }
    }

    var body: some View {
        List {
            if store.songs.isEmpty {
                Text("Cuando tengas música en tu biblioteca, aquí verás tus más reproducidas y tus favoritas de la semana.")
                    .foregroundStyle(.secondary)
            }
            if !mostPlayed.isEmpty {
                Section("Más reproducidas") {
                    ForEach(Array(mostPlayed.enumerated()), id: \.element.id) { index, song in
                        HStack(spacing: 12) {
                            Text("\(index + 1)")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                                .frame(width: 24)
                            SongRowView(song: song) {
                                player.play(song: song, in: mostPlayed)
                            }
                        }
                    }
                }
            }
            if !weekFavorites.isEmpty {
                Section("Favoritas de la semana") {
                    ForEach(weekFavorites) { song in
                        SongRowView(song: song) {
                            player.play(song: song, in: weekFavorites)
                        }
                    }
                }
            }
            if !recentAlbums.isEmpty {
                Section("Álbumes recién agregados") {
                    ForEach(recentAlbums, id: \.name) { album in
                        NavigationLink {
                            AlbumDetailView(album: album.name)
                        } label: {
                            HStack(spacing: 12) {
                                CoverView(song: store.coverForSongs(store.songsByAlbum(album.name)), size: 52)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(album.name).lineLimit(1)
                                    Text(store.songsByAlbum(album.name).first?.displayArtist ?? "")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                }
            }
            if !recentArtists.isEmpty {
                Section("Artistas recién agregados") {
                    ForEach(recentArtists, id: \.name) { artist in
                        NavigationLink {
                            ArtistDetailView(artist: artist.name)
                        } label: {
                            HStack(spacing: 12) {
                                CoverView(song: store.coverForSongs(store.songsByArtist(artist.name)), size: 52)
                                Text(artist.name).lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Para ti")
    }
}
