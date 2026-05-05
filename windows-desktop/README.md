# Windows Desktop App

Run:

```powershell
python -m sync_my_mobile
```

No third-party Python packages are required.

The app listens for Android companion beacons on UDP `47854`, shows discovered devices, then downloads files using a configurable thread pool.
