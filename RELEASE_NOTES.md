# Sync My Mobile Release

Neo Apps release package for Sync My Mobile desktop and mobile companions.

## Release Assets

- `Sync My Mobile Desktop.exe`: Windows desktop app for discovering phones, refreshing selected-file lists, and downloading files over LAN.
- `Sync My Mobile Android.apk`: Android companion app for selecting device/cloud files and starting LAN sync.
- `SyncMyMobileiOS-device-signed.ipa`: iPhone companion app signed for development/device testing.
- `SyncMyMobileMac.app.zip`: signed macOS desktop companion app. The app displays as `Sync My Mobile` with Neo Apps branding.

## iPhone Companion

- Built with SwiftUI for iPhone.
- Supports Local Network sharing over UDP `47854` and HTTP `47855`.
- Supports selected cloud files, Files app selections, and the app's `On My iPhone` documents folder.
- Keep the app open and the iPhone unlocked while downloading.

Important: the IPA is development/device signed. It installs only on devices allowed by the Apple developer account/provisioning profile used to build it. For public distribution, publish through TestFlight, App Store, or an Ad Hoc profile.

## Mac Companion App

- Native SwiftUI desktop app for macOS 13 or later.
- Discovers Android/iPhone companion apps on the LAN.
- Supports manual `PHONE_IP:47855` entry when discovery is blocked.
- Shows selected files and downloads them to a chosen Mac folder.
- Branded as `Sync My Mobile` by Neo Apps.

The Mac app is signed for local launch but not notarized. If macOS blocks first launch, open `System Settings > Privacy & Security`, choose `Open Anyway`, then confirm `Open`.

## Notes

- All transfers are local-network only.
- Mobile and desktop devices must be on the same Wi-Fi/LAN.
- Firewalls and iPhone Local Network permission must allow the connection.
