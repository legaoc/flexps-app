import Foundation

// MARK: - Letras con LRCLib
// Web: https://lrclib.net/api/get?artist_name&track_name&album_name&duration
// (index.html:4729 y 4849), con caché en el store "lyrics".
enum LyricsService {

    struct FetchedLyrics {
        var plainLyrics: String
        var syncedLyrics: String
    }

    /// Busca la letra de una canción en LRCLib. Devuelve nil si no hay.
    static func fetchLyrics(title: String, artist: String, album: String, duration: Double) async -> FetchedLyrics? {
        let t = title.trimmingCharacters(in: .whitespaces)
        let a = artist.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, !a.isEmpty else { return nil }
        var components = URLComponents(string: "https://lrclib.net/api/get")
        var items = [
            URLQueryItem(name: "track_name", value: t),
            URLQueryItem(name: "artist_name", value: a)
        ]
        let al = album.trimmingCharacters(in: .whitespaces)
        if !al.isEmpty { items.append(URLQueryItem(name: "album_name", value: al)) }
        if duration > 0 { items.append(URLQueryItem(name: "duration", value: String(Int(duration.rounded())))) }
        components?.queryItems = items
        guard let url = components?.url else { return nil }
        do {
            var request = URLRequest(url: url)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            let plain = json["plainLyrics"] as? String ?? ""
            let synced = json["syncedLyrics"] as? String ?? ""
            guard !plain.isEmpty || !synced.isEmpty else { return nil }
            return FetchedLyrics(plainLyrics: plain, syncedLyrics: synced)
        } catch {
            return nil
        }
    }

    /// Parsea LRC "[mm:ss.xx] texto" en líneas ordenadas por tiempo.
    /// Ignora etiquetas de metadatos como [ti:...], [ar:...], [length:...].
    static func parseLRC(_ lrc: String) -> [LyricLine] {
        var lines: [LyricLine] = []
        let pattern = #"^\[(\d+):(\d+(?:\.\d+)?)\]\s*(.*)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        for raw in lrc.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            let range = NSRange(line.startIndex..., in: line)
            guard let match = regex.firstMatch(in: line, range: range),
                  let minRange = Range(match.range(at: 1), in: line),
                  let secRange = Range(match.range(at: 2), in: line),
                  let textRange = Range(match.range(at: 3), in: line) else { continue }
            let minutes = Double(line[minRange]) ?? 0
            let seconds = Double(line[secRange]) ?? 0
            let text = String(line[textRange]).trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            lines.append(LyricLine(time: minutes * 60 + seconds, text: text))
        }
        return lines.sorted { $0.time < $1.time }
    }

    /// Índice de la línea activa para un tiempo dado, o nil si aún no empieza.
    static func activeLineIndex(lines: [LyricLine], at time: Double) -> Int? {
        var active: Int? = nil
        for (index, line) in lines.enumerated() where line.time <= time {
            active = index
        }
        return active
    }
}
