import Foundation

final class TorrentEngine: @unchecked Sendable {
    private let bridge: WLTorrentBridge
    private let queue = DispatchQueue(label: "watchly.torrent", qos: .userInitiated)
    private let directory: URL
    init(cacheGB: Int) throws {
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("WatchlyStreams", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        directory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        bridge = WLTorrentBridge(directory: directory.path, cacheBytes: Int64(cacheGB) * 1024 * 1024 * 1024)
    }
    static func cleanAbandonedSessions() {
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("WatchlyStreams", isDirectory: true)
        // Only call once on cold launch, before constructing a session.
        try? FileManager.default.removeItem(at: root)
    }
    private func work<T>(_ operation: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { continuation.resume(with: Result { try operation() }) }
        }
    }
    func open(_ location: String) async throws {
        let source: String
        if location.lowercased().hasPrefix("magnet:") { source = location }
        else {
            guard let url = URL(string: location), ["https", "http"].contains(url.scheme?.lowercased() ?? "") else {
                throw WatchlyError.message("Use a magnet link or an HTTP(S) torrent URL.")
            }
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), data.count <= 16 * 1024 * 1024 else {
                throw WatchlyError.message("Could not download the torrent metadata.")
            }
            let file = directory.appendingPathComponent("source.torrent")
            try data.write(to: file, options: .atomic)
            source = file.path
        }
        try await work { try self.bridge.open(source) }
    }
    func files() async throws -> [TorrentFile]? {
        try await work {
            let snapshot = try self.bridge.snapshot()
            guard (snapshot["hasMetadata"] as? NSNumber)?.boolValue == true else { return nil }
            let files = snapshot["files"] as? [[String: Any]] ?? []
            return files.compactMap { row in
                guard let index = row["index"] as? NSNumber, let name = row["name"] as? String, let size = row["size"] as? NSNumber else { return nil }
                return TorrentFile(id: index.intValue, name: name, size: size.int64Value)
            }
        }
    }
    func select(_ file: TorrentFile) async throws { try await work { try self.bridge.selectFile(file.id) } }
    func read(offset: Int64, count: Int) async throws -> Data {
        try await work { try self.bridge.read(offset: offset, count: count) }
    }
    func cancel() { bridge.cancel() }
    func stop() async {
        bridge.cancel()
        _ = try? await work { self.bridge.stop(); try? FileManager.default.removeItem(at: self.directory) }
    }
}
