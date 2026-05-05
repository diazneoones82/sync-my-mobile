import Foundation
import Network

final class LanSyncServer {
    private let listener: NWListener
    private let store: SelectionStore
    private let queue = DispatchQueue(label: "sync-my-mobile.http-server")
    private var running = false

    init(port: UInt16, store: SelectionStore) throws {
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            throw SyncFileError.notFound
        }
        self.listener = try NWListener(using: .tcp, on: endpointPort)
        self.store = store
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
    }

    func start() {
        guard !running else { return }
        running = true
        listener.start(queue: queue)
    }

    func stop() {
        guard running else { return }
        running = false
        listener.cancel()
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, _, error in
            guard let self else {
                connection.cancel()
                return
            }
            guard error == nil, let data, let request = String(data: data, encoding: .utf8) else {
                self.sendText("Bad Request", status: 400, reason: "Bad Request", connection: connection)
                return
            }
            self.route(request, connection: connection)
        }
    }

    private func route(_ request: String, connection: NWConnection) {
        let firstLine = request.components(separatedBy: "\r\n").first ?? ""
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else {
            sendText("Bad Request", status: 400, reason: "Bad Request", connection: connection)
            return
        }

        let path = String(parts[1])
        if path == "/manifest" {
            sendData(store.manifestJSON(), contentType: "application/json", connection: connection)
        } else if path.hasPrefix("/file?") {
            guard let id = queryParam(path, "id") else {
                sendText("Missing id", status: 400, reason: "Bad Request", connection: connection)
                return
            }
            sendFile(id: id, connection: connection)
        } else {
            sendText("Not Found", status: 404, reason: "Not Found", connection: connection)
        }
    }

    private func sendFile(id: String, connection: NWConnection) {
        do {
            let resolved = try store.resolveFileID(id)
            let didAccess = resolved.accessURL.startAccessingSecurityScopedResource()
            let attributes = try FileManager.default.attributesOfItem(atPath: resolved.url.path)
            let length = (attributes[.size] as? NSNumber)?.int64Value ?? -1
            let handle = try FileHandle(forReadingFrom: resolved.url)
            let header = httpHeader(
                status: 200,
                reason: "OK",
                contentType: "application/octet-stream",
                contentLength: length,
                filename: resolved.url.lastPathComponent,
            )
            connection.send(content: header, completion: .contentProcessed { [weak self] error in
                if error != nil {
                    try? handle.close()
                    if didAccess {
                        resolved.accessURL.stopAccessingSecurityScopedResource()
                    }
                    connection.cancel()
                    return
                }
                self?.sendNextChunk(handle: handle, accessURL: resolved.accessURL, didAccess: didAccess, connection: connection)
            })
        } catch {
            sendText("File not found", status: 404, reason: "Not Found", connection: connection)
        }
    }

    private func sendNextChunk(handle: FileHandle, accessURL: URL, didAccess: Bool, connection: NWConnection) {
        let chunk = handle.readData(ofLength: 64 * 1024)
        if chunk.isEmpty {
            try? handle.close()
            if didAccess {
                accessURL.stopAccessingSecurityScopedResource()
            }
            connection.cancel()
            return
        }

        connection.send(content: chunk, completion: .contentProcessed { [weak self] error in
            if error != nil {
                try? handle.close()
                if didAccess {
                    accessURL.stopAccessingSecurityScopedResource()
                }
                connection.cancel()
                return
            }
            self?.sendNextChunk(handle: handle, accessURL: accessURL, didAccess: didAccess, connection: connection)
        })
    }

    private func sendText(_ text: String, status: Int, reason: String, connection: NWConnection) {
        sendData(Data(text.utf8), status: status, reason: reason, contentType: "text/plain", connection: connection)
    }

    private func sendData(
        _ body: Data,
        status: Int = 200,
        reason: String = "OK",
        contentType: String,
        connection: NWConnection,
    ) {
        var payload = httpHeader(status: status, reason: reason, contentType: contentType, contentLength: Int64(body.count))
        payload.append(body)
        connection.send(content: payload, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func httpHeader(status: Int, reason: String, contentType: String, contentLength: Int64, filename: String? = nil) -> Data {
        var header = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: \(contentType)\r\n"
        if contentLength >= 0 {
            header += "Content-Length: \(contentLength)\r\n"
        }
        if let filename {
            header += "Content-Disposition: attachment; filename=\"\(Self.headerSafeFilename(filename))\"\r\n"
        }
        header += "Connection: close\r\n\r\n"
        return Data(header.utf8)
    }

    private static func headerSafeFilename(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "_")
            .replacingOccurrences(of: "\"", with: "_")
            .replacingOccurrences(of: "\r", with: "_")
            .replacingOccurrences(of: "\n", with: "_")
    }

    private func queryParam(_ path: String, _ name: String) -> String? {
        let query = path.split(separator: "?", maxSplits: 1).dropFirst().first.map(String.init) ?? ""
        for item in query.split(separator: "&") {
            let pair = item.split(separator: "=", maxSplits: 1).map(String.init)
            if pair.count == 2, pair[0] == name {
                return pair[1].removingPercentEncoding
            }
        }
        return nil
    }
}
