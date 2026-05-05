import AppKit
import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var devices: [Device] = []
    @Published var selectedDeviceID: Device.ID?
    @Published var files: [RemoteFile] = []
    @Published var destination: URL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
    @Published var status = "Scanning for mobile devices..."
    @Published var logs: [String] = []
    @Published var workerCount = 6
    @Published var isBusy = false

    private let discovery = DiscoveryService()

    var selectedDevice: Device? {
        devices.first { $0.id == selectedDeviceID }
    }

    var totalSize: Int64 {
        files.reduce(0) { $0 + $1.size }
    }

    func start() {
        discovery.start { [weak self] device in
            Task { @MainActor in
                self?.upsert(device)
            }
        }
    }

    func stop() {
        discovery.stop()
    }

    func scanNow() {
        status = "Scanning..."
        discovery.scanOnce { [weak self] device in
            Task { @MainActor in
                self?.upsert(device)
            }
        }
    }

    func addManualDevice(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }
        let parts = trimmed.split(separator: ":", maxSplits: 1).map(String.init)
        let host = parts[0]
        let port = parts.count > 1 ? (Int(parts[1]) ?? Int(defaultHTTPPort)) : Int(defaultHTTPPort)
        let device = Device(id: "\(host):\(port)", name: "Manual \(host)", host: host, port: port, lastSeen: Date())
        upsert(device)
        selectedDeviceID = device.id
        Task {
            await refreshManifest()
        }
    }

    func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = destination
        if panel.runModal() == .OK, let url = panel.url {
            destination = url
        }
    }

    func refreshManifest() async {
        guard let selectedDevice else {
            status = "Select a device first."
            return
        }
        isBusy = true
        status = "Loading manifest from \(selectedDevice.host)..."
        defer { isBusy = false }

        do {
            let manifest = try await DeviceAPI(baseURL: selectedDevice.baseURL).manifest()
            let clean = PathTools.uniqueByTarget(manifest.files)
            files = clean
            status = "\(clean.count) files ready, \(Self.formatBytes(totalSize))"
        } catch {
            status = "Manifest failed: \(error.localizedDescription)"
            appendLog(status)
        }
    }

    func downloadAll() async {
        guard let selectedDevice else {
            status = "Select a device first."
            return
        }
        guard !files.isEmpty else {
            status = "No files to download."
            return
        }

        isBusy = true
        status = "Downloading..."
        defer { isBusy = false }

        let result = await DownloadManager().download(
            files: files,
            from: selectedDevice,
            destinationRoot: destination,
            workers: workerCount,
            progress: { [weak self] message in
                await MainActor.run {
                    self?.status = message
                }
            },
            log: { [weak self] message in
                await MainActor.run {
                    self?.appendLog(message)
                }
            }
        )
        status = "Done. Downloaded \(result.downloaded), skipped \(result.skipped), failed \(result.failed)."
    }

    func clearLogs() {
        logs.removeAll()
    }

    private func upsert(_ device: Device) {
        if let index = devices.firstIndex(where: { $0.id == device.id }) {
            devices[index] = device
        } else {
            devices.append(device)
            devices.sort { $0.displayName < $1.displayName }
        }
        if selectedDeviceID == nil {
            selectedDeviceID = device.id
        }
        status = "Found \(device.name) at \(device.host)"
    }

    private func appendLog(_ message: String) {
        logs.append("[\(Self.timeFormatter.string(from: Date()))] \(message)")
    }

    static func formatBytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
