import Foundation
import Network

private final class StartGate: @unchecked Sendable {
    private let lock = NSLock()
    private var waiting = true
    func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard waiting else { return false }
        waiting = false
        return true
    }
}

/// Loopback only; an unguessable per-session path prevents accidental access.
final class RangeServer: @unchecked Sendable {
    private let engine: TorrentEngine
    private let file: TorrentFile
    private let queue = DispatchQueue(label: "watchly.http")
    private var listener: NWListener?
    private var clients: [UUID: NWConnection] = [:]
    private var transfers: [ObjectIdentifier: Task<Void, Never>] = [:]
    private var pendingHeaders = Set<ObjectIdentifier>()
    private let token = UUID().uuidString
    var onError: (@Sendable (String) -> Void)?
    init(engine: TorrentEngine, file: TorrentFile) { self.engine = engine; self.file = file }

    func start() async throws -> URL {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: params)
        self.listener = listener
        return try await withCheckedThrowingContinuation { continuation in
            let gate = StartGate()
            listener.stateUpdateHandler = { [weak self, weak listener] state in
                switch state {
                case .ready:
                    guard gate.claim() else { return }
                    if let port = listener?.port, let self {
                        continuation.resume(returning: URL(string: "http://127.0.0.1:\(port.rawValue)/\(self.token)/video")!)
                    } else { continuation.resume(throwing: WatchlyError.message("Could not start video streaming.")) }
                case .failed(let error): if gate.claim() { continuation.resume(throwing: error) }
                case .cancelled: if gate.claim() { continuation.resume(throwing: CancellationError()) }
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
            listener.start(queue: queue)
        }
    }
    func stop() {
        queue.async {
            self.listener?.cancel(); self.listener = nil
            for task in self.transfers.values { task.cancel() }
            self.transfers.removeAll()
            for client in self.clients.values { client.cancel() }
            self.clients.removeAll()
            self.pendingHeaders.removeAll()
        }
    }
    private func accept(_ client: NWConnection) {
        guard clients.count < 8 else { client.cancel(); return }
        let id = UUID()
        clients[id] = client
        pendingHeaders.insert(ObjectIdentifier(client))
        client.stateUpdateHandler = { [weak self, weak client] state in
            guard let client else { return }
            if case .cancelled = state { self?.transfers.removeValue(forKey: ObjectIdentifier(client))?.cancel(); self?.clients[id] = nil; self?.pendingHeaders.remove(ObjectIdentifier(client)) }
            if case .failed = state { client.cancel(); self?.transfers.removeValue(forKey: ObjectIdentifier(client))?.cancel(); self?.clients[id] = nil; self?.pendingHeaders.remove(ObjectIdentifier(client)) }
        }
        client.start(queue: queue)
        receiveHeader(client, accumulated: Data())
        queue.asyncAfter(deadline: .now() + 10) { [weak self, weak client] in
            if let client, self?.pendingHeaders.contains(ObjectIdentifier(client)) == true { client.cancel() }
        }
    }
    private func receiveHeader(_ client: NWConnection, accumulated: Data) {
        client.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, complete, error in
            guard let self, error == nil else { client.cancel(); return }
            var buffer = accumulated
            buffer.append(data ?? Data())
            guard buffer.count <= 16384 else { self.reply(client, status: "431 Request Header Fields Too Large"); return }
            if let raw = String(data: buffer, encoding: .utf8), raw.contains("\r\n\r\n") { self.handle(client, header: raw) }
            else if complete { client.cancel() }
            else { self.receiveHeader(client, accumulated: buffer) }
        }
    }
    private func reply(_ client: NWConnection, status: String, extra: String = "") {
        let response = "HTTP/1.1 \(status)\r\n\(extra)Content-Length: 0\r\nConnection: close\r\n\r\n"
        client.send(content: Data(response.utf8), completion: .contentProcessed { _ in client.cancel() })
    }
    private func handle(_ client: NWConnection, header: String) {
        pendingHeaders.remove(ObjectIdentifier(client))
        let lines = header.components(separatedBy: "\r\n")
        let request = (lines.first ?? "").split(separator: " ")
        guard request.count == 3, request[1] == "/\(token)/video" else { reply(client, status: "404 Not Found"); return }
        let method = String(request[0])
        guard method == "GET" || method == "HEAD" else { reply(client, status: "405 Method Not Allowed", extra: "Allow: GET, HEAD\r\n"); return }
        let rangeHeaders = lines.dropFirst().filter { $0.lowercased().hasPrefix("range:") }
        guard rangeHeaders.count <= 1 else { reply(client, status: "400 Bad Request"); return }
        let requested = rangeHeaders.first.map { String($0.dropFirst(6)).trimmingCharacters(in: .whitespaces) }
        guard let range = try? ByteRange.parse(requested, size: file.size) else {
            reply(client, status: "416 Range Not Satisfiable", extra: "Content-Range: bytes */\(file.size)\r\n"); return
        }
        let status = requested == nil ? "200 OK" : "206 Partial Content"
        let contentRange = requested == nil ? "" : "Content-Range: bytes \(range.lower)-\(range.upper)/\(file.size)\r\n"
        let response = "HTTP/1.1 \(status)\r\nAccept-Ranges: bytes\r\nContent-Type: application/octet-stream\r\nContent-Length: \(range.count)\r\n\(contentRange)Connection: close\r\n\r\n"
        client.send(content: Data(response.utf8), completion: .contentProcessed { [weak self] error in
            guard error == nil, method != "HEAD" else { client.cancel(); return }
            self?.stream(client, range: range)
        })
    }
    private func stream(_ client: NWConnection, range: ByteRange) {
        let key = ObjectIdentifier(client)
        let requestID = UUID().uuidString
        transfers[key] = Task { [weak self] in
            guard let self else { return }
            do {
                var offset = range.lower
                while offset <= range.upper {
                    try Task.checkCancellation()
                    let data = try await engine.read(offset: offset, count: Int(min(256 * 1024, range.upper - offset + 1)), requestID: requestID)
                    try Task.checkCancellation()
                    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                        client.send(content: data, completion: .contentProcessed { error in
                            if let error { continuation.resume(throwing: error) }
                            else { continuation.resume() }
                        })
                    }
                    offset += Int64(data.count)
                }
            } catch is CancellationError { }
            catch {
                // Individual probes may be abandoned by VLC. Report transport evidence,
                // not a fatal decoder error for the whole playback session.
                if !Task.isCancelled, case .ready = client.state { onError?(error.localizedDescription) }
            }
            await engine.finishRequest(requestID)
            client.cancel()
            queue.async { [weak self] in self?.transfers[key] = nil }
        }
        // VLC closes abandoned range connections when it probes/seeks elsewhere.
        // Observe that close while waiting for torrent pieces, not only during send.
        client.receive(minimumIncompleteLength: 1, maximumLength: 1) { [weak self] _, _, complete, error in
            if complete || error != nil {
                self?.transfers.removeValue(forKey: key)?.cancel()
                client.cancel()
            }
        }
    }
}
