import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var model: SyncModel
    @State private var showSourceChooser = false
    @State private var showPhoneFolderPicker = false
    @State private var showCloudFilePicker = false
    @State private var darkMode = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    Image(systemName: "iphone.radiowaves.left.and.right")
                        .font(.system(size: 72, weight: .semibold))
                        .foregroundStyle(accent)
                        .padding(.top, 16)

                    Text("Sync My Mobile")
                        .font(.title.bold())
                        .foregroundStyle(foreground)

                    Text("Neo Apps")
                        .font(.subheadline.bold())
                        .foregroundStyle(accent)

                    Toggle("Dark Mode", isOn: $darkMode)
                        .tint(accent)
                        .foregroundStyle(foreground)
                        .padding(.horizontal)

                    selectedPanel

                    Button("Choose Source") { showSourceChooser = true }
                        .buttonStyle(.borderedProminent)

                    Button("Clear Selections") { model.clearSelections() }
                        .buttonStyle(.bordered)

                    HStack {
                        Text("Auto interval")
                        Spacer()
                        Stepper("\(model.autoIntervalMinutes) minute(s)", value: $model.autoIntervalMinutes, in: 1...240)
                    }
                    .foregroundStyle(foreground)
                    .padding(.horizontal)

                    Button("Start LAN Sync") { model.startSync() }
                        .buttonStyle(.borderedProminent)

                    Button("Stop Sync") { model.stopSync(message: "Sync has stopped") }
                        .buttonStyle(.bordered)

                    Button("About") { model.showAbout = true }
                        .buttonStyle(.bordered)

                    Button("Cloud Access Help") { model.showCloudHelp = true }
                        .buttonStyle(.bordered)

                    Button("Exit") { model.stopSync(message: "Sync stopped. Close the app from the iPhone App Switcher.") }
                        .buttonStyle(.bordered)

                    TimelineView(.periodic(from: .now, by: 0.1)) { context in
                        Text(Self.footerDateFormatter.string(from: context.date))
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(accent)
                            .multilineTextAlignment(.center)
                            .padding(.top, 8)
                    }
                }
                .padding(20)
            }
            .background(background.ignoresSafeArea())
            .confirmationDialog("Choose source", isPresented: $showSourceChooser) {
                Button("Phone Internal Storage") { showPhoneFolderPicker = true }
                Button("Cloud Files") { showCloudFilePicker = true }
                Button("Cancel", role: .cancel) {}
            }
            .fileImporter(
                isPresented: $showPhoneFolderPicker,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: true,
                onCompletion: model.addPhoneFolders,
            )
            .fileImporter(
                isPresented: $showCloudFilePicker,
                allowedContentTypes: [.item],
                allowsMultipleSelection: true,
                onCompletion: model.addCloudFiles,
            )
            .alert("About Sync My Mobile", isPresented: $model.showAbout) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Author: Bartholomew Diaz Michael\n\nDownloads selected iPhone Files app sources to the Windows desktop over the same local network.\nThe supporting desktop app discovers this phone and downloads files in parallel.")
            }
            .alert("Cloud Access Help", isPresented: $model.showCloudHelp) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Install and sign in to iCloud Drive, Google Drive, OneDrive, or Box. Tap Choose Source, then Cloud Files. Use the Files picker Browse/Open From menu to choose the provider, select one or more files, then allow access.")
            }
            .alert("Sync My Mobile", isPresented: $model.showStatusAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.status)
            }
        }
        .preferredColorScheme(darkMode ? .dark : .light)
    }

    private var selectedPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.selectionSummary.isEmpty ? "No folders or files selected yet." : "Selected:")
                .font(.headline)
            ForEach(model.selectionSummary, id: \.self) { line in
                Text(line)
                    .font(.callout)
                    .foregroundStyle(accent)
            }
            if !model.status.isEmpty {
                Text(model.status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(panel)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var background: Color { darkMode ? Color(red: 0.03, green: 0.07, blue: 0.12) : Color(red: 0.96, green: 0.98, blue: 1.0) }
    private var panel: Color { darkMode ? Color(red: 0.06, green: 0.12, blue: 0.21) : .white }
    private var foreground: Color { darkMode ? Color(red: 0.90, green: 0.97, blue: 1.0) : Color(red: 0.06, green: 0.12, blue: 0.20) }
    private var accent: Color { darkMode ? Color(red: 0.45, green: 0.96, blue: 1.0) : Color(red: 0.15, green: 0.39, blue: 0.92) }

    private static let footerDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()
}
