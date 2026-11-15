import Foundation
import Combine
import CryptoKit

@MainActor final class LibraryStore: ObservableObject {
    @Published private(set) var profiles: [Profile] = []
    @Published var activeID: String?
    @Published private(set) var saved: [MediaTitle] = []
    @Published private(set) var history: [HistoryEntry] = []
    @Published var discover = DiscoverSelection() { didSet { if activeID != nil { write(discover, key: profileKey + ".discover") } } }
    @Published var sourceProvider: String { didSet { defaults.set(sourceProvider, forKey: "sourceProvider") } }
    @Published var cacheGB: Int { didSet { defaults.set(cacheGB, forKey: "cacheGB") } }
    private let defaults = UserDefaults.standard
    private var profileKey: String { "profile.\(activeID ?? "none")" }
    init() {
        sourceProvider = UserDefaults.standard.string(forKey: "sourceProvider") ?? "https://torrentio.strem.fun"
        cacheGB = max(1, UserDefaults.standard.integer(forKey: "cacheGB"))
        profiles = read("profiles", fallback: [Profile(name: "Me")])
        write(profiles, key: "profiles")
    }
    private func read<T: Decodable>(_ key: String, fallback: T) -> T {
        guard let data = defaults.data(forKey: key), let value = try? JSONDecoder().decode(T.self, from: data) else { return fallback }
        return value
    }
    private func write<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }
    func select(_ profile: Profile, pin: String = "") -> Bool {
        if let digest = profile.pinDigest, digest != hash(pin, salt: profile.id) { return false }
        activeID = profile.id
        saved = read(profileKey + ".saved", fallback: [])
        history = read(profileKey + ".history", fallback: [])
        discover = read(profileKey + ".discover", fallback: DiscoverSelection())
        return true
    }
    func addProfile(name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, profiles.count < 8 else { return }
        profiles.append(Profile(name: clean))
        write(profiles, key: "profiles")
    }
    func setPIN(_ value: String) {
        guard let i = profiles.firstIndex(where: { $0.id == activeID }) else { return }
        guard value.isEmpty || (value.count == 4 && value.allSatisfy(\.isNumber)) else { return }
        profiles[i].pinDigest = value.isEmpty ? nil : hash(value, salt: profiles[i].id)
        write(profiles, key: "profiles")
    }
    private func hash(_ value: String, salt: String) -> String {
        SHA256.hash(data: Data((salt + ":" + value).utf8)).map { String(format: "%02x", $0) }.joined()
    }
    func hasSaved(_ title: MediaTitle) -> Bool { saved.contains { $0.id == title.id && $0.type == title.type } }
    func toggle(_ title: MediaTitle) {
        if hasSaved(title) { saved.removeAll { $0.id == title.id && $0.type == title.type } }
        else { saved.insert(title, at: 0) }
        write(saved, key: profileKey + ".saved")
    }
    func entry(_ title: MediaTitle, episode: Episode?) -> HistoryEntry? {
        history.first { $0.id == HistoryEntry.key(title, episode) }
    }
    func record(_ title: MediaTitle, episode: Episode?, source: StreamSource, position: Double, duration: Double) {
        guard activeID != nil, position.isFinite, duration.isFinite, position >= 0, duration > 0 else { return }
        let id = HistoryEntry.key(title, episode)
        history.removeAll { $0.id == id }
        history.insert(HistoryEntry(id: id, media: title, episode: episode, source: source, position: position, duration: duration), at: 0)
        history = Array(history.prefix(100))
        write(history, key: profileKey + ".history")
    }
    func clearHistory() { history = []; write(history, key: profileKey + ".history") }
    func signOut() { activeID = nil; saved = []; history = [] }
}
