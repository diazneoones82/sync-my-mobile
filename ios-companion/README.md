# Sync My Mobile iOS Companion

Native iPhone companion app for Sync My Mobile. The Windows desktop app discovers this iPhone on the local network, reads a file list, and downloads selected files over LAN.

## What iOS Allows

Unlike Android, iOS does **not** allow apps to browse the whole phone storage.

This app can share:

- Files/folders you select in the iOS Files picker.
- Cloud files visible in Files, such as iCloud Drive, Google Drive, OneDrive, and Box.
- Files placed in `Files > On My iPhone > Sync My Mobile`.

This app cannot browse:

- All internal storage.
- System folders.
- Private app data.
- WhatsApp/app folders unless they expose files through Files.
- Photos library files unless a separate Photos picker is added.

## Quick Start

1. Install the app from Xcode.
2. Open the app once on iPhone.
3. Allow `Local Network` when prompted.
4. Add files using one of these:
   - `Choose Source > Cloud Files`
   - `Choose Source > Browse Files App`
   - `Choose Source > On My iPhone Folder`
5. Tap `Start LAN Sync`.
6. Open the Windows desktop app.
7. Click `Refresh List`.
8. Download the files.

Keep the iPhone unlocked and keep Sync My Mobile open while downloading.

## Requirements

- macOS with Xcode installed.
- Apple ID signed in to Xcode.
- iPhone connected by USB for installation.
- Windows desktop app on the same network as the iPhone.
- Local network access allowed on iPhone.
- Firewall rules on Windows must allow the desktop app to connect.

## Install On iPhone

1. Connect iPhone to the Mac by USB.
2. Unlock iPhone and keep it awake.
3. Tap `Trust This Computer` if prompted.
4. Open `SyncMyMobileiOS.xcodeproj` in Xcode.
5. Select the `SyncMyMobileiOS` project.
6. Select the `SyncMyMobileiOS` target.
7. Open `Signing & Capabilities`.
8. Enable `Automatically manage signing`.
9. Select your Apple developer team.
10. If Xcode reports a bundle identifier conflict, change `com.neoapps.syncmymobile.ios` to something unique, such as `com.yourname.syncmymobile.ios`.
11. Select your iPhone in Xcode's device picker.
12. Wait for Xcode to finish pairing or preparing the device.
13. Click `Run`.

The app should install and open on the iPhone.

## Trust The App

If iPhone says the developer is not trusted:

1. Open iPhone `Settings`.
2. Go to `General`.
3. Open `VPN & Device Management`.
4. Under `Developer App`, tap your Apple ID/developer profile.
5. Tap `Trust`.
6. Confirm `Trust`.
7. Open Sync My Mobile again.

If `VPN & Device Management` is missing, try opening the app once first. iOS often shows this setting only after the developer app has been blocked once.

## Enable Developer Mode

Some iPhones require Developer Mode for Xcode-installed apps.

1. Open iPhone `Settings`.
2. Go to `Privacy & Security`.
3. Tap `Developer Mode`.
4. Turn it on.
5. Restart iPhone if prompted.
6. Confirm Developer Mode after restart.

If `Developer Mode` is missing:

1. Open Xcode on the Mac.
2. Go to `Window > Devices and Simulators`.
3. Select the iPhone.
4. Wait for pairing/preparation to finish.
5. Check iPhone settings again.

## Allow Local Network

The first time you tap `Start LAN Sync`, iOS should ask for Local Network access.

Tap `Allow`.

If you tapped `Don't Allow`:

1. Open iPhone `Settings`.
2. Scroll to `Sync My Mobile`.
3. Enable `Local Network`.

Without this permission, the Windows desktop app may not discover or connect to the iPhone.

## Select Cloud Files

Use this for iCloud Drive, Google Drive, OneDrive, Box, and other providers that appear in Files.

1. Install and sign in to the provider app on iPhone.
2. Open Sync My Mobile.
3. Tap `Choose Source`.
4. Tap `Cloud Files`.
5. In the Files picker, tap `Browse`.
6. Choose the cloud provider from Locations.
7. Select one or more files.
8. Confirm selection.
9. Tap `Start LAN Sync`.
10. Refresh the Windows desktop file list.

Tip: make cloud files available offline before selecting them. If the app says only some files imported, open those files once in Files or mark them available offline, then select again.

## Select Files On iPhone

The app exposes this folder in the iPhone Files app:

```text
Files > Browse > On My iPhone > Sync My Mobile
```

Use it like this:

1. Open Sync My Mobile once after installation.
2. Open the iPhone `Files` app.
3. Tap `Browse`.
4. Open `On My iPhone`.
5. Open `Sync My Mobile`.
6. Place files or folders there.
7. Return to Sync My Mobile.
8. Tap `Choose Source`.
9. Tap `On My iPhone Folder`.
10. Tap `Start LAN Sync`.
11. Refresh the Windows desktop file list.

If the folder does not appear, open Sync My Mobile once, force-close and reopen Files, then check `On My iPhone` again.

## Browse Files App

`Choose Source > Browse Files App` opens Apple's Files picker.

Use this to select files or folders outside the app folder. Only items visible in the Files picker can be selected.

## Download Notes

Keep Sync My Mobile open in the foreground while downloading.

iOS may pause the local file server when:

- iPhone locks.
- App goes to the background.
- Network changes.
- Low Power Mode becomes aggressive.

If Windows shows a timeout:

1. Unlock iPhone.
2. Open Sync My Mobile.
3. Tap `Start LAN Sync`.
4. Refresh/download again from Windows.

## Desktop Connection Details

The iPhone app uses:

- UDP discovery port: `47854`
- HTTP file server port: `47855`
- Manifest URL: `http://IPHONE_IP:47855/manifest`
- File URL: `http://IPHONE_IP:47855/file?id=...`

If discovery fails, use the desktop app's manual IP connection option with the iPhone IP address and port `47855`.

## Build An IPA

For normal development use, install with Xcode `Run`.

To archive:

1. Open the project in Xcode.
2. Select `Any iOS Device`.
3. Choose `Product > Archive`.
4. Choose `Distribute App`.
5. Select the distribution method for your Apple account.

Development-signed IPAs only install on devices included in the provisioning profile.

## Troubleshooting

### App Installs But Will Not Open

- Trust the developer profile in `Settings > General > VPN & Device Management`.
- Enable Developer Mode if prompted.
- Reinstall from Xcode after trusting the iPhone.

### Desktop Shows No Files

- Tap `Clear Selections` in the iPhone app.
- Select files again.
- Confirm the app reports the correct imported count.
- Tap `Start LAN Sync`.
- Keep the iPhone app open.
- Click `Refresh List` in the Windows app.

### Downloads Timeout

- Keep iPhone unlocked.
- Keep Sync My Mobile in the foreground.
- Make cloud files available offline before selecting.
- Make sure iPhone and Windows are on the same network.
- Check Windows firewall rules.

### On My iPhone Folder Missing

- Open Sync My Mobile once.
- Reopen the Files app.
- Tap `Browse` until Locations appears.
- Open `On My iPhone`.
- Look for `Sync My Mobile`.
- Reinstall the latest signed build if needed.
