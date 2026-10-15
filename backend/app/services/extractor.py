"""Wrapper yt-dlp: info + download (blocking -> dijalankan via to_thread)."""
import asyncio
import os
import uuid
from pathlib import Path

import yt_dlp

from app.config import settings
from app.services.formats import build_format
from app.services.spotify import SpotifyTrack, search_query
from app.utils.filename import sanitize_filename


def _base_opts() -> dict:
    opts: dict = {
        "quiet": True,
        "no_warnings": True,
        "noplaylist": True,
        "retries": 2,
        "socket_timeout": 15,
    }
    cookie = Path(settings.COOKIE_FILE)
    if cookie.is_file():
        opts["cookiefile"] = str(cookie)
    return opts


def _sync_info(url: str) -> dict:
    opts = _base_opts()
    opts["skip_download"] = True
    with yt_dlp.YoutubeDL(opts) as ydl:
        return ydl.extract_info(url, download=False)


def _sync_download(url: str, quality: str, audio_only: bool, container: str) -> str:
    out_dir = Path(settings.DOWNLOAD_DIR)
    out_dir.mkdir(parents=True, exist_ok=True)
    job = uuid.uuid4().hex[:10]
    tmpl = str(out_dir / f"%(title)s [{job}].%(ext)s")

    postprocessors: list[dict] = []
    merge_fmt = "mp3" if audio_only else (container or "mp4")
    if audio_only:
        postprocessors.append({
            "key": "FFmpegExtractAudio",
            "preferredcodec": "mp3",
            "preferredquality": "192",
        })
    else:
        postprocessors.append({"key": "FFmpegMerger"})

    opts = _base_opts()
    opts.update({
        "format": build_format(quality, audio_only),
        "outtmpl": tmpl,
        "merge_output_format": merge_fmt,
        "postprocessors": postprocessors,
    })
    with yt_dlp.YoutubeDL(opts) as ydl:
        info = ydl.extract_info(url, download=True)
        filename = ydl.prepare_filename(info)
        # jika audio-only, ekstensi berubah jadi mp3
        if audio_only:
            cand = str(Path(filename).with_suffix(".mp3"))
            if os.path.isfile(cand):
                return cand
        if os.path.isfile(filename):
            return filename
        # fallback: cari file terbaru dengan job id
        matches = sorted(out_dir.glob(f"*[{job}]*"), key=lambda p: p.stat().st_mtime)
        if matches:
            return str(matches[-1])
        raise FileNotFoundError("hasil download tidak ditemukan")


async def get_info(url: str) -> dict:
    return await asyncio.to_thread(_sync_info, url)


def _sync_search_first(query: str) -> dict:
    opts = _base_opts()
    opts["skip_download"] = True
    with yt_dlp.YoutubeDL(opts) as ydl:
        result = ydl.extract_info(f"ytsearch1:{query}", download=False)
    entries = (result or {}).get("entries") or []
    return entries[0] if entries else {}


async def download_spotify_match(track: SpotifyTrack, container: str = "mp3") -> tuple[str, str, str]:
    """Cari padanan YouTube dari metadata Spotify lalu download audionya.

    Return (path, filename, matched_youtube_url). Selalu audio-only.
    """
    video = await asyncio.to_thread(_sync_search_first, search_query(track))
    if not video:
        raise ValueError("tidak ada padanan YouTube yang cocok")
    vid = video.get("id")
    yt_url = str(video.get("webpage_url") or (f"https://www.youtube.com/watch?v={vid}" if vid else ""))
    if not yt_url:
        raise ValueError("hasil search YouTube tidak valid")
    path = await asyncio.to_thread(_sync_download, yt_url, "audio", True, container)
    base = sanitize_filename(f"{track.artists} - {track.title}")
    return path, base + Path(path).suffix, yt_url


async def download_media(url: str, quality: str, audio_only: bool, container: str) -> tuple[str, str]:
    path = await asyncio.to_thread(_sync_download, url, quality, audio_only, container)
    title = Path(path).stem
    return path, sanitize_filename(title) + Path(path).suffix
