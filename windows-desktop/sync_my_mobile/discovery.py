from __future__ import annotations

import ipaddress
import json
import socket
import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass
from typing import Callable
from urllib.error import URLError
from urllib.request import Request, urlopen

from .protocol import APP_ID, DEFAULT_HTTP_PORT, DISCOVERY_PORT


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
        self._udp_thread: threading.Thread | None = None
        self._scan_thread: threading.Thread | None = None

    def start(self) -> None:
        if self._udp_thread and self._udp_thread.is_alive():
            return
        self._stop.clear()
        self._udp_thread = threading.Thread(target=self._listen, name="discovery-listener", daemon=True)
        self._scan_thread = threading.Thread(target=self._scan_loop, name="iphone-port-scanner", daemon=True)
        self._udp_thread.start()
        self._scan_thread.start()

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

    def _scan_loop(self) -> None:
        while not self._stop.is_set():
            self._scan_port_47855()
            self._stop.wait(8.0)

    def _scan_port_47855(self) -> None:
        hosts = self._candidate_hosts()
        if not hosts:
            return
        with ThreadPoolExecutor(max_workers=64, thread_name_prefix="iphone-scan") as pool:
            futures = [pool.submit(self._probe_manifest, host) for host in hosts]
            for future in as_completed(futures):
                if self._stop.is_set():
                    break
                device = future.result()
                if device:
                    self._on_device(device)

    def _candidate_hosts(self) -> list[str]:
        networks: set[ipaddress.IPv4Network] = set()
        for address in self._local_ipv4_addresses():
            try:
                networks.add(ipaddress.ip_network(f"{address}/24", strict=False))
            except ValueError:
                continue
        return sorted({str(host) for network in networks for host in network.hosts()})

    def _local_ipv4_addresses(self) -> set[str]:
        addresses: set[str] = set()
        hostname = socket.gethostname()
        try:
            for address in socket.gethostbyname_ex(hostname)[2]:
                if self._is_lan_ipv4(address):
                    addresses.add(address)
        except socket.gaierror:
            pass

        try:
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
                sock.connect(("8.8.8.8", 80))
                address = sock.getsockname()[0]
                if self._is_lan_ipv4(address):
                    addresses.add(address)
        except OSError:
            pass

        return addresses

    @staticmethod
    def _is_lan_ipv4(address: str) -> bool:
        try:
            ip = ipaddress.ip_address(address)
        except ValueError:
            return False
        return ip.version == 4 and not ip.is_loopback and not ip.is_link_local

    def _probe_manifest(self, host: str) -> Device | None:
        url = f"http://{host}:{DEFAULT_HTTP_PORT}/manifest"
        request = Request(url, headers={"User-Agent": "SyncMyMobile-Windows/0.1"})
        try:
            with urlopen(request, timeout=0.45) as response:
                data = json.loads(response.read(128 * 1024).decode("utf-8"))
        except (OSError, TimeoutError, URLError, UnicodeDecodeError, json.JSONDecodeError):
            return None

        if data.get("app") != APP_ID:
            return None
        name = str(data.get("deviceName") or f"iPhone {host}")
        return Device(name=name, host=host, port=DEFAULT_HTTP_PORT, last_seen=time.time())

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
