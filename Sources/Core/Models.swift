import Foundation

struct Episode: Codable, Hashable, Identifiable {
    var id: String
    var season: Int
    var episode: Int
    var title: String?
    var overview: String?
    var thumbnail: String?
    var released: String?
    var label: String { String(format: "S%02dE%02d", season, episode) }
}

extension Episode {
    private enum ProviderKeys: String, CodingKey { case id, season, episode, title, name, overview, description, thumbnail, released }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: ProviderKeys.self)
        id = try values.decode(String.self, forKey: .id)
        season = try values.decodeIfPresent(Int.self, forKey: .season) ?? 0
        episode = try values.decodeIfPresent(Int.self, forKey: .episode) ?? 0
        title = try values.decodeIfPresent(String.self, forKey: .title) ?? values.decodeIfPresent(String.self, forKey: .name)
        overview = try values.decodeIfPresent(String.self, forKey: .overview) ?? values.decodeIfPresent(String.self, forKey: .description)
        thumbnail = try values.decodeIfPresent(String.self, forKey: .thumbnail)
        released = try values.decodeIfPresent(String.self, forKey: .released)
    }
}

struct MediaTitle: Codable, Hashable, Identifiable {
    var id: String
    var type: String
    var name: String
    var poster: String?
    var background: String?
    var description: String?
    var releaseInfo: String?
    var imdbRating: String?
    var genres: [String]?
    var cast: [String]?
    var runtime: String?
    var videos: [Episode]?
    var isSeries: Bool { type == "series" }
    var episodes: [Episode] {
        (videos ?? []).filter { $0.season > 0 }.sorted {
            ($0.season, $0.episode) < ($1.season, $1.episode)
        }
    }
    var facts: String { [releaseInfo, runtime, imdbRating.map { "★ \($0)" }].compactMap { $0 }.joined(separator: " · ") }
}

struct StreamSource: Codable, Hashable, Identifiable {
    var name: String?
    var title: String?
    var infoHash: String?
    var fileIdx: Int?
    var url: String?
    var id: String { "\(infoHash ?? url ?? title ?? "unknown"):\(fileIdx ?? -1)" }
    var label: String { title ?? name ?? "Video" }
    var magnet: String? {
        guard let hash = infoHash, hash.range(of: "^[0-9a-fA-F]{40}$", options: .regularExpression) != nil else { return nil }
        var components = URLComponents()
        components.scheme = "magnet"
        components.queryItems = [URLQueryItem(name: "xt", value: "urn:btih:\(hash)"), URLQueryItem(name: "dn", value: label)]
        components.queryItems! += ["udp://tracker.opentrackr.org:1337/announce", "udp://tracker.torrent.eu.org:451/announce"].map { URLQueryItem(name: "tr", value: $0) }
        return components.string
    }
    var location: String? {
        if let url, let scheme = URL(string: url)?.scheme?.lowercased(), ["http", "https"].contains(scheme) { return url }
        return magnet ?? url
    }
}

struct Profile: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var name: String
    var symbol = "person.fill"
    var pinDigest: String?
}

struct HistoryEntry: Codable, Identifiable {
    var id: String
    var media: MediaTitle
    var episode: Episode?
    var source: StreamSource
    var position: Double
    var duration: Double
    var updated = Date()
    var completed: Bool { duration > 0 && position / duration >= 0.95 }
    static func key(_ media: MediaTitle, _ episode: Episode?) -> String { "\(media.type):\(media.id):\(episode?.id ?? "movie")" }
}

struct ByteRange: Equatable {
    var lower: Int64
    var upper: Int64
    var count: Int64 { upper - lower + 1 }
    static func parse(_ value: String?, size: Int64) throws -> ByteRange {
        guard size > 0 else { throw RangeError.invalid }
        guard let value else { return ByteRange(lower: 0, upper: size - 1) }
        guard value.hasPrefix("bytes="), !value.contains(",") else { throw RangeError.invalid }
        let parts = value.dropFirst(6).split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2 else { throw RangeError.invalid }
        if parts[0].isEmpty {
            guard let suffix = Int64(parts[1]), suffix > 0 else { throw RangeError.invalid }
            return ByteRange(lower: max(0, size - suffix), upper: size - 1)
        }
        guard let start = Int64(parts[0]), start >= 0, start < size else { throw RangeError.invalid }
        let end: Int64
        if parts[1].isEmpty { end = size - 1 }
        else { guard let parsed = Int64(parts[1]), parsed >= start else { throw RangeError.invalid }; end = min(parsed, size - 1) }
        return ByteRange(lower: start, upper: end)
    }
    enum RangeError: Error { case invalid }
}

struct TorrentFile: Identifiable, Hashable {
    var id: Int
    var name: String
    var size: Int64
    var isVideo: Bool { ["mkv", "mp4", "m4v", "avi", "mov", "ts", "webm"].contains((name as NSString).pathExtension.lowercased()) }
    func matches(_ episode: Episode) -> Bool {
        let pattern = "(?i)(?:^|[^a-z0-9])(?:s0*\(episode.season)[ ._-]*e0*\(episode.episode)|0*\(episode.season)x0*\(episode.episode))(?:[^0-9]|$)"
        return name.range(of: pattern, options: .regularExpression) != nil
    }
}
