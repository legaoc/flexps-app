import Foundation

// MARK: - Canción
// Equivale al objeto song de la web (index.html, stores "songs" de MusiquitaDB v5).
struct Song: Identifiable, Codable, Equatable, Hashable {
    var id: String
    var name: String            // nombre de archivo original
    var type: String            // MIME type
    var size: Int64
    var addedAt: TimeInterval   // ms desde epoch, como en la web
    var duration: Double        // segundos
    var title: String
    var artist: String
    var album: String
    var cover: String?          // base64 embebido (solo si es pequeño) o nil
    var coverFileName: String?  // archivo local en Documents/Covers/
    var albumCover: String?     // URL de Deezer
    var artistImage: String?    // URL de Deezer
    var releaseDate: String?
    var infoSource: String?     // "deezer"
    var favorite: Bool
    var favoritedAt: TimeInterval?
    var playCount: Int

    init(id: String = UUID().uuidString, name: String, type: String = "", size: Int64 = 0,
         addedAt: TimeInterval = Date().timeIntervalSince1970 * 1000, duration: Double = 0,
         title: String, artist: String = "Artista desconocido", album: String = "") {
        self.id = id; self.name = name; self.type = type; self.size = size
        self.addedAt = addedAt; self.duration = duration
        self.title = title; self.artist = artist; self.album = album
        self.favorite = false; self.playCount = 0
    }

    var displayTitle: String { title.isEmpty ? name : title }
    var displayArtist: String { artist.isEmpty ? "Artista desconocido" : artist }
    var displayAlbum: String { album.isEmpty ? "Álbum desconocido" : album }

    /// Badge de calidad, misma lógica que qualityLabel() en index.html:2129.
    var qualityLabel: String {
        let t = type.lowercased(), n = name.lowercased()
        if t.contains("flac") || n.hasSuffix(".flac") { return "FLAC" }
        if t.contains("wav") || n.hasSuffix(".wav") { return "WAV" }
        if t.contains("ogg") || n.hasSuffix(".ogg") { return "OGG" }
        if t.contains("mp4") || t.contains("aac") || t.contains("m4a") || n.hasSuffix(".m4a") { return "AAC" }
        if t.contains("mpeg") || t.contains("mp3") || n.hasSuffix(".mp3") { return "MP3" }
        if t.contains("webm") { return "WEBM" }
        return ""
    }

    var fileExtension: String {
        let ext = (name as NSString).pathExtension.lowercased()
        if !ext.isEmpty { return ext }
        let t = type.lowercased()
        if t.contains("flac") { return "flac" }
        if t.contains("wav") { return "wav" }
        if t.contains("aac") || t.contains("m4a") || t.contains("mp4") { return "m4a" }
        return "mp3"
    }

    var formattedDuration: String {
        guard duration > 0 else { return "0:00" }
        let m = Int(duration) / 60, s = Int(duration) % 60
        return "\(m):\(String(format: "%02d", s))"
    }

    var formattedSize: String {
        if size < 1024 { return "\(size) B" }
        if size < 1024 * 1024 { return String(format: "%.1f KB", Double(size) / 1024) }
        return String(format: "%.1f MB", Double(size) / 1024 / 1024)
    }
}

// MARK: - Playlist
struct Playlist: Identifiable, Codable, Equatable, Hashable {
    var id: String
    var name: String
    var songIds: [String]
    var createdAt: TimeInterval

    init(id: String = UUID().uuidString, name: String, songIds: [String] = []) {
        self.id = id; self.name = name; self.songIds = songIds
        self.createdAt = Date().timeIntervalSince1970 * 1000
    }
}

// MARK: - Meta (equivale al store "meta" de MusiquitaDB)
// theme, queue, recentPlaylists, recentAlbums, favoritePlaylists,
// favoriteAlbums, favoriteArtists, crossfadeOn, crossfadeSeconds.
struct LibraryMeta: Codable {
    var theme: String = "system"
    var queue: [String] = []
    var recentPlaylists: [String] = []
    var recentAlbums: [String] = []
    var favoritePlaylists: [String] = []
    var favoriteAlbums: [String] = []
    var favoriteArtists: [String] = []
    var crossfadeOn: Bool = false
    var crossfadeSeconds: Int = 4
}

// MARK: - Letras en caché (store "lyrics" de la web)
struct LyricsCacheEntry: Codable {
    var songId: String
    var title: String
    var artist: String
    var album: String
    var plainLyrics: String
    var syncedLyrics: String
    var savedAt: TimeInterval
}

// MARK: - Biblioteca completa persistida en Documents/library.json
struct LibraryData: Codable {
    var songs: [Song] = []
    var playlists: [Playlist] = []
    var meta: LibraryMeta = LibraryMeta()
    var lyrics: [LyricsCacheEntry] = []
}

// MARK: - Orden (mismo <select id="sort"> de index.html:1390-1397)
enum SortMode: String, CaseIterable, Identifiable {
    case name = "name"          // Canción: A-Z (default en la web)
    case dateNew = "dateNew"    // Adquisición: recientes
    case dateOld = "dateOld"    // Adquisición: antiguas
    case nameZA = "nameZA"      // Canción: Z-A
    case artist = "artist"      // Artista: A-Z
    case artistZA = "artistZA"  // Artista: Z-A
    case size = "size"          // Tamaño

    var id: String { rawValue }
    var label: String {
        switch self {
        case .name: return "Canción: A-Z"
        case .dateNew: return "Adquisición: recientes"
        case .dateOld: return "Adquisición: antiguas"
        case .nameZA: return "Canción: Z-A"
        case .artist: return "Artista: A-Z"
        case .artistZA: return "Artista: Z-A"
        case .size: return "Tamaño"
        }
    }

    func sort(_ list: [Song]) -> [Song] {
        switch self {
        case .name:
            return list.sorted { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending }
        case .nameZA:
            return list.sorted { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedDescending }
        case .artist:
            return list.sorted {
                let r = $0.displayArtist.localizedCaseInsensitiveCompare($1.displayArtist)
                return r == .orderedSame
                    ? $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending
                    : r == .orderedAscending
            }
        case .artistZA:
            return list.sorted {
                let r = $0.displayArtist.localizedCaseInsensitiveCompare($1.displayArtist)
                return r == .orderedSame
                    ? $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending
                    : r == .orderedDescending
            }
        case .dateOld:
            return list.sorted { $0.addedAt < $1.addedAt }
        case .size:
            return list.sorted { $0.size > $1.size }
        case .dateNew:
            return list.sorted { $0.addedAt > $1.addedAt }
        }
    }
}

// MARK: - Repetir / temporizador
enum RepeatMode: String, CaseIterable {
    case off, all, one
    var icon: String {
        switch self {
        case .off: return "repeat"
        case .all: return "repeat"
        case .one: return "repeat.1"
        }
    }
}

enum SleepTimerOption: String, CaseIterable, Identifiable {
    case off, min15 = "15", min30 = "30", min45 = "45", min60 = "60", endOfSong = "end"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .off: return "Apagado"
        case .endOfSong: return "Al terminar la canción"
        default: return "\(rawValue) min"
        }
    }
}

// MARK: - Track de YouTube (últimos 40 en memoria, como en la web)
struct YouTubeTrack: Identifiable, Equatable, Hashable {
    var id: String { videoId }
    var videoId: String
    var title: String
    var artist: String
    var album: String = "YouTube"
    var cover: String?
    var isLocal: Bool = false   // false = YouTube, true = canción local (cola mixta)
}

// MARK: - Resultado de Deezer (api/music-info.js)
struct MusicInfoResult {
    var found: Bool
    var title: String?
    var artist: String?
    var album: String?
    var albumCover: String?
    var artistImage: String?
    var releaseDate: String?
    var source: String = "deezer"
}

// MARK: - Línea de letra sincronizada (LRC)
struct LyricLine: Identifiable, Equatable {
    var id: Int { Int(time * 1000) }
    var time: Double   // segundos
    var text: String
}
