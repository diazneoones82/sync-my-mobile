import Foundation

final class DeviceAPI {
    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL, timeout: TimeInterval = 120) {
        self.baseURL = baseURL
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.waitsForConnectivity = true
        self.session = URLSession(configuration: configuration)
    }

    func manifest(timeout: TimeInterval? = nil) async throws -> Manifest {
        var request = URLRequest(url: baseURL.appending(path: "manifest"))
        request.setValue("SyncMyMobile-Mac/0.1", forHTTPHeaderField: "User-Agent")
        if let timeout {
            request.timeoutInterval = timeout
        }
        let (data, response) = try await session.data(for: request)
        try Self.validate(response)
        return try JSONDecoder().decode(Manifest.self, from: data)
    }

    func download(_ file: RemoteFile, to target: URL) async throws {
        var components = URLComponents(url: baseURL.appending(path: "file"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "id", value: file.id)]
        guard let url = components.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.setValue("SyncMyMobile-Mac/0.1", forHTTPHeaderField: "User-Agent")
        let (temporaryURL, response) = try await session.download(for: request)
        try Self.validate(response)

        let manager = FileManager.default
        try manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        if manager.fileExists(atPath: target.path) {
            try manager.removeItem(at: target)
        }
        try manager.moveItem(at: temporaryURL, to: target)

        if file.modified > 0 {
            let date = Date(timeIntervalSince1970: TimeInterval(file.modified) / 1000)
            try? manager.setAttributes([.modificationDate: date], ofItemAtPath: target.path)
        }
    }

    private static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            return
        }
        guard (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
}
