from __future__ import annotations

import json
import socket
import threading
import time
from dataclasses import dataclass
from typing import Callable

from .protocol import APP_ID, DISCOVERY_PORT


@dataclass(frozen=True)
class Device:
    name: str
    host: str
    port: int
    last_seen: float

    @property
    def base_url(self) -> str:
        return f"http://{self.host}:{self.port}"


class DiscoveryListener:
    def __init__(self, on_device: Callable[[Device], None]) -> None:
        self._on_device = on_device
        self._stop = threading.Event()
        self._thread: threading.Thread | None = None

    def start(self) -> None:
        if self._thread and self._thread.is_alive():
            return
        self._stop.clear()
        self._thread = threading.Thread(target=self._listen, name="discovery-listener", daemon=True)
        self._thread.start()

    def stop(self) -> None:
        self._stop.set()

    def _listen(self) -> None:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            sock.bind(("", DISCOVERY_PORT))
            sock.settimeout(1.0)
            while not self._stop.is_set():
                try:
                    payload, address = sock.recvfrom(4096)
                except socket.timeout:
                    continue
                except OSError:
                    break

                device = self._parse_device(payload, address[0])
                if device:
                    self._on_device(device)

    @staticmethod
    def _parse_device(payload: bytes, host: str) -> Device | None:
        try:
            data = json.loads(payload.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            return None

        if data.get("app") != APP_ID:
            return None

        name = str(data.get("deviceName") or host)
        try:
            port = int(data.get("port"))
        except (TypeError, ValueError):
            return None

        return Device(name=name, host=host, port=port, last_seen=time.time())
