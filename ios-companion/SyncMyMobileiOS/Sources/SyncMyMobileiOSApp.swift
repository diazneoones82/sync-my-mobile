import SwiftUI

@main
struct SyncMyMobileiOSApp: App {
    @StateObject private var model = SyncModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
        }
    }
}
