# Sync My Mobile Mac Desktop

Native macOS desktop app for Sync My Mobile by Neo Apps. It mirrors the Windows desktop app workflow and uses the same Sync My Mobile / Neo Apps branding:

- Discovers Android/iPhone companion apps on the local network.
- Reads `/manifest` from the selected phone.
- Shows selected files.
- Downloads files from `/file?id=...`.
- Supports manual IP entry when discovery is blocked.
- Shows the Sync My Mobile logo and Neo Apps About information.

## Run From Source

```bash
cd mac-desktop
swift run
```

## Build

```bash
cd mac-desktop
swift build -c release
```

The release executable is created at:

```text
mac-desktop/.build/release/SyncMyMobileMac
```

## Packaged App

This workspace also includes a packaged app bundle:

```text
build/mac-app/SyncMyMobileMac.app
```

If macOS blocks the app because it is not notarized:

1. Open `System Settings`.
2. Go to `Privacy & Security`.
3. Scroll to the security warning.
4. Click `Open Anyway`.
5. Confirm `Open`.

## Usage

1. Start LAN sync on the iPhone or Android companion app.
2. Open `SyncMyMobileMac.app`. The app displays as `Sync My Mobile`.
3. Wait for the phone to appear in `Devices`.
4. If discovery does not work, enter `IPHONE_IP` or `IPHONE_IP:47855` and click `Add`.
5. Click `Refresh List`.
6. Choose a download folder.
7. Click `Download All`.

Keep the iPhone companion app open in the foreground while downloading. iOS may pause the local server if the phone locks or the app goes into the background.

## Network Details

The companion apps use:

- UDP discovery port: `47854`
- HTTP server port: `47855`
- Manifest URL: `http://PHONE_IP:47855/manifest`
- File URL: `http://PHONE_IP:47855/file?id=...`

If discovery or downloads fail, make sure macOS firewall, Windows firewall, and iPhone Local Network permissions allow LAN connections.
