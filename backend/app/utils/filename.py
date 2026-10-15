"""Sanitasi nama file agar aman di semua OS."""
import re

_ILLEGAL = re.compile(r'[<>:"/\\|?*\x00-\x1f]')
_WS = re.compile(r"\s+")


def sanitize_filename(name: str, max_len: int = 120) -> str:
    base = _WS.sub(" ", (name or "").strip())
    base = _ILLEGAL.sub("", base).strip(" .")
    if not base:
        base = "download"
    # pisahkan ekstensi agar truncate tidak motong ekstensi
    if "." in base:
        stem, dot, ext = base.rpartition(".")
        ext = re.sub(r"[^A-Za-z0-9]+", "", ext)[:8]
        keep = max_len - (len(ext) + 1 if ext else 0)
        stem = stem[:keep].rstrip(" .") or "download"
        base = f"{stem}.{ext}" if ext else stem
    else:
        base = base[:max_len] or "download"
    if base.lower() in {".", ".."}:
        base = "download"
    return base
