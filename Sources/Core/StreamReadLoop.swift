import Foundation

enum StreamReadResult { case pending, storageLimited, bytes(Data) }
enum StreamReadError: LocalizedError {
    case timedOut
    var errorDescription: String? { "Torrent data timed out. The required pieces did not arrive; try another source with active peers." }
}

enum StreamReadLoop {
    static func read(timeout: TimeInterval = 45, interval: UInt64 = 100_000_000,
                     poll: () async throws -> StreamReadResult) async throws -> Data {
        var deadline = Date().addingTimeInterval(timeout)
        while true {
            try Task.checkCancellation()
            let result = try await poll()
            try Task.checkCancellation()
            switch result {
            case .bytes(let data): if !data.isEmpty { return data }
            case .storageLimited: deadline = Date().addingTimeInterval(timeout)
            case .pending: break
            }
            if Date() >= deadline { throw StreamReadError.timedOut }
            try await Task.sleep(nanoseconds: interval)
        }
    }
}

struct TorrentProgress {
    var peers = 0
    var speed: Int64 = 0
    var downloaded: Int64 = 0
    var delivered: Int64 = 0
    var storageLimited = false
    var cacheLimit: Int64 = 0
    var summary: String {
        "\(peers) peers · \(ByteCountFormatter.string(fromByteCount: speed, countStyle: .file))/s · \(ByteCountFormatter.string(fromByteCount: downloaded, countStyle: .file)) downloaded"
    }
}
