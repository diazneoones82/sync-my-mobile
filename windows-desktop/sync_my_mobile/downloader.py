from __future__ import annotations

import os
import re
import shutil
import tempfile
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

from .device_api import DeviceApi, RemoteFile
from .protocol import BUFFER_SIZE


ProgressCallback = Callable[[str, int, int, int], None]
LogCallback = Callable[[str], None]


@dataclass(frozen=True)
class DownloadSummary:
    downloaded: int
    skipped: int
    failed: int


class FolderDownloader:
    def __init__(
        self,
        api: DeviceApi,
        destination_root: Path,
        workers: int,
        on_progress: ProgressCallback,
        on_log: LogCallback,
    ) -> None:
        self.api = api
        self.destination_root = destination_root
        self.workers = max(1, min(workers, 32))
        self.on_progress = on_progress
        self.on_log = on_log

    def download_all(self, files: list[RemoteFile]) -> DownloadSummary:
        self.destination_root.mkdir(parents=True, exist_ok=True)
        downloaded = 0
        skipped = 0
        failed = 0
        unique_files = unique_by_target(files)

        with ThreadPoolExecutor(max_workers=self.workers, thread_name_prefix="download") as pool:
            futures = [pool.submit(self._download_one, remote_file) for remote_file in unique_files]
            for future in as_completed(futures):
                result = future.result()
                if result == "downloaded":
                    downloaded += 1
                elif result == "skipped":
                    skipped += 1
                else:
                    failed += 1

        return DownloadSummary(downloaded=downloaded, skipped=skipped, failed=failed)

    def _download_one(self, remote_file: RemoteFile) -> str:
        target = self.destination_root / sanitize_relative_path(remote_file.relative_path)
        target.parent.mkdir(parents=True, exist_ok=True)

        if target.exists() and target.stat().st_size == remote_file.size:
            self.on_progress(remote_file.relative_path, remote_file.size, remote_file.size, 0)
            self.on_log(f"Skipped {remote_file.relative_path}")
            return "skipped"

        fd, temp_name = tempfile.mkstemp(prefix=".sync-", suffix=".part", dir=str(target.parent))
        os.close(fd)
        temp_path = Path(temp_name)
        written = 0

        try:
            with self.api.open_file(remote_file.id) as response:
                header_name = filename_from_content_disposition(response.headers.get("Content-Disposition"))
                if header_name and target.name.lower() in {"download", "view", "uc", "drive.google.com-uc"}:
                    target = target.with_name(sanitize_filename(header_name))
                    target.parent.mkdir(parents=True, exist_ok=True)
                with temp_path.open("wb") as output:
                    while True:
                        chunk = response.read(BUFFER_SIZE)
                        if not chunk:
                            break
                        output.write(chunk)
                        written += len(chunk)
                        self.on_progress(remote_file.relative_path, written, remote_file.size, len(chunk))

            shutil.move(str(temp_path), str(target))
            if remote_file.modified > 0:
                os.utime(target, (remote_file.modified / 1000, remote_file.modified / 1000))
            self.on_log(f"Downloaded {remote_file.relative_path}")
            return "downloaded"
        except Exception as exc:
            self.on_log(f"Failed {remote_file.relative_path}: {exc}")
            try:
                temp_path.unlink(missing_ok=True)
            except OSError:
                pass
            return "failed"


def sanitize_relative_path(value: str) -> Path:
    clean = value.replace("\\", "/").lstrip("/")
    parts = []
    for part in clean.split("/"):
        if not part or part in {".", ".."}:
            continue
        safe = re.sub(r'[<>:"|?*\x00-\x1f]', "_", part).strip()
        parts.append(safe or "_")
    return Path(*parts) if parts else Path("unnamed")


def sanitize_filename(value: str) -> str:
    return re.sub(r'[<>:"/\\|?*\x00-\x1f]', "_", value).strip() or "download"


def filename_from_content_disposition(value: str | None) -> str | None:
    if not value:
        return None
    match = re.search(r'filename\*?=(?:UTF-8\'\')?"?([^";]+)"?', value, re.IGNORECASE)
    if not match:
        return None
    return match.group(1).strip()


def unique_by_target(files: list[RemoteFile]) -> list[RemoteFile]:
    unique: dict[str, RemoteFile] = {}
    for remote_file in files:
        target_key = str(sanitize_relative_path(remote_file.relative_path)).casefold()
        if target_key not in unique:
            unique[target_key] = remote_file
    return list(unique.values())
