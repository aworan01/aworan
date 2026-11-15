import Foundation

enum WatchlyError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

actor Catalogue {
    static let shared = Catalogue()
    private var cache: [String: (Date, Data)] = [:]
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 40
        return URLSession(configuration: config)
    }()
    private func fetch<T: Decodable>(_ url: URL, as type: T.Type, cacheFor seconds: Double = 0) async throws -> T {
        if let cached = cache[url.absoluteString], Date().timeIntervalSince(cached.0) < seconds {
            return try JSONDecoder().decode(type, from: cached.1)
        }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw WatchlyError.message("The catalogue or source provider is unavailable. Try again later.")
        }
        let result = try JSONDecoder().decode(type, from: data)
        if seconds > 0 { cache[url.absoluteString] = (Date(), data) }
        return result
    }
    private func encoded(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
    }
    struct Titles: Decodable { var metas: [MediaTitle] }
    struct Detail: Decodable { var meta: MediaTitle }
    struct Streams: Decodable { var streams: [StreamSource] }

    func shelf(type: String, genre: String? = nil) async throws -> [MediaTitle] {
        let filter = genre.map { "/genre=\(encoded($0))" } ?? ""
        let url = URL(string: "https://cinemeta-catalogs.strem.io/top/catalog/\(type)/top\(filter).json")!
        return try await fetch(url, as: Titles.self, cacheFor: 3600).metas
    }
    func search(_ query: String, type: String) async throws -> [MediaTitle] {
        let url = URL(string: "https://v3-cinemeta.strem.io/catalog/\(type)/top/search=\(encoded(query)).json")!
        return try await fetch(url, as: Titles.self, cacheFor: 300).metas
    }
    func detail(_ media: MediaTitle) async throws -> MediaTitle {
        let url = URL(string: "https://v3-cinemeta.strem.io/meta/\(encoded(media.type))/\(encoded(media.id)).json")!
        return try await fetch(url, as: Detail.self, cacheFor: 3600).meta
    }
    func sources(_ media: MediaTitle, episode: Episode?, base: String) async throws -> [StreamSource] {
        guard let root = URL(string: base.trimmingCharacters(in: .whitespacesAndNewlines)), root.scheme == "https", root.host != nil else {
            throw WatchlyError.message("Enter a valid HTTPS source-provider address in Settings.")
        }
        let id = episode.map { "\(media.id):\($0.season):\($0.episode)" } ?? media.id
        let url = root.appendingPathComponent("stream").appendingPathComponent(media.type).appendingPathComponent(id + ".json")
        let found = try await fetch(url, as: Streams.self).streams.filter { $0.location != nil }
        var seen = Set<String>()
        return found.filter { seen.insert($0.id).inserted }
    }
    struct Intro: Decodable {
        var start_sec: Double?
        var end_sec: Double?
        var start_ms: Double?
        var end_ms: Double?
        var start: Double { start_sec ?? (start_ms ?? 0) / 1000 }
        var end: Double { end_sec ?? (end_ms ?? 0) / 1000 }
    }
    struct Segments: Decodable { var intro: Intro? }
    func intro(_ media: MediaTitle, episode: Episode) async -> Intro? {
        guard media.id.hasPrefix("tt") else { return nil }
        let url = URL(string: "https://api.introdb.app/segments?imdb_id=\(encoded(media.id))&season=\(episode.season)&episode=\(episode.episode)")!
        guard let value = try? await fetch(url, as: Segments.self, cacheFor: 86400).intro,
              value.start.isFinite, value.end.isFinite, value.start >= 0, value.end > value.start else { return nil }
        return value
    }
}
