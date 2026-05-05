import AppKit
import SwiftUI

@main
struct SyncMyMobileMacApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(state)
                .frame(minWidth: 980, minHeight: 680)
                .onAppear { state.start() }
                .onDisappear { state.stop() }
        }
        .windowStyle(.titleBar)
    }
}

struct ContentView: View {
    @EnvironmentObject private var state: AppState
    @State private var manualAddress = ""
    @State private var showAbout = false

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            mainPanel
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Devices")
                .font(.title2.bold())

            List(selection: $state.selectedDeviceID) {
                ForEach(state.devices) { device in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(device.name)
                            .font(.headline)
                        Text("\(device.host):\(device.port)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(device.id)
                }
            }

            HStack {
                TextField("iPhone IP or IP:port", text: $manualAddress)
                    .textFieldStyle(.roundedBorder)
                Button("Add") {
                    state.addManualDevice(manualAddress)
                    manualAddress = ""
                }
            }

            Button("Scan Now") {
                state.scanNow()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .navigationSplitViewColumnWidth(min: 260, ideal: 300)
    }

    private var mainPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            controls
            fileTable
            logPanel
            statusBar
        }
        .padding(18)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            BrandLogo()
                .frame(width: 58, height: 58)

            VStack(alignment: .leading, spacing: 3) {
                Text("Sync My Mobile")
                    .font(.largeTitle.bold())
                Text("Neo Apps")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.cyan)
                Text("Discover Android or iPhone companion apps, list selected files, and download them over LAN.")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("About") {
                showAbout = true
            }
        }
        .alert("About Sync My Mobile", isPresented: $showAbout) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Sync My Mobile\nNeo Apps\n\nAuthor: Bartholomew Diaz Michael\n\nDownloads selected Android or iPhone files to this Mac over the same local network.")
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button("Refresh List") {
                    Task { await state.refreshManifest() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(state.isBusy || state.selectedDevice == nil)

                Button("Download All") {
                    Task { await state.downloadAll() }
                }
                .disabled(state.isBusy || state.files.isEmpty)

                Button("Choose Folder") {
                    state.chooseDestination()
                }

                Stepper("Workers: \(state.workerCount)", value: $state.workerCount, in: 1...16)
                    .frame(width: 160)

                if state.isBusy {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Text("Destination: \(state.destination.path)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var fileTable: some View {
        VStack(spacing: 0) {
            HStack {
                Text("File")
                    .font(.caption.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Size")
                    .font(.caption.bold())
                    .frame(width: 110, alignment: .trailing)
                Text("Modified")
                    .font(.caption.bold())
                    .frame(width: 160, alignment: .trailing)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor))

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(state.files) { file in
                        HStack {
                            Text(file.relativePath)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(AppState.formatBytes(file.size))
                                .monospacedDigit()
                                .frame(width: 110, alignment: .trailing)
                            Text(dateText(file.modified))
                                .monospacedDigit()
                                .frame(width: 160, alignment: .trailing)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        Divider()
                    }
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay {
            if state.files.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.system(size: 34))
                        .foregroundStyle(.secondary)
                    Text("No Files Loaded")
                        .font(.headline)
                    Text("Select a device and click Refresh List.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var logPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Download Log")
                    .font(.headline)
                Spacer()
                Button("Clear") {
                    state.clearLogs()
                }
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(state.logs.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(8)
            }
            .frame(height: 130)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private var statusBar: some View {
        HStack {
            Text(state.status)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Text("\(state.files.count) file(s)")
                .foregroundStyle(.secondary)
            Text(AppState.formatBytes(state.totalSize))
                .foregroundStyle(.secondary)
        }
        .font(.callout)
    }

    private func dateText(_ modified: Int64) -> String {
        guard modified > 0 else {
            return "-"
        }
        return Self.dateFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(modified) / 1000))
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}

struct BrandLogo: View {
    var body: some View {
        if let image = logoImage {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            Image(systemName: "iphone.radiowaves.left.and.right")
                .resizable()
                .scaledToFit()
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.cyan)
        }
    }

    private var logoImage: NSImage? {
        Bundle.module.url(forResource: "sync-my-mobile-logo", withExtension: "png")
            .flatMap { NSImage(contentsOf: $0) }
            ?? NSImage(named: "sync-my-mobile-logo")
            ?? Bundle.main.url(forResource: "sync-my-mobile-logo", withExtension: "png")
                .flatMap { NSImage(contentsOf: $0) }
    }
}
