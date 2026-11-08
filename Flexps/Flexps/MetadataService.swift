import AVFoundation
import Foundation
import UIKit

// MARK: - Metadatos al importar
// Web: readDuration() + readTags() (index.html:2015, 2051) con jsmediatags.
// Aquí: AVAsset commonMetadata (título, artista, álbum, artwork) + duration.
enum MetadataService {

    struct ExtractedMetadata {
        var title: String?
        var artist: String?
        var album: String?
        var duration: Double = 0
        var artworkData: Data?
    }

    static func extract(from url: URL) async -> ExtractedMetadata {
        var result = ExtractedMetadata()
        let asset = AVURLAsset(url: url)
        do {
            let duration = try await asset.load(.duration)
            result.duration = duration.seconds.isFinite ? duration.seconds : 0
            let items = try await asset.load(.commonMetadata)
            for item in items {
                guard let key = item.commonKey else { continue }
                switch key {
                case .commonKeyTitle:
                    result.title = try? await item.load(.stringValue)
                case .commonKeyArtist:
                    result.artist = try? await item.load(.stringValue)
                case .commonKeyAlbumName:
                    result.album = try? await item.load(.stringValue)
                case .commonKeyArtwork:
                    result.artworkData = try? await item.load(.dataValue)
                default:
                    break
                }
            }
        } catch {
            // Si AVAsset falla, el importador sigue con el nombre de archivo.
        }
        return result
    }

    /// Limpia el nombre de archivo como guessTrackInfo() en la web (index.html:2176):
    /// quita "(Official Video)", "(Audio)", etc.
    static func cleanFileName(_ name: String) -> String {
        var base = (name as NSString).deletingPathExtension
        let pattern = #"\([^)]*(official|audio|video|lyrics|remix|version)[^)]*\)"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
            base = regex.stringByReplacingMatches(in: base, range: NSRange(base.startIndex..., in: base), withTemplate: "")
        }
        return base.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Si el nombre es "Artista - Título", lo separa. Si no, título = nombre limpio.
    static func guessTrackInfo(from fileName: String) -> (title: String, artist: String) {
        let clean = cleanFileName(fileName)
        let parts = clean.components(separatedBy: " - ")
        if parts.count >= 2 {
            return (parts.dropFirst().joined(separator: " - ").trimmingCharacters(in: .whitespaces),
                    parts[0].trimmingCharacters(in: .whitespaces))
        }
        return (clean, "Artista desconocido")
    }

    // MARK: - Deezer (llamada directa, sin clave)
    // Puerto de api/music-info.js: búsqueda en
    // https://api.deezer.com/search?q=...&limit=25 y scoring por
    // título exacto (+20) / contiene (+8) / contenido en (+5),
    // artista igual, álbum igual (+15/+6/+4), +2 si hay portada,
    // +2 si hay foto de artista.
    static func searchMusicInfo(title: String, artist: String, album: String) async -> MusicInfoResult {
        let found = MusicInfoResult(found: false)
        let t = title.trimmingCharacters(in: .whitespaces)
        let a = artist.trimmingCharacters(in: .whitespaces)
        let al = album.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty || !a.isEmpty || !al.isEmpty else { return found }

        var query: String
        if !a.isEmpty, !t.isEmpty, !al.isEmpty { query = "\(a) \(t) \(al)" }
        else if !a.isEmpty, !t.isEmpty { query = "\(a) \(t)" }
        else if !a.isEmpty, !al.isEmpty { query = "\(a) \(al)" }
        else { query = !a.isEmpty ? a : (!t.isEmpty ? t : al) }

        var components = URLComponents(string: "https://api.deezer.com/search")
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: "25")
        ]
        guard let url = components?.url else { return found }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return found }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let items = json["data"] as? [[String: Any]], !items.isEmpty else {
                return found
            }
            let nt = normalize(t), na = normalize(a), nal = normalize(al)
            var best: [String: Any]? = nil
            var bestScore = -1
            for item in items {
                let it = normalize(item["title"] as? String ?? "")
                let ia = normalize((item["artist"] as? [String: Any])?["name"] as? String ?? "")
                let ial = normalize((item["album"] as? [String: Any])?["title"] as? String ?? "")
                var score = 0
                score += matchScore(needle: nt, haystack: it, exact: 20, contains: 8, contained: 5)
                score += matchScore(needle: na, haystack: ia, exact: 20, contains: 8, contained: 5)
                score += matchScore(needle: nal, haystack: ial, exact: 15, contains: 6, contained: 4)
                let albumDict = item["album"] as? [String: Any]
                let artistDict = item["artist"] as? [String: Any]
                if albumDict?["cover_xl"] != nil || albumDict?["cover_big"] != nil { score += 2 }
                if artistDict?["picture_xl"] != nil || artistDict?["picture_big"] != nil { score += 2 }
                if score > bestScore { bestScore = score; best = item }
            }
            guard let best else { return found }
            let albumDict = best["album"] as? [String: Any]
            let artistDict = best["artist"] as? [String: Any]
            return MusicInfoResult(
                found: true,
                title: best["title"] as? String ?? t,
                artist: artistDict?["name"] as? String ?? a,
                album: albumDict?["title"] as? String ?? al,
                albumCover: (albumDict?["cover_xl"] as? String)
                    ?? (albumDict?["cover_big"] as? String)
                    ?? (albumDict?["cover_medium"] as? String)
                    ?? (albumDict?["cover"] as? String),
                artistImage: (artistDict?["picture_xl"] as? String)
                    ?? (artistDict?["picture_big"] as? String)
                    ?? (artistDict?["picture_medium"] as? String)
                    ?? (artistDict?["picture"] as? String),
                releaseDate: albumDict?["release_date"] as? String
            )
        } catch {
            return found
        }
    }

    private static func matchScore(needle: String, haystack: String, exact: Int, contains: Int, contained: Int) -> Int {
        guard !needle.isEmpty, !haystack.isEmpty else { return 0 }
        if haystack == needle { return exact }
        if haystack.contains(needle) { return contains }
        if needle.contains(haystack) { return contained }
        return 0
    }

    /// Normalización idéntica a normalize() en api/music-info.js:
    /// minúsculas, sin diacríticos, sin puntuación, espacios simples.
    static func normalize(_ value: String) -> String {
        value.lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted).joined(separator: " ")
            .split(separator: " ").joined(separator: " ")
    }

    /// Descarga una imagen de portada/foto y la guarda en Documents/Covers/.
    static func downloadCover(urlString: String, fileName: String, coversDir: URL) async -> String? {
        guard let url = URL(string: urlString) else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty else { return nil }
            try FileManager.default.createDirectory(at: coversDir, withIntermediateDirectories: true)
            let dest = coversDir.appendingPathComponent(fileName)
            try data.write(to: dest, options: .atomic)
            return fileName
        } catch {
            return nil
        }
    }
}
