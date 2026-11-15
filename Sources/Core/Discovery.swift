import Foundation

enum DiscoverSort: String, Codable, CaseIterable {
    case catalogue = "Catalogue order", title = "Title A–Z", newest = "Newest first", rating = "Highest rated"
}

struct DiscoverSelection: Codable, Equatable {
    var type = "movie"
    var genre = "All"
    var sort: DiscoverSort = .catalogue
    static let genres = ["All", "Action", "Adventure", "Animation", "Comedy", "Crime", "Documentary", "Drama", "Family", "Fantasy", "Horror", "Mystery", "Romance", "Sci-Fi", "Thriller"]

    func ordered(_ items: [MediaTitle]) -> [MediaTitle] {
        // Preserve provider order for ties; unknown metadata always sorts last.
        items.enumerated().sorted { lhs, rhs in
            switch sort {
            case .catalogue: return lhs.offset < rhs.offset
            case .title:
                let result = lhs.element.name.localizedStandardCompare(rhs.element.name)
                return result == .orderedSame ? lhs.offset < rhs.offset : result == .orderedAscending
            case .newest:
                let a = Int((lhs.element.releaseInfo ?? "").prefix(4)) ?? -1
                let b = Int((rhs.element.releaseInfo ?? "").prefix(4)) ?? -1
                return a == b ? lhs.offset < rhs.offset : a > b
            case .rating:
                let a = Double(lhs.element.imdbRating ?? "") ?? -1
                let b = Double(rhs.element.imdbRating ?? "") ?? -1
                return a == b ? lhs.offset < rhs.offset : a > b
            }
        }.map(\.element)
    }
}

struct SkipSegment: Decodable {
    var start_sec: Double?
    var end_sec: Double?
    var start_ms: Double?
    var end_ms: Double?
    var start: Double { start_sec ?? start_ms.map { $0 / 1000 } ?? .nan }
    var end: Double { end_sec ?? end_ms.map { $0 / 1000 } ?? .nan }
    func isAvailable(at position: Double, duration: Double) -> Bool {
        start.isFinite && end.isFinite && duration.isFinite && start >= 0 && end > start &&
        end <= duration && position >= start && position < end
    }
}

struct SkipSegments: Decodable {
    var intro: SkipSegment?
    var outro: SkipSegment?
    var post_credits: SkipSegment?
    var no_intro: Bool?
    var no_outro: Bool?
    func intro(at position: Double, duration: Double) -> SkipSegment? {
        guard no_intro != true, let intro, intro.isAvailable(at: position, duration: duration) else { return nil }
        return intro
    }
    func outro(at position: Double, duration: Double) -> SkipSegment? {
        guard no_outro != true, let outro, outro.isAvailable(at: position, duration: duration) else { return nil }
        guard position < outroDestination(outro) else { return nil }
        return outro
    }
    func outroDestination(_ outro: SkipSegment) -> Double {
        // Preserve a reported post-credit scene when it lies inside the credits window.
        if let scene = post_credits, scene.start.isFinite, scene.start > outro.start, scene.start < outro.end {
            return scene.start
        }
        return outro.end
    }
}
