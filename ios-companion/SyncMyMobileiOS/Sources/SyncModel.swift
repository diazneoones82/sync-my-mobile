import Foundation
import SwiftUI
import UIKit

let appID = "sync-my-mobile"
let discoveryPort: UInt16 = 47854
let httpPort: UInt16 = 47855
let localFilesReadmeName = "README - Add Files Here.txt"

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

    func prepareLocalFilesFolder() {
        do {
            _ = try SelectionStore.localFilesFolder()
            status = "Local folder ready in Files > On My iPhone > Sync My Mobile"
        } catch {
            status = "Could not prepare local iPhone folder: \(error.localizedDescription)"
            showStatusAlert = true
        }
    }

    func addAppDocumentsFolder() {
        do {
            try store.addLocalFilesFolder()
            refreshSummary()
            status = "Using Files > On My iPhone > Sync My Mobile. Add files there, then tap Start LAN Sync or Refresh List."
            showStatusAlert = true
        } catch {
            status = "Could not use local iPhone folder: \(error.localizedDescription)"
            showStatusAlert = true
        }
    }

    func addCloudFiles(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            let imported = store.addFiles(urls)
            refreshSummary()
            if imported == urls.count {
                status = imported == 1 ? "1 cloud file selected." : "\(imported) cloud files selected."
            } else {
                status = "\(imported) of \(urls.count) cloud file(s) imported. Open cloud files once in Files if they are not downloaded locally, then select again."
                showStatusAlert = true
            }
        case .failure(let error):
            status = "File selection failed: \(error.localizedDescription)"
            showStatusAlert = true
        }
    }

    func addPhoneItems(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            let imported = store.addPhoneItems(urls)
            refreshSummary()
            if imported == urls.count {
                status = imported == 1 ? "1 phone item selected." : "\(imported) phone items selected."
            } else {
                status = "\(imported) of \(urls.count) phone item(s) imported. iOS only allows files or folders chosen through Files."
                showStatusAlert = true
            }
        case .failure(let error):
            status = "Phone storage selection failed: \(error.localizedDescription)"
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
        let rootURL: URL
        let provider: String
        let displayName: String
        let isFolder: Bool
    }

    private let lock = NSLock()
    private var sources: [Source] = []
    private var autoIntervalMinutes = 1

    func addFiles(_ urls: [URL]) -> Int {
        add(urls: urls, isFolder: false)
    }

    func addFolders(_ urls: [URL]) -> Int {
        add(urls: urls, isFolder: true)
    }

    func addPhoneItems(_ urls: [URL]) -> Int {
        let folders = urls.filter { Self.isDirectory($0) }
        let files = urls.filter { !Self.isDirectory($0) }
        return add(urls: folders, isFolder: true) + add(urls: files, isFolder: false)
    }

    func addLocalFilesFolder() throws {
        let folder = try Self.localFilesFolder()
        lock.lock()
        sources.removeAll {
            $0.rootURL.standardizedFileURL == folder.standardizedFileURL
        }
        sources.append(Source(rootURL: folder, provider: "On My iPhone", displayName: "Sync My Mobile", isFolder: true))
        lock.unlock()
    }

    func clear() {
        lock.lock()
        let snapshot = sources
        sources.removeAll()
        lock.unlock()
        for source in snapshot {
            let parent = source.isFolder ? source.rootURL : source.rootURL.deletingLastPathComponent()
            try? FileManager.default.removeItem(at: parent)
        }
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
        if id.hasPrefix("local:") {
            let encoded = String(id.dropFirst("local:".count))
            guard let data = Data(base64Encoded: encoded), let path = String(data: data, encoding: .utf8) else { throw SyncFileError.notFound }
            let url = URL(fileURLWithPath: path)
            return ResolvedFile(url: url, accessURL: url)
        }

        throw SyncFileError.notFound
    }

    private func add(urls: [URL], isFolder: Bool) -> Int {
        let newSources = urls.compactMap { url -> Source? in
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            let provider = Self.providerName(for: url)
            let name = (try? url.resourceValues(forKeys: [.nameKey]))?.name ?? url.lastPathComponent
            do {
                let imported = try Self.importSource(url, name: name, isFolder: isFolder)
                return Source(rootURL: imported, provider: provider, displayName: name.isEmpty ? "Files" : name, isFolder: isFolder)
            } catch {
                return nil
            }
        }
        lock.lock()
        sources.append(contentsOf: newSources)
        lock.unlock()
        return newSources.count
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
        guard source.rootURL.isFileURL else { return nil }
        let values = try? source.rootURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .nameKey])
        let name = values?.name ?? source.rootURL.lastPathComponent
        return ManifestFile(
            id: Self.fileID(for: source.rootURL),
            relativePath: "\(source.provider)/\(name)",
            size: Int64(values?.fileSize ?? 0),
            modified: Int64((values?.contentModificationDate ?? .distantPast).timeIntervalSince1970 * 1000),
        )
    }

    private func folderManifestFiles(_ source: Source) -> [ManifestFile] {
        let root = source.rootURL

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
            if child.lastPathComponent == localFilesReadmeName {
                continue
            }
            let relative = child.path.replacingOccurrences(of: root.path + "/", with: "")
            files.append(
                ManifestFile(
                    id: Self.fileID(for: child),
                    relativePath: "\(source.provider)/\(source.displayName)/\(relative)",
                    size: Int64(values?.fileSize ?? 0),
                    modified: Int64((values?.contentModificationDate ?? .distantPast).timeIntervalSince1970 * 1000),
                )
            )
        }
        return files
    }

    private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }

    private static func fileID(for url: URL) -> String {
        "local:\(Data(url.path.utf8).base64EncodedString())"
    }

    private static func importSource(_ url: URL, name: String, isFolder: Bool) throws -> URL {
        let base = try importBaseDirectory()
        let sourceDirectory = base.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)

        let displayName = name.isEmpty ? url.lastPathComponent : name
        let destination = sourceDirectory.appendingPathComponent(displayName, isDirectory: isFolder)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try coordinatedCopy(from: url, to: destination)
        return destination
    }

    private static func coordinatedCopy(from source: URL, to destination: URL) throws {
        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: source, options: [], error: &coordinationError) { coordinatedURL in
            do {
                try FileManager.default.copyItem(at: coordinatedURL, to: destination)
            } catch {
                copyError = error
            }
        }
        if let coordinationError {
            throw coordinationError
        }
        if let copyError {
            throw copyError
        }
    }

    private static func importBaseDirectory() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = appSupport.appendingPathComponent("SelectedSources", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func localFilesFolder() throws -> URL {
        let documents = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let readme = documents.appendingPathComponent(localFilesReadmeName)
        if !FileManager.default.fileExists(atPath: readme.path) {
            let text = """
            Add files or folders next to this README from the iPhone Files app.

            In Sync My Mobile, choose Source > On My iPhone Folder, then Start LAN Sync.
            The desktop app will list and download files from this app folder.
            """
            try text.write(to: readme, atomically: true, encoding: .utf8)
        }
        return documents
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
