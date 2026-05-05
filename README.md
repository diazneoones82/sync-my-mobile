# Neo Apps / Sync My Mobile

Sync My Mobile is an open-source LAN sync toolkit for moving selected mobile files to a Windows desktop when both devices are on the same network.

## Apps

- `windows-desktop`: final Windows desktop app built with Python/Tkinter. It discovers phones, shows available files, downloads with parallel workers, supports tray minimize, dark mode, auto sync, and clearable download logs.
- `android-companion`: native Android companion app. It lets users select phone storage or cloud files through Android pickers, starts LAN sync, and serves selected files to the desktop app.
- `ios-companion`: native SwiftUI iPhone companion source project. It mirrors the APK flow where iOS allows, but must be built on macOS with Xcode and Apple signing.
- `ios-companion/mac-desktop`: native macOS desktop downloader built with SwiftUI. It mirrors the Windows desktop workflow for Mac users.

## Final Builds

Final build artifacts are in `dist`:

- `Sync My Mobile Desktop.exe`
- `Sync My Mobile Android.apk`

The Windows EXE file metadata uses `Neo Apps` as the company name. Windows will still show an unknown verified publisher unless the EXE is Authenticode-signed with a trusted code-signing certificate.

## How It Works

1. Mobile and Windows devices connect to the same Wi-Fi/LAN.
2. The mobile app starts a LAN HTTP server on port `47855`.
3. The mobile app broadcasts discovery beacons on UDP port `47854`.
4. The Windows app discovers the phone, reads `/manifest`, and downloads selected files from `/file?id=...`.
5. Downloads run concurrently using a configurable thread pool.

The transfer is local-network only. There is no hosted cloud backend.

## Android

Open `android-companion` in Android Studio or build with Gradle:

```powershell
& "build\tools\gradle-8.10.2\bin\gradle.bat" -p "android-companion" clean assembleDebug
```

The APK output is:

```text
android-companion/app/build/outputs/apk/debug/app-debug.apk
```

## Windows Desktop

Run from source:

```powershell
cd windows-desktop
python -m sync_my_mobile
```

Build the EXE:

```powershell
python -m PyInstaller --noconfirm --clean --windowed --onefile --name "Sync My Mobile Desktop" --icon "..\assets\sync-my-mobile.ico" --version-file "version_info.txt" --add-data "sync_my_mobile\assets;assets" launcher.py
```

## iOS

Open `ios-companion/SyncMyMobileiOS.xcodeproj` on a Mac with Xcode. Set your Apple developer team, connect an iPhone, and run. iOS apps cannot be built or signed on Windows.

Quick iPhone flow:

1. Install the iOS app from Xcode.
2. Open the app and allow Local Network access.
3. Use `Choose Source > Cloud Files`, `Browse Files App`, or `On My iPhone Folder`.
4. Tap `Start LAN Sync`.
5. Keep the iPhone unlocked and the app in the foreground while downloading.
6. Use the Windows or Mac desktop app to refresh and download.

Full iOS instructions are in `ios-companion/README.md`.

## macOS Desktop

The macOS desktop app is in `ios-companion/mac-desktop`.

Run from source on a Mac:

```bash
cd ios-companion/mac-desktop
swift run
```

Build a release executable:

```bash
cd ios-companion/mac-desktop
swift build -c release
```

Use it like the Windows app:

1. Start LAN sync on the Android or iPhone companion.
2. Open the Mac desktop app.
3. Wait for the phone to appear, or add `PHONE_IP:47855` manually.
4. Click `Refresh List`.
5. Choose a download folder.
6. Click `Download All`.

Full Mac desktop instructions are in `ios-companion/mac-desktop/README.md`.

## Security Notes

This app trusts devices on the same LAN. Avoid untrusted networks. A future production version should add pairing codes and authenticated requests.

## License

MIT License. See `LICENSE`.
