import AVFoundation
import Foundation
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Biblioteca local
// Web: IndexedDB MusiquitaDB v5, stores songs, playlists, meta, lyrics.
// Aquí: JSON en Documents/library.json (metadatos, playlists, meta, letras)
// + archivos de audio en Documents/Music/<id>.<ext>
// + portadas en Documents/Covers/. Sin SwiftData, sin Firebase, sin login.
@MainActor
final class LibraryStore: ObservableObject {

    @Published var songs: [Song] = []
    @Published var playlists: [Playlist] = []
    @Published var meta: LibraryMeta = LibraryMeta()
    @Published var lyricsCache: [LyricsCacheEntry] = []
    @Published var isImporting = false
    @Published var importStatus: String = ""
    @Published var importProgress: Double = 0

    /// Últimos 40 tracks de YouTube en memoria (como la web, no persistentes).
    @Published var recentYouTube: [YouTubeTrack] = []

    static let supportedExtensions: Set<String> = ["mp3", "mp4", "m4a", "wav", "aac", "flac"]

    private let fileManager = FileManager.default

    var documentsDir: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    var libraryFile: URL { documentsDir.appendingPathComponent("library.json") }
    var musicDir: URL { documentsDir.appendingPathComponent("Music") }
    var coversDir: URL { documentsDir.appendingPathComponent("Covers") }

    init() {
        load()
    }

    // MARK: - Persistencia

    func load() {
        guard let data = try? Data(contentsOf: libraryFile),
              let decoded = try? JSONDecoder().decode(LibraryData.self, from: data) else { return }
        songs = decoded.songs
        playlists = decoded.playlists
        meta = decoded.meta
        lyricsCache = decoded.lyrics
    }

    func save() {
        let data = LibraryData(songs: songs, playlists: playlists, meta: meta, lyrics: lyricsCache)
        do {
            try fileManager.createDirectory(at: musicDir, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: coversDir, withIntermediateDirectories: true)
            let encoded = try JSONEncoder().encode(data)
            try encoded.write(to: libraryFile, options: .atomic)
        } catch {
            // Si el guardado falla, los datos en memoria siguen vigentes.
        }
    }

    // MARK: - Archivos de audio y portadas

    func localFileURL(for song: Song) -> URL {
        musicDir.appendingPathComponent("\(song.id).\(song.fileExtension)")
    }

    func coverImageData(for song: Song) -> Data? {
        if let fileName = song.coverFileName {
            return try? Data(contentsOf: coversDir.appendingPathComponent(fileName))
        }
        if let base64 = song.cover, let data = Data(base64Encoded: base64) {
            return data
        }
        return nil
    }

    func coverURL(for song: Song) -> URL? {
        guard let albumCover = song.albumCover else { return nil }
        return URL(string: albumCover)
    }

    // MARK: - Importar

    /// Importa archivos elegidos con fileImporter. Copia cada archivo a
    /// Documents/Music con startAccessingSecurityScopedResource; nunca se
    /// guarda la URL original (igual que la web guarda el Blob en IndexedDB).
    func importFiles(_ urls: [URL]) async {
        guard !urls.isEmpty else { return }
        isImporting = true
        importProgress = 0
        var imported = 0
        for (index, url) in urls.enumerated() {
            importStatus = "Importando \(index + 1) de \(urls.count)…"
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            if await importOne(url) { imported += 1 }
            importProgress = Double(index + 1) / Double(urls.count)
        }
        save()
        importStatus = imported > 0 ? "Se importaron \(imported) canciones." : "No se pudo importar ninguna canción."
        isImporting = false
    }

    private func importOne(_ url: URL) async -> Bool {
        let ext = url.pathExtension.lowercased()
        guard Self.supportedExtensions.contains(ext) else { return false }
        let fileName = url.lastPathComponent
        let fileSize = (try? fileManager.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        let metadata = await MetadataService.extract(from: url)
        let guessed = MetadataService.guessTrackInfo(from: fileName)
        let song = Song(
            name: fileName,
            type: mimeType(forExtension: ext),
            size: fileSize,
            duration: metadata.duration,
            title: metadata.title?.isEmpty == false ? metadata.title! : guessed.title,
            artist: metadata.artist?.isEmpty == false ? metadata.artist! : guessed.artist,
            album: metadata.album ?? ""
        )
        do {
            try fileManager.createDirectory(at: musicDir, withIntermediateDirectories: true)
            let dest = localFileURL(for: song)
            if fileManager.fileExists(atPath: dest.path) {
                try fileManager.removeItem(at: dest)
            }
            try fileManager.copyItem(at: url, to: dest)
        } catch {
            return false
        }
        var finalSong = song
        // Portada embebida: se guarda como archivo en Covers/ si existe.
        if let artwork = metadata.artworkData {
            try? fileManager.createDirectory(at: coversDir, withIntermediateDirectories: true)
            let coverName = "\(song.id).jpg"
            if (try? artwork.write(to: coversDir.appendingPathComponent(coverName), options: .atomic)) != nil {
                finalSong.coverFileName = coverName
            } else if artwork.count < 200_000 {
                finalSong.cover = artwork.base64EncodedString()
            }
        }
        songs.append(finalSong)
        // Enriquecer con Deezer en segundo plano, como updateSongInfo() en la web.
        Task { await enrichWithDeezer(songId: finalSong.id) }
        return true
    }

    private func mimeType(forExtension ext: String) -> String {
        switch ext {
        case "mp3": return "audio/mpeg"
        case "m4a", "aac": return "audio/aac"
        case "wav": return "audio/wav"
        case "flac": return "audio/flac"
        case "mp4": return "audio/mp4"
        default: return "audio/mpeg"
        }
    }

    func deleteSong(_ song: Song) {
        songs.removeAll { $0.id == song.id }
        for index in playlists.indices {
            playlists[index].songIds.removeAll { $0 == song.id }
        }
        lyricsCache.removeAll { $0.songId == song.id }
        try? fileManager.removeItem(at: localFileURL(for: song))
        if let coverFileName = song.coverFileName {
            try? fileManager.removeItem(at: coversDir.appendingPathComponent(coverFileName))
        }
        save()
    }

    // MARK: - Deezer

    /// Actualiza albumCover, artistImage y releaseDate de una canción
    /// (updateSongInfo() en index.html:2319). No toca título/artista/álbum.
    func enrichWithDeezer(songId: String, force: Bool = false) async {
        guard let index = songs.firstIndex(where: { $0.id == songId }) else { return }
        let song = songs[index]
        if !force, song.infoSource == "deezer", song.albumCover != nil { return }
        let result = await MetadataService.searchMusicInfo(title: song.title, artist: song.artist, album: song.album)
        guard result.found else { return }
        guard let current = songs.firstIndex(where: { $0.id == songId }) else { return }
        songs[current].albumCover = result.albumCover
        songs[current].artistImage = result.artistImage
        songs[current].releaseDate = result.releaseDate
        songs[current].infoSource = "deezer"
        if let albumCover = result.albumCover {
            let fileName = "\(songId)-album.jpg"
            if await MetadataService.downloadCover(urlString: albumCover, fileName: fileName, coversDir: coversDir) != nil {
                songs[current].coverFileName = fileName
            }
        }
        save()
    }

    /// "Actualizar información" en Ajustes: recorre toda la biblioteca.
    func updateAllInfo() async -> (updated: Int, total: Int) {
        var updated = 0
        for song in songs {
            let before = song.albumCover
            await enrichWithDeezer(songId: song.id, force: true)
            if songs.first(where: { $0.id == song.id })?.albumCover != before { updated += 1 }
        }
        return (updated, songs.count)
    }

    // MARK: - Letras

    func cachedLyrics(for song: Song) -> LyricsCacheEntry? {
        lyricsCache.first { $0.songId == song.id }
    }

    func fetchLyrics(for song: Song) async -> LyricsCacheEntry? {
        if let cached = cachedLyrics(for: song), !cached.plainLyrics.isEmpty || !cached.syncedLyrics.isEmpty {
            return cached
        }
        guard let fetched = await LyricsService.fetchLyrics(
            title: song.title, artist: song.artist, album: song.album, duration: song.duration
        ) else {
            let empty = LyricsCacheEntry(songId: song.id, title: song.title, artist: song.artist,
                                         album: song.album, plainLyrics: "", syncedLyrics: "",
                                         savedAt: Date().timeIntervalSince1970 * 1000)
            lyricsCache.removeAll { $0.songId == song.id }
            lyricsCache.append(empty)
            save()
            return nil
        }
        let entry = LyricsCacheEntry(songId: song.id, title: song.title, artist: song.artist,
                                     album: song.album, plainLyrics: fetched.plainLyrics,
                                     syncedLyrics: fetched.syncedLyrics,
                                     savedAt: Date().timeIntervalSince1970 * 1000)
        lyricsCache.removeAll { $0.songId == song.id }
        lyricsCache.append(entry)
        save()
        return entry
    }

    /// "Actualizar letras" en Ajustes: busca la letra de toda la biblioteca.
    func updateAllLyrics() async -> (found: Int, total: Int) {
        var found = 0
        for song in songs {
            if await fetchLyrics(for: song) != nil { found += 1 }
        }
        return (found, songs.count)
    }

    // MARK: - Favoritos y recientes

    func toggleSongFavorite(_ song: Song) {
        guard let index = songs.firstIndex(where: { $0.id == song.id }) else { return }
        songs[index].favorite.toggle()
        songs[index].favoritedAt = songs[index].favorite ? Date().timeIntervalSince1970 * 1000 : nil
        save()
    }

    func toggleEntityFavorite(type: FavoriteEntityType, key: String) {
        switch type {
        case .playlist:
            if meta.favoritePlaylists.contains(key) { meta.favoritePlaylists.removeAll { $0 == key } }
            else { meta.favoritePlaylists.append(key) }
        case .album:
            if meta.favoriteAlbums.contains(key) { meta.favoriteAlbums.removeAll { $0 == key } }
            else { meta.favoriteAlbums.append(key) }
        case .artist:
            if meta.favoriteArtists.contains(key) { meta.favoriteArtists.removeAll { $0 == key } }
            else { meta.favoriteArtists.append(key) }
        }
        save()
    }

    func isEntityFavorite(type: FavoriteEntityType, key: String) -> Bool {
        switch type {
        case .playlist: return meta.favoritePlaylists.contains(key)
        case .album: return meta.favoriteAlbums.contains(key)
        case .artist: return meta.favoriteArtists.contains(key)
        }
    }

    /// touchRecent() en la web (index.html:3085): mueve al frente, máx. 12.
    func touchRecent(list: inout [String], key: String, limit: Int = 12) {
        list.removeAll { $0 == key }
        list.insert(key, at: 0)
        if list.count > limit { list = Array(list.prefix(limit)) }
    }

    func markPlaylistRecent(_ id: String) {
        touchRecent(list: &meta.recentPlaylists, key: id)
        save()
    }

    func markAlbumRecent(_ album: String) {
        touchRecent(list: &meta.recentAlbums, key: album)
        save()
    }

    // MARK: - Agrupaciones (renderGroupList en la web, index.html:3333)

    var artists: [String] {
        Array(Set(songs.map { $0.displayArtist })).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var albums: [String] {
        Array(Set(songs.map { $0.displayAlbum })).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func songsByArtist(_ artist: String) -> [Song] {
        songs.filter { $0.displayArtist == artist }
    }

    func songsByAlbum(_ album: String) -> [Song] {
        songs.filter { $0.displayAlbum == album }
    }

    func songsForPlaylist(_ playlist: Playlist) -> [Song] {
        playlist.songIds.compactMap { id in songs.first { $0.id == id } }
    }

    func coverForSongs(_ list: [Song]) -> Song? {
        list.first { $0.coverFileName != nil || $0.cover != nil || $0.albumCover != nil } ?? list.first
    }

    // MARK: - Playlists CRUD

    func createPlaylist(name: String) -> Playlist {
        let playlist = Playlist(name: name.trimmingCharacters(in: .whitespacesAndNewlines))
        playlists.append(playlist)
        save()
        return playlist
    }

    func renamePlaylist(_ playlist: Playlist, newName: String) {
        guard let index = playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        playlists[index].name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        save()
    }

    func deletePlaylist(_ playlist: Playlist) {
        playlists.removeAll { $0.id == playlist.id }
        meta.recentPlaylists.removeAll { $0 == playlist.id }
        meta.favoritePlaylists.removeAll { $0 == playlist.id }
        save()
    }

    func addSong(_ song: Song, to playlist: Playlist) {
        guard let index = playlists.firstIndex(where: { $0.id == playlist.id }),
              !playlists[index].songIds.contains(song.id) else { return }
        playlists[index].songIds.append(song.id)
        save()
    }

    func removeSong(_ song: Song, from playlist: Playlist) {
        guard let index = playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        playlists[index].songIds.removeAll { $0 == song.id }
        save()
    }

    func addSong(_ song: Song, toPlaylistId id: String) {
        guard let playlist = playlists.first(where: { $0.id == id }) else { return }
        addSong(song, to: playlist)
    }

    // MARK: - YouTube recientes

    func rememberYouTube(_ track: YouTubeTrack) {
        recentYouTube.removeAll { $0.videoId == track.videoId }
        recentYouTube.insert(track, at: 0)
        if recentYouTube.count > 40 { recentYouTube = Array(recentYouTube.prefix(40)) }
    }

    // MARK: - Almacenamiento y borrado

    /// Tamaño total ocupado por la biblioteca (archivos + JSON + portadas).
    func storageSize() -> Int64 {
        var total: Int64 = 0
        for dir in [musicDir, coversDir] {
            guard let enumerator = fileManager.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey]) else { continue }
            for case let url as URL in enumerator {
                // fileSize es Int? y total es Int64: convertir explícitamente.
                total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
        }
        total += Int64((try? libraryFile.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        return total
    }

    func formattedStorageSize() -> String {
        let bytes = storageSize()
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        return String(format: "%.1f MB", Double(bytes) / 1024 / 1024)
    }

    /// "Borrar biblioteca": elimina canciones, playlists, letras y archivos.
    func clearLibrary() {
        songs = []
        playlists = []
        lyricsCache = []
        meta = LibraryMeta()
        recentYouTube = []
        try? fileManager.removeItem(at: musicDir)
        try? fileManager.removeItem(at: coversDir)
        try? fileManager.removeItem(at: libraryFile)
        save()
    }
}

enum FavoriteEntityType {
    case playlist, album, artist
}
