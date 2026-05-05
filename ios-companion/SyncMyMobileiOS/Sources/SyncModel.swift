import Foundation
import SwiftUI
import UIKit

let appID = "sync-my-mobile"
let discoveryPort: UInt16 = 47854
let httpPort: UInt16 = 47855

@MainActor
final class SyncModel: ObservableObject {
    @Published var selectionSummary: [String] = []
    @Published var status = "Waiting to start LAN sync."
    @Published var autoIntervalMinutes = 1
    @Published var showAbout = false
    @Published var showCloudHelp = false
    @Published var showStatusAlert = false

    private let store = SelectionStore()
    private var server: LanSyncServer?
    private var beacon: UdpBeacon?

    func addCloudFiles(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            store.addFiles(urls)
            refreshSummary()
            let count = urls.count
            status = count == 1 ? "1 cloud file selected." : "\(count) cloud files selected."
        case .failure(let error):
            status = "File selection failed: \(error.localizedDescription)"
            showStatusAlert = true
        }
    }

    func addPhoneFolders(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            store.addFolders(urls)
            refreshSummary()
            let count = urls.count
            status = count == 1 ? "1 phone folder selected." : "\(count) phone folders selected."
        case .failure(let error):
            status = "Folder selection failed: \(error.localizedDescription)"
            showStatusAlert = true
        }
    }

    func clearSelections() {
        store.clear()
        refreshSummary()
        status = "Selections cleared."
    }

    func startSync() {
        do {
            store.setAutoInterval(autoIntervalMinutes)
            if server == nil {
                server = try LanSyncServer(port: httpPort, store: store)
            }
            server?.start()
            if beacon == nil {
                beacon = UdpBeacon(httpPort: httpPort)
            }
            beacon?.start()
            status = "LAN sync started on port \(httpPort)"
            showStatusAlert = true
        } catch {
            status = "LAN sync failed: \(error.localizedDescription)"
            showStatusAlert = true
        }
    }

    func stopSync(message: String) {
        server?.stop()
        server = nil
        beacon?.stop()
        beacon = nil
        status = message
        showStatusAlert = true
    }

    private func refreshSummary() {
        selectionSummary = store.summary()
    }
}

final class SelectionStore {
    private struct Source {
        let bookmark: Data
        let provider: String
        let displayName: String
        let isFolder: Bool
    }

    private let lock = NSLock()
    private var sources: [Source] = []
    private var autoIntervalMinutes = 1

    func addFiles(_ urls: [URL]) {
        add(urls: urls, isFolder: false)
    }

    func addFolders(_ urls: [URL]) {
        add(urls: urls, isFolder: true)
    }

    func clear() {
        lock.lock()
        sources.removeAll()
        lock.unlock()
    }

    func setAutoInterval(_ value: Int) {
        lock.lock()
        autoIntervalMinutes = max(1, min(value, 240))
        lock.unlock()
    }

    func summary() -> [String] {
        lock.lock()
        let snapshot = sources
        lock.unlock()

        var counts: [String: Int] = [:]
        var folders: [String] = []
        for source in snapshot {
            if source.isFolder {
                folders.append("\(source.provider): \(source.displayName)")
            } else {
                counts[source.provider, default: 0] += 1
            }
        }
        let fileLines = counts.keys.sorted().map { provider in
            "\(provider): \(counts[provider] ?? 0) file(s) selected"
        }
        return (folders.sorted() + fileLines)
    }

    func manifestJSON() -> Data {
        let files = manifestFiles()
        lock.lock()
        let interval = autoIntervalMinutes
        lock.unlock()
        let items = files.map { file in
            [
                "id": file.id,
                "relativePath": file.relativePath,
                "size": file.size,
                "modified": file.modified,
            ] as [String: Any]
        }
        let payload: [String: Any] = [
            "app": appID,
            "deviceName": UIDevice.current.name,
            "autoIntervalMinutes": interval,
            "files": items,
        ]
        return (try? JSONSerialization.data(withJSONObject: payload, options: [])) ?? Data(#"{"app":"sync-my-mobile","deviceName":"iPhone","files":[]}"#.utf8)
    }

    func resolveFileID(_ id: String) throws -> ResolvedFile {
        if id.hasPrefix("file:") {
            let encoded = String(id.dropFirst("file:".count))
            guard let data = Data(base64Encoded: encoded) else { throw SyncFileError.notFound }
            var stale = false
            let url = try URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
            return ResolvedFile(url: url, accessURL: url)
        }

        if id.hasPrefix("folder:") {
            let parts = id.split(separator: ":", maxSplits: 2).map(String.init)
            guard parts.count == 3,
                  let data = Data(base64Encoded: parts[1]),
                  let relative = parts[2].removingPercentEncoding else { throw SyncFileError.notFound }
            var stale = false
            let root = try URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
            return ResolvedFile(url: root.appendingPathComponent(relative), accessURL: root)
        }

        throw SyncFileError.notFound
    }

    private func add(urls: [URL], isFolder: Bool) {
        let newSources = urls.compactMap { url -> Source? in
            let provider = Self.providerName(for: url)
            let name = (try? url.resourceValues(forKeys: [.nameKey]))?.name ?? url.lastPathComponent
            do {
                let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
                return Source(bookmark: bookmark, provider: provider, displayName: name.isEmpty ? "Files" : name, isFolder: isFolder)
            } catch {
                return nil
            }
        }
        lock.lock()
        sources.append(contentsOf: newSources)
        lock.unlock()
    }

    private func manifestFiles() -> [ManifestFile] {
        lock.lock()
        let snapshot = sources
        lock.unlock()

        var files: [ManifestFile] = []
        for source in snapshot {
            if source.isFolder {
                files.append(contentsOf: folderManifestFiles(source))
            } else if let file = singleManifestFile(source) {
                files.append(file)
            }
        }
        var seen = Set<String>()
        return files.filter { seen.insert($0.relativePath.lowercased()).inserted }
    }

    private func singleManifestFile(_ source: Source) -> ManifestFile? {
        guard let resolved = try? resolveFileID("file:\(source.bookmark.base64EncodedString())") else { return nil }
        let didAccess = resolved.accessURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                resolved.accessURL.stopAccessingSecurityScopedResource()
            }
        }
        guard resolved.url.isFileURL else { return nil }
        let values = try? resolved.url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .nameKey])
        let name = values?.name ?? resolved.url.lastPathComponent
        return ManifestFile(
            id: "file:\(source.bookmark.base64EncodedString())",
            relativePath: "\(source.provider)/\(name)",
            size: Int64(values?.fileSize ?? 0),
            modified: Int64((values?.contentModificationDate ?? .distantPast).timeIntervalSince1970 * 1000),
        )
    }

    private func folderManifestFiles(_ source: Source) -> [ManifestFile] {
        guard let root = try? resolveBookmark(source.bookmark) else { return [] }
        let didAccess = root.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                root.stopAccessingSecurityScopedResource()
            }
        }

        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .fileSizeKey, .contentModificationDateKey, .nameKey]
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else {
            return []
        }

        var files: [ManifestFile] = []
        for case let child as URL in enumerator {
            let values = try? child.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true {
                continue
            }
            guard values?.isRegularFile == true else {
                continue
            }
            let relative = child.path.replacingOccurrences(of: root.path + "/", with: "")
            let encoded = relative.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? relative
            files.append(
                ManifestFile(
                    id: "folder:\(source.bookmark.base64EncodedString()):\(encoded)",
                    relativePath: "\(source.provider)/\(source.displayName)/\(relative)",
                    size: Int64(values?.fileSize ?? 0),
                    modified: Int64((values?.contentModificationDate ?? .distantPast).timeIntervalSince1970 * 1000),
                )
            )
        }
        return files
    }

    private func resolveBookmark(_ data: Data) throws -> URL {
        var stale = false
        return try URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
    }

    private static func providerName(for url: URL) -> String {
        let text = url.absoluteString.lowercased()
        if text.contains("onedrive") || text.contains("skydrive") || text.contains("microsoft") || text.contains("sharepoint") {
            return "ONEDRIVE"
        }
        if text.contains("box") {
            return "BOXDRIVE"
        }
        if text.contains("google") || text.contains("drive") {
            return "GDRIVE"
        }
        if text.contains("icloud") || text.contains("mobile documents") {
            return "iCloud Drive"
        }
        return "iPhone Files"
    }
}

struct ManifestFile {
    let id: String
    let relativePath: String
    let size: Int64
    let modified: Int64
}

struct ResolvedFile {
    let url: URL
    let accessURL: URL
}

enum SyncFileError: Error {
    case notFound
}
