import Foundation

// MARK: - YouTube
// Web: api/youtube-search.js (YouTube Data API v3, part=snippet, type=video,
// videoEmbeddable=true, videoCategoryId=10, maxResults=12) y
// songFromYouTubeLink() con oEmbed (index.html:4532), que funciona sin clave.
// En la app Swift NO hay servidor Vercel propio: la búsqueda llama directo a
// googleapis.com con la clave que el usuario pega en Ajustes
// (guardada en UserDefaults, nunca en el repo).
enum YouTubeService {

    enum YouTubeError: LocalizedError {
        case noAPIKey
        case invalidResponse(String)
        case network

        var errorDescription: String? {
            switch self {
            case .noAPIKey:
                return "La búsqueda necesita tu clave de YouTube Data API v3. Pégala en Ajustes → YouTube, o pega un enlace de YouTube para reproducir sin clave."
            case .invalidResponse(let message):
                return message.isEmpty ? "YouTube no respondió." : message
            case .network:
                return "No se pudo conectar con YouTube."
            }
        }
    }

    /// Extrae el videoId de cualquier enlace de YouTube (watch, youtu.be, shorts, embed).
    static func parseVideoId(_ value: String) -> String? {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let patterns = [
            #"(?:youtube\.com/(?:watch\?[^#]*v=|embed/|v/|shorts/))([A-Za-z0-9_-]{11})"#,
            #"youtu\.be/([A-Za-z0-9_-]{11})"#,
            #"^([A-Za-z0-9_-]{11})$"#
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range(at: 1), in: text) {
                return String(text[range])
            }
        }
        return nil
    }

    /// Resuelve un enlace pegado vía oEmbed (sin clave), como la web.
    static func trackFromLink(_ value: String) async -> YouTubeTrack? {
        guard let videoId = parseVideoId(value) else { return nil }
        var title = "YouTube"
        var artist = "YouTube"
        var cover: String? = nil
        let oembed = "https://www.youtube.com/oembed?format=json&url=" +
            ("https://www.youtube.com/watch?v=\(videoId)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")
        if let url = URL(string: oembed),
           let (data, response) = try? await URLSession.shared.data(from: url),
           (response as? HTTPURLResponse)?.statusCode == 200,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            title = json["title"] as? String ?? title
            artist = json["author_name"] as? String ?? artist
            cover = json["thumbnail_url"] as? String
        }
        return YouTubeTrack(videoId: videoId, title: title, artist: artist, cover: cover)
    }

    /// Búsqueda con la clave del usuario (mismos parámetros que api/youtube-search.js).
    static func search(query: String, apiKey: String) async throws -> [YouTubeTrack] {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw YouTubeError.noAPIKey }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        var components = URLComponents(string: "https://www.googleapis.com/youtube/v3/search")
        components?.queryItems = [
            URLQueryItem(name: "part", value: "snippet"),
            URLQueryItem(name: "type", value: "video"),
            URLQueryItem(name: "videoEmbeddable", value: "true"),
            URLQueryItem(name: "videoCategoryId", value: "10"),
            URLQueryItem(name: "maxResults", value: "12"),
            URLQueryItem(name: "q", value: q),
            URLQueryItem(name: "key", value: key)
        ]
        guard let url = components?.url else { throw YouTubeError.network }
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(from: url)
        } catch {
            throw YouTubeError.network
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw YouTubeError.network
        }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            let message = (json["error"] as? [String: Any])?["message"] as? String ?? ""
            throw YouTubeError.invalidResponse(message)
        }
        let items = json["items"] as? [[String: Any]] ?? []
        return items.compactMap { item -> YouTubeTrack? in
            guard let videoId = (item["id"] as? [String: Any])?["videoId"] as? String else { return nil }
            let snippet = item["snippet"] as? [String: Any] ?? [:]
            let thumbs = snippet["thumbnails"] as? [String: Any]
            let cover = (thumbs?["high"] as? [String: Any])?["url"] as? String
                ?? (thumbs?["medium"] as? [String: Any])?["url"] as? String
                ?? (thumbs?["default"] as? [String: Any])?["url"] as? String
            return YouTubeTrack(
                videoId: videoId,
                title: snippet["title"] as? String ?? "YouTube",
                artist: snippet["channelTitle"] as? String ?? "YouTube",
                cover: cover
            )
        }
    }
}
