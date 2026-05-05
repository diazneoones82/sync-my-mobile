# Sync My Mobile iOS Companion

This is the native iPhone companion for Sync My Mobile. It mirrors the Android APK flow where possible:

- Choose Source has two options: Phone Internal Storage and Cloud Files.
- Cloud Files uses the iOS Files picker, so iCloud Drive, Google Drive, OneDrive, and Box can appear from the Browse/Open From locations list when their apps are installed and signed in.
- Start LAN Sync starts a TCP HTTP server on port `47855` and broadcasts the same UDP discovery payload on port `47854` used by the Windows desktop app.
- The Windows desktop app can call `/manifest` and `/file?id=...` exactly as it does for Android.

## Build On macOS

iOS apps cannot be built or signed on Windows. To build this project:

1. Copy or open `ios-companion/SyncMyMobileiOS.xcodeproj` on a Mac with Xcode installed.
2. Open the project in Xcode.
3. Select the `SyncMyMobileiOS` target.
4. Set your Apple developer team under Signing & Capabilities.
5. Change the bundle identifier if needed.
6. Connect an iPhone, choose it as the run destination, and press Run.

For an installable `.ipa`, use Xcode Product > Archive, then Distribute App.

## iOS Notes

iOS does not allow apps to terminate themselves like Android. The `Exit` button stops the LAN sync server and beacon; the user closes the app from the iPhone App Switcher.

The first time LAN sync starts, iOS should ask for Local Network permission. Allow it so the Windows desktop app can discover and connect to the iPhone.
