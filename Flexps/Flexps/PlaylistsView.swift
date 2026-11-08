import SwiftUI

// MARK: - Playlists (renderPlaylistsView en la web, index.html:3565)
struct PlaylistsView: View {
    @EnvironmentObject var store: LibraryStore
    @State private var showCreate = false
    @State private var newName = ""

    var body: some View {
        List {
            if store.playlists.isEmpty {
                Text("Aún no tienes playlists. Crea una y agrega canciones desde cualquier canción.")
                    .foregroundStyle(.secondary)
            }
            ForEach(store.playlists) { playlist in
                NavigationLink {
                    PlaylistDetailView(playlist: playlist)
                } label: {
                    HStack(spacing: 12) {
                        CoverView(song: store.coverForSongs(store.songsForPlaylist(playlist)), size: 52)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(playlist.name)
                                .lineLimit(1)
                            Text("\(playlist.songIds.count) canciones")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if store.isEntityFavorite(type: .playlist, key: playlist.id) {
                            Image(systemName: "heart.fill")
                                .foregroundStyle(.red)
                                .font(.caption)
                        }
                    }
                }
                .swipeActions {
                    Button(role: .destructive) {
                        store.deletePlaylist(playlist)
                    } label: {
                        Label("Eliminar", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Playlists")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showCreate = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .alert("Nueva playlist", isPresented: $showCreate) {
            TextField("Nombre", text: $newName)
            Button("Crear") {
                guard !newName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                _ = store.createPlaylist(name: newName)
                newName = ""
            }
            Button("Cancelar", role: .cancel) { newName = "" }
        } message: {
            Text("Ponle un nombre a tu playlist.")
        }
    }
}

// MARK: - Detalle de playlist (renderPlaylistDetail en la web, index.html:3622)
struct PlaylistDetailView: View {
    var playlist: Playlist
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var player: PlayerManager
    @State private var showRename = false
    @State private var newName = ""

    private var livePlaylist: Playlist? {
        store.playlists.first { $0.id == playlist.id }
    }

    private var playlistSongs: [Song] {
        guard let livePlaylist else { return [] }
        return store.songsForPlaylist(livePlaylist)
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    CoverView(song: store.coverForSongs(playlistSongs), size: 160)
                    Text(playlist.name)
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("\(playlistSongs.count) canciones")
                        .foregroundStyle(.secondary)
                    HStack(spacing: 16) {
                        Button {
                            player.playShuffled(playlistSongs)
                        } label: {
                            Label("Aleatorio", systemImage: "shuffle")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(playlistSongs.isEmpty)
                        Button {
                            store.toggleEntityFavorite(type: .playlist, key: playlist.id)
                        } label: {
                            Label("Favorito", systemImage: store.isEntityFavorite(type: .playlist, key: playlist.id) ? "heart.fill" : "heart")
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }
            ForEach(playlistSongs) { song in
                SongRowView(song: song) {
                    player.play(song: song, in: playlistSongs)
                }
                .swipeActions {
                    Button(role: .destructive) {
                        if let livePlaylist {
                            store.removeSong(song, from: livePlaylist)
                        }
                    } label: {
                        Label("Quitar", systemImage: "minus.circle")
                    }
                }
            }
            if playlistSongs.isEmpty {
                Text("Esta playlist está vacía. Agrega canciones desde el menú de cualquier canción.")
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.plain)
        .navigationTitle(playlist.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        newName = playlist.name
                        showRename = true
                    } label: {
                        Label("Renombrar", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        store.deletePlaylist(playlist)
                    } label: {
                        Label("Eliminar playlist", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .alert("Renombrar playlist", isPresented: $showRename) {
            TextField("Nombre", text: $newName)
            Button("Guardar") {
                guard !newName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                store.renamePlaylist(playlist, newName: newName)
            }
            Button("Cancelar", role: .cancel) { }
        }
        .onAppear {
            store.markPlaylistRecent(playlist.id)
        }
    }
}
