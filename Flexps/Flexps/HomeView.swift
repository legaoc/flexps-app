import SwiftUI

// MARK: - Inicio (renderHome en la web, index.html:3160)
// Acceso a YouTube, playlists recientes, álbumes recientes,
// y acceso a Para ti, Canciones, Artistas y Álbumes.
struct HomeView: View {
    @Binding var showImporter: Bool
    @Binding var showSettings: Bool

    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var player: PlayerManager
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    if store.songs.isEmpty {
                        emptyState
                    } else {
                        youTubeCard
                        recentPlaylistsSection
                        recentAlbumsSection
                        browseSection
                    }
                }
                .padding()
            }
            .navigationTitle("iPlayerPod")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .navigationDestination(for: HomeDestination.self) { destination in
                switch destination {
                case .songs:
                    SongsListView()
                case .artists:
                    ArtistsListView()
                case .albums:
                    AlbumsListView()
                case .forYou:
                    ForYouView()
                case .youTube:
                    YouTubeView()
                case .playlist(let id):
                    if let playlist = store.playlists.first(where: { $0.id == id }) {
                        PlaylistDetailView(playlist: playlist)
                    }
                case .album(let name):
                    AlbumDetailView(album: name)
                case .artist(let name):
                    ArtistDetailView(artist: name)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Tu música,")
                .font(.largeTitle)
                .fontWeight(.bold)
            Text("en un solo lugar.")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundStyle(.secondary)
            Text("\(store.songs.count) canciones · \(store.playlists.count) playlists")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "music.note.list")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Aún no hay música")
                .font(.headline)
            Text("Importa tus archivos MP3, M4A, WAV, AAC o FLAC para empezar tu biblioteca.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                showImporter = true
            } label: {
                Label("Importar música", systemImage: "square.and.arrow.down")
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var youTubeCard: some View {
        Button {
            path.append(HomeDestination.youTube)
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.red)
                        .frame(width: 52, height: 52)
                    Image(systemName: "play.fill")
                        .foregroundStyle(.white)
                        .font(.title3)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("YouTube")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("Busca o pega un enlace para reproducir")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color.secondary.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private var recentPlaylistsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "Playlists recientes", destination: nil)
            if store.meta.recentPlaylists.isEmpty {
                Text("Tus playlists recientes aparecerán aquí.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(store.meta.recentPlaylists.compactMap { id in store.playlists.first { $0.id == id } }) { playlist in
                            recentCard(
                                title: playlist.name,
                                subtitle: "\(store.songsForPlaylist(playlist).count) canciones",
                                coverSong: store.coverForSongs(store.songsForPlaylist(playlist))
                            ) {
                                path.append(HomeDestination.playlist(id: playlist.id))
                            }
                        }
                    }
                }
            }
        }
    }

    private var recentAlbumsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "Álbumes recientes", destination: nil)
            if store.meta.recentAlbums.isEmpty {
                Text("Tus álbumes recientes aparecerán aquí.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(store.meta.recentAlbums, id: \.self) { album in
                            let albumSongs = store.songsByAlbum(album)
                            recentCard(
                                title: album,
                                subtitle: albumSongs.first?.displayArtist ?? "",
                                coverSong: store.coverForSongs(albumSongs)
                            ) {
                                path.append(HomeDestination.album(name: album))
                            }
                        }
                    }
                }
            }
        }
    }

    private var browseSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Explorar")
                .font(.title3)
                .fontWeight(.semibold)
            VStack(spacing: 0) {
                browseRow(title: "Para ti", icon: "sparkles", destination: .forYou)
                browseRow(title: "Canciones", icon: "music.note", destination: .songs)
                browseRow(title: "Artistas", icon: "person.crop.circle", destination: .artists)
                browseRow(title: "Álbumes", icon: "square.stack", destination: .albums)
            }
            .background(Color.secondary.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            Button {
                showImporter = true
            } label: {
                Label(store.isImporting ? store.importStatus : "Importar música", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)
            if store.isImporting {
                ProgressView(value: store.importProgress)
            }
        }
    }

    private func browseRow(title: String, icon: String, destination: HomeDestination) -> some View {
        Button {
            path.append(destination)
        } label: {
            HStack {
                Image(systemName: icon)
                    .frame(width: 28)
                    .foregroundStyle(.accentColor)
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .buttonStyle(.plain)
    }

    private func sectionHeader(title: String, destination: HomeDestination?) -> some View {
        HStack {
            Text(title)
                .font(.title3)
                .fontWeight(.semibold)
            Spacer()
        }
    }

    private func recentCard(title: String, subtitle: String, coverSong: Song?, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                CoverView(song: coverSong, size: 140)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 140, alignment: .leading)
        }
        .buttonStyle(.plain)
    }
}

enum HomeDestination: Hashable {
    case songs, artists, albums, forYou, youTube
    case playlist(id: String)
    case album(name: String)
    case artist(name: String)
}
