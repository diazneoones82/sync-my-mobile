from __future__ import annotations

import queue
import sys
import threading
import time
import tkinter as tk
from pathlib import Path
from tkinter import filedialog, messagebox, simpledialog, ttk

from PIL import Image, ImageTk
import pystray

from .device_api import DeviceApi, Manifest
from .discovery import Device, DiscoveryListener
from .downloader import FolderDownloader, unique_by_target


class SyncMyMobileApp(tk.Tk):
    def __init__(self) -> None:
        super().__init__()
        self.title("Sync My Mobile")
        self.geometry("860x560")
        self.minsize(760, 480)

        self.devices: dict[str, Device] = {}
        self.selected_device: Device | None = None
        self.manifest: Manifest | None = None
        self.events: queue.Queue[tuple[str, object]] = queue.Queue()
        self.destination = Path.home() / "Desktop" / "Sync My Mobile"
        self.tray_icon: pystray.Icon | None = None
        self._closing = False
        self.dark_mode = tk.BooleanVar(value=True)
        self.auto_sync = tk.BooleanVar(value=False)
        self.interval_minutes = tk.IntVar(value=15)
        self.last_auto_sync_at = 0.0
        self.logo_image = Image.open(resource_path("assets/sync-my-mobile-logo.png")).convert("RGBA")
        self.logo_tk = ImageTk.PhotoImage(self.logo_image.resize((58, 58), Image.Resampling.LANCZOS))

        self.discovery = DiscoveryListener(self._device_seen)
        self._configure_icon()
        self._build_ui()
        self._apply_theme()
        self.discovery.start()
        self.after(100, self._drain_events)
        self.after(1000, self._auto_sync_tick)
        self.protocol("WM_DELETE_WINDOW", self._close)
        self.bind("<Unmap>", self._on_unmap)

    def _build_ui(self) -> None:
        self.columnconfigure(0, weight=1)
        self.rowconfigure(2, weight=1)

        header = ttk.Frame(self, padding=12, style="App.TFrame")
        header.grid(row=0, column=0, sticky="ew")
        header.columnconfigure(1, weight=1)

        brand = ttk.Frame(header, style="App.TFrame")
        brand.grid(row=0, column=0, sticky="w", padx=(0, 12))
        ttk.Label(brand, image=self.logo_tk, style="App.TLabel").grid(row=0, column=0, rowspan=2, sticky="w")
        ttk.Label(brand, text="Sync My Mobile", style="Title.TLabel").grid(row=0, column=1, sticky="w", padx=(10, 0))
        ttk.Label(brand, text="Neo Apps", style="Accent.TLabel").grid(row=1, column=1, sticky="w", padx=(10, 0))

        ttk.Label(header, text="Discovered phone", style="App.TLabel").grid(row=1, column=0, sticky="w", pady=(10, 0))
        self.device_var = tk.StringVar()
        self.device_combo = ttk.Combobox(header, textvariable=self.device_var, state="readonly", width=38)
        self.device_combo.grid(row=1, column=1, sticky="ew", padx=8, pady=(10, 0))
        self.device_combo.bind("<<ComboboxSelected>>", lambda _event: self._select_device())

        ttk.Button(header, text="Connect IP", command=self._connect_by_ip).grid(row=1, column=2, padx=4, pady=(10, 0))
        ttk.Button(header, text="Refresh List", command=self._load_manifest).grid(row=1, column=3, padx=4, pady=(10, 0))
        ttk.Button(header, text="Download", command=self._start_download).grid(row=1, column=4, padx=4, pady=(10, 0))
        ttk.Button(header, text="Clear", command=self._clear_download_info).grid(row=1, column=5, padx=4, pady=(10, 0))
        ttk.Button(header, text="About", command=self._show_about).grid(row=1, column=6, padx=4, pady=(10, 0))

        options = ttk.Frame(self, padding=(12, 0, 12, 12), style="App.TFrame")
        options.grid(row=1, column=0, sticky="ew")
        options.columnconfigure(1, weight=1)

        ttk.Label(options, text="Save to", style="App.TLabel").grid(row=0, column=0, sticky="w")
        self.destination_var = tk.StringVar(value=str(self.destination))
        ttk.Entry(options, textvariable=self.destination_var).grid(row=0, column=1, sticky="ew", padx=8)
        ttk.Button(options, text="Browse", command=self._choose_destination).grid(row=0, column=2)

        ttk.Label(options, text="Threads", style="App.TLabel").grid(row=0, column=3, padx=(16, 4), sticky="e")
        self.worker_var = tk.IntVar(value=17)
        ttk.Spinbox(options, from_=1, to=32, textvariable=self.worker_var, width=5).grid(row=0, column=4)

        ttk.Checkbutton(options, text="Auto Sync", variable=self.auto_sync, style="App.TCheckbutton").grid(row=1, column=0, sticky="w", pady=(10, 0))
        ttk.Label(options, text="Every", style="App.TLabel").grid(row=1, column=1, sticky="e", pady=(10, 0))
        ttk.Spinbox(options, from_=1, to=240, textvariable=self.interval_minutes, width=5).grid(row=1, column=2, sticky="w", pady=(10, 0))
        ttk.Label(options, text="minutes", style="App.TLabel").grid(row=1, column=3, sticky="w", pady=(10, 0))
        ttk.Checkbutton(options, text="Dark Mode", variable=self.dark_mode, command=self._apply_theme, style="App.TCheckbutton").grid(row=1, column=4, sticky="e", pady=(10, 0))

        body = ttk.PanedWindow(self, orient=tk.HORIZONTAL)
        body.grid(row=2, column=0, sticky="nsew", padx=12, pady=(0, 12))

        file_frame = ttk.Frame(body, style="Panel.TFrame")
        file_frame.columnconfigure(0, weight=1)
        file_frame.rowconfigure(0, weight=1)
        self.file_list = tk.Listbox(file_frame)
        self.file_list.grid(row=0, column=0, sticky="nsew")
        body.add(file_frame, weight=2)

        log_frame = ttk.Frame(body, style="Panel.TFrame")
        log_frame.columnconfigure(0, weight=1)
        log_frame.rowconfigure(0, weight=1)
        self.log = tk.Text(log_frame, height=12, state="disabled", wrap="word")
        self.log.grid(row=0, column=0, sticky="nsew")
        body.add(log_frame, weight=3)

        footer = ttk.Frame(self, padding=(12, 0, 12, 12), style="App.TFrame")
        footer.grid(row=3, column=0, sticky="ew")
        footer.columnconfigure(0, weight=1)
        self.status_var = tk.StringVar(value="Waiting for Android companion on the same network...")
        ttk.Label(footer, textvariable=self.status_var, style="Accent.TLabel").grid(row=0, column=0, sticky="w")
        self.progress = ttk.Progressbar(footer, mode="determinate")
        self.progress.grid(row=0, column=1, sticky="ew", padx=(8, 0))

    def _apply_theme(self) -> None:
        dark = self.dark_mode.get()
        colors = {
            "bg": "#07111f" if dark else "#f5f9ff",
            "panel": "#0b1729" if dark else "#ffffff",
            "fg": "#e6f7ff" if dark else "#102033",
            "muted": "#73f6ff" if dark else "#2563eb",
            "field": "#101f35" if dark else "#ffffff",
            "select": "#164e63" if dark else "#dbeafe",
            "text": "#d9fbff" if dark else "#102033",
        }
        self.configure(bg=colors["bg"])
        style = ttk.Style(self)
        style.theme_use("clam")
        style.configure("App.TFrame", background=colors["bg"])
        style.configure("Panel.TFrame", background=colors["panel"])
        style.configure("App.TLabel", background=colors["bg"], foreground=colors["fg"])
        style.configure("Title.TLabel", background=colors["bg"], foreground=colors["fg"], font=("Segoe UI", 18, "bold"))
        style.configure("Accent.TLabel", background=colors["bg"], foreground=colors["muted"], font=("Segoe UI", 10, "bold"))
        style.configure("App.TCheckbutton", background=colors["bg"], foreground=colors["fg"])
        style.map("App.TCheckbutton", background=[("active", colors["bg"])], foreground=[("active", colors["muted"])])
        style.configure("TButton", background="#12324d" if dark else "#dbeafe", foreground=colors["fg"], bordercolor=colors["muted"])
        style.map("TButton", background=[("active", "#155e75" if dark else "#bfdbfe")])
        style.configure("TEntry", fieldbackground=colors["field"], foreground=colors["text"])
        style.configure("TCombobox", fieldbackground=colors["field"], foreground=colors["text"])
        style.configure("TSpinbox", fieldbackground=colors["field"], foreground=colors["text"])
        style.configure("Horizontal.TProgressbar", background=colors["muted"], troughcolor=colors["panel"])
        self.file_list.configure(bg=colors["field"], fg=colors["text"], selectbackground=colors["select"], highlightbackground=colors["muted"])
        self.log.configure(bg=colors["field"], fg=colors["text"], insertbackground=colors["text"], highlightbackground=colors["muted"])

    def _device_seen(self, device: Device) -> None:
        self.events.put(("device", device))

    def _drain_events(self) -> None:
        try:
            while True:
                kind, payload = self.events.get_nowait()
                if kind == "device":
                    self._update_device(payload)  # type: ignore[arg-type]
                elif kind == "manifest":
                    self._show_manifest(payload)  # type: ignore[arg-type]
                elif kind == "log":
                    self._append_log(str(payload))
                elif kind == "status":
                    self.status_var.set(str(payload))
                elif kind == "progress":
                    done, total, label = payload  # type: ignore[misc]
                    self.progress["maximum"] = max(total, 1)
                    self.progress["value"] = done
                    if label:
                        self.status_var.set(str(label))
        except queue.Empty:
            pass
        self.after(100, self._drain_events)

    def _update_device(self, device: Device) -> None:
        key = f"{device.name} ({device.host}:{device.port})"
        self.devices[key] = device
        self.device_combo["values"] = sorted(self.devices.keys())
        if not self.selected_device:
            self.device_var.set(key)
            self._select_device()
        self.status_var.set(f"Found {device.name} at {device.host}")

    def _select_device(self) -> None:
        self.selected_device = self.devices.get(self.device_var.get())

    def _connect_by_ip(self) -> None:
        value = simpledialog.askstring("Connect by IP", "Android phone IP or IP:port")
        if not value:
            return
        host, _, port_text = value.strip().partition(":")
        try:
            port = int(port_text) if port_text else 47855
        except ValueError:
            messagebox.showerror("Sync My Mobile", "Port must be a number.")
            return
        device = Device(name=f"Manual {host}", host=host, port=port, last_seen=0)
        self._update_device(device)
        self._load_manifest()

    def _load_manifest(self) -> None:
        if not self.selected_device:
            messagebox.showinfo("Sync My Mobile", "Start the Android companion app on the same network first.")
            return
        self.status_var.set("Loading manifest...")
        threading.Thread(target=self._load_manifest_worker, daemon=True).start()

    def _load_manifest_worker(self) -> None:
        try:
            manifest = DeviceApi(self.selected_device.base_url).get_manifest()  # type: ignore[union-attr]
            self.events.put(("manifest", manifest))
        except Exception as exc:
            self.events.put(("status", f"Manifest failed: {exc}"))

    def _show_manifest(self, manifest: Manifest) -> None:
        deduped_files = unique_by_target(manifest.files)
        self.manifest = Manifest(device_name=manifest.device_name, files=deduped_files)
        self.file_list.delete(0, tk.END)
        for item in deduped_files:
            self.file_list.insert(tk.END, f"{item.relative_path} ({item.size:,} bytes)")
        total_size = sum(item.size for item in deduped_files)
        duplicate_count = len(manifest.files) - len(deduped_files)
        suffix = f" ({duplicate_count} duplicates hidden)" if duplicate_count else ""
        self.status_var.set(f"{len(deduped_files)} files ready, {total_size:,} bytes{suffix}")

    def _choose_destination(self) -> None:
        selected = filedialog.askdirectory(initialdir=str(self.destination))
        if selected:
            self.destination_var.set(selected)

    def _start_download(self) -> None:
        if not self.selected_device:
            messagebox.showinfo("Sync My Mobile", "No Android device selected.")
            return
        if not self.manifest:
            self._load_manifest()
            return
        self.progress["value"] = 0
        self.progress["maximum"] = max(len(self.manifest.files), 1)
        threading.Thread(target=self._download_worker, daemon=True).start()

    def _download_worker(self) -> None:
        assert self.selected_device is not None
        assert self.manifest is not None

        completed: set[str] = set()
        total_bytes = sum(file.size for file in self.manifest.files)
        transferred_bytes = 0
        progress_by_file: dict[str, int] = {}
        progress_lock = threading.Lock()

        def on_progress(relative_path: str, written: int, total: int, chunk_size: int) -> None:
            nonlocal transferred_bytes
            with progress_lock:
                previous = progress_by_file.get(relative_path, 0)
                progress_by_file[relative_path] = max(previous, written)
                transferred_bytes += max(0, written - previous)
                if total == 0 or written >= total:
                    completed.add(relative_path)
                file_total = format_size(total) if total > 0 else "unknown"
                grand_total = format_size(total_bytes) if total_bytes > 0 else "unknown"
                label = f"Downloading {relative_path}: {format_size(written)} / {file_total} ({format_size(transferred_bytes)} / {grand_total} total)"
            if total == 0 or written >= total:
                self.events.put(("progress", (len(completed), len(self.manifest.files), label)))
            elif chunk_size:
                self.events.put(("progress", (len(completed), len(self.manifest.files), label)))

        def on_log(message: str) -> None:
            self.events.put(("log", message))

        target = Path(self.destination_var.get()) / self.manifest.device_name
        downloader = FolderDownloader(
            api=DeviceApi(self.selected_device.base_url),
            destination_root=target,
            workers=self.worker_var.get(),
            on_progress=on_progress,
            on_log=on_log,
        )
        self.events.put(("status", "Downloading..."))
        summary = downloader.download_all(self.manifest.files)
        self.events.put(("status", f"Done. Downloaded {summary.downloaded}, skipped {summary.skipped}, failed {summary.failed}."))

    def _auto_sync_tick(self) -> None:
        due_seconds = max(1, self.interval_minutes.get()) * 60
        if self.auto_sync.get() and self.selected_device and time.time() - self.last_auto_sync_at >= due_seconds:
            self.last_auto_sync_at = time.time()
            threading.Thread(target=self._auto_sync_worker, daemon=True).start()
        self.after(30_000, self._auto_sync_tick)

    def _auto_sync_worker(self) -> None:
        try:
            manifest = DeviceApi(self.selected_device.base_url).get_manifest()  # type: ignore[union-attr]
            clean_manifest = Manifest(device_name=manifest.device_name, files=unique_by_target(manifest.files))
            self.events.put(("manifest", clean_manifest))
            self.manifest = clean_manifest
            self._download_worker()
        except Exception as exc:
            self.events.put(("status", f"Auto sync failed: {exc}"))

    def _append_log(self, message: str) -> None:
        self.log.configure(state="normal")
        self.log.insert(tk.END, message + "\n")
        self.log.see(tk.END)
        self.log.configure(state="disabled")

    def _clear_download_info(self) -> None:
        self.log.configure(state="normal")
        self.log.delete("1.0", tk.END)
        self.log.configure(state="disabled")
        self.progress["value"] = 0
        self.status_var.set("Downloaded list cleared.")

    def _show_about(self) -> None:
        messagebox.showinfo(
            "About Sync My Mobile",
            "Sync My Mobile\n\n"
            "Author: Bartholomew Diaz Michael\n\n"
            "Downloads selected Android phone folders to a Windows desktop over the same local network.\n"
            "The supporting desktop app discovers the phone, syncs files in parallel, and can run in the tray.",
        )

    def _on_unmap(self, _event: tk.Event) -> None:
        if self._closing:
            return
        if self.state() == "iconic":
            self.after(0, self._hide_to_tray)

    def _hide_to_tray(self) -> None:
        self.withdraw()
        self._ensure_tray_icon()

    def _ensure_tray_icon(self) -> None:
        if self.tray_icon:
            return
        self.tray_icon = pystray.Icon(
            "sync-my-mobile",
            _tray_image(),
            "Sync My Mobile",
            menu=pystray.Menu(
                pystray.MenuItem("Open", lambda _icon, _item: self.after(0, self._restore_from_tray), default=True),
                pystray.MenuItem("Quit", lambda _icon, _item: self.after(0, self._close)),
            ),
        )
        threading.Thread(target=self.tray_icon.run, name="tray-icon", daemon=True).start()

    def _restore_from_tray(self) -> None:
        self.deiconify()
        self.state("normal")
        self.lift()
        self.focus_force()

    def _close(self) -> None:
        self._closing = True
        if self.tray_icon:
            self.tray_icon.stop()
            self.tray_icon = None
        self.discovery.stop()
        self.destroy()

    def _configure_icon(self) -> None:
        icon_path = resource_path("assets/sync-my-mobile.ico")
        try:
            self.iconbitmap(icon_path)
        except tk.TclError:
            pass


def main() -> None:
    SyncMyMobileApp().mainloop()


def _tray_image() -> Image.Image:
    return Image.open(resource_path("assets/sync-my-mobile-logo.png")).convert("RGBA").resize((64, 64), Image.Resampling.LANCZOS)


def resource_path(relative_path: str) -> str:
    base = Path(getattr(sys, "_MEIPASS", Path(__file__).resolve().parent))
    candidates = [
        base / relative_path,
        base / "sync_my_mobile" / relative_path,
        Path(__file__).resolve().parent / relative_path,
    ]
    for candidate in candidates:
        if candidate.exists():
            return str(candidate)
    return str(candidates[0])


def format_size(bytes_value: int) -> str:
    value = float(max(0, bytes_value))
    units = ["B", "KB", "MB", "GB", "TB"]
    for unit in units:
        if value < 1024 or unit == units[-1]:
            if unit == "B":
                return f"{int(value)} {unit}"
            return f"{value:.2f} {unit}"
        value /= 1024
