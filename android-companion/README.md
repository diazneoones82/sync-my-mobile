# Android Companion

Open this folder in Android Studio:

```text
D:\projects\sync my mobile\android-companion
```

Run the app on a physical Android phone, select one or more folders, then press `Start LAN Sync`.

The phone will:

- Keep a foreground sync service alive.
- Broadcast discovery beacons to Windows on UDP `47854`.
- Serve a file manifest at `http://PHONE_IP:47855/manifest`.
- Serve file contents through `http://PHONE_IP:47855/file?id=...`.

Both devices must be on the same local network. Some routers block peer-to-peer Wi-Fi traffic; if discovery does not work, try the same non-guest Wi-Fi network.
