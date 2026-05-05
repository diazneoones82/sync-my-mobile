from __future__ import annotations

import json
from dataclasses import dataclass
from urllib.parse import quote
from urllib.request import Request, urlopen


@dataclass(frozen=True)
class RemoteFile:
    id: str
    relative_path: str
    size: int
    modified: int


@dataclass(frozen=True)
class Manifest:
    device_name: str
    files: list[RemoteFile]


class DeviceApi:
    def __init__(self, base_url: str, timeout: float = 120.0) -> None:
        self.base_url = base_url.rstrip("/")
        self.timeout = timeout

    def get_manifest(self) -> Manifest:
        with urlopen(f"{self.base_url}/manifest", timeout=self.timeout) as response:
            payload = json.loads(response.read().decode("utf-8"))

        files = [
            RemoteFile(
                id=str(item["id"]),
                relative_path=str(item["relativePath"]),
                size=int(item.get("size", 0)),
                modified=int(item.get("modified", 0)),
            )
            for item in payload.get("files", [])
        ]
        return Manifest(device_name=str(payload.get("deviceName") or "Android Phone"), files=files)

    def open_file(self, file_id: str):
        url = f"{self.base_url}/file?id={quote(file_id, safe='')}"
        request = Request(url, headers={"User-Agent": "SyncMyMobile-Windows/0.1"})
        return urlopen(request, timeout=self.timeout)
