"""Hapus file temp / hasil lama."""
import time
from pathlib import Path


def remove_file_safe(path: str | Path) -> None:
    try:
        Path(path).unlink(missing_ok=True)
    except OSError:
        pass


def cleanup_old_files(directory: str | Path, max_age_sec: int) -> int:
    d = Path(directory)
    if not d.is_dir():
        return 0
    now = time.time()
    removed = 0
    for p in d.iterdir():
        if not p.is_file() or p.name == ".gitkeep":
            continue
        try:
            if now - p.stat().st_mtime > max_age_sec:
                p.unlink()
                removed += 1
        except OSError:
            continue
    return removed
