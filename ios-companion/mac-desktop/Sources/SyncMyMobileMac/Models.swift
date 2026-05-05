import Foundation

let appID = "sync-my-mobile"
let discoveryPort: UInt16 = 47854
let defaultHTTPPort: UInt16 = 47855

struct Device: Identifiable, Hashable {
    let id: String
    let name: String
    let host: String
    let port: Int
    let lastSeen: Date

    var baseURL: URL {
        URL(string: "http://\(host):\(port)")!
    }

    var displayName: String {
        "\(name) (\(host):\(port))"
    }
}

struct Manifest: Decodable {
    let app: String?
    let deviceName: String
    let autoIntervalMinutes: Int?
    let files: [RemoteFile]
}

struct RemoteFile: Identifiable, Decodable, Hashable {
    let id: String
    let relativePath: String
    let size: Int64
    let modified: Int64
}

struct DownloadResult {
    var downloaded = 0
    var skipped = 0
    var failed = 0
}
