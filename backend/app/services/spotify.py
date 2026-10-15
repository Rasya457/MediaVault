"""Spotify track metadata via API (MVP: track saja, audio dicocokkan dari YouTube)."""
from dataclasses import dataclass
from urllib.parse import urlparse

import spotipy
from spotipy.oauth2 import SpotifyClientCredentials

from app.config import settings


class SpotifyConfigError(RuntimeError):
    """Kredensial Spotify belum di-set."""


class SpotifyUnsupportedError(ValueError):
    """Tipe URL Spotify di luar scope MVP."""


@dataclass
class SpotifyTrack:
    id: str
    title: str
    artists: str
    album: str
    cover: str | None
    duration_sec: int | None
    spotify_url: str


def is_spotify_url(url: str) -> bool:
    try:
        return (urlparse(url).hostname or "").lower() == "open.spotify.com"
    except Exception:
        return False


def _client() -> spotipy.Spotify:
    if not settings.SPOTIFY_CLIENT_ID or not settings.SPOTIFY_CLIENT_SECRET:
        raise SpotifyConfigError("SPOTIFY_CLIENT_ID/SECRET belum di-set di .env")
    auth = SpotifyClientCredentials(
        client_id=settings.SPOTIFY_CLIENT_ID,
        client_secret=settings.SPOTIFY_CLIENT_SECRET,
    )
    return spotipy.Spotify(auth_manager=auth)


def parse_track_id(url: str) -> str:
    """Ambil track id; tolak album/playlist/episode/show/artist (di luar MVP)."""
    parts = urlparse(url).path.strip("/").split("/")
    if len(parts) >= 2 and parts[-2] == "track" and parts[-1]:
        return parts[-1]
    if parts and parts[0] in {"album", "playlist", "episode", "show", "artist"}:
        raise SpotifyUnsupportedError(f"MVP hanya dukung Spotify track, bukan {parts[0]}")
    raise SpotifyUnsupportedError("URL Spotify tidak dikenali sebagai track")


def get_track(url: str) -> SpotifyTrack:
    track_id = parse_track_id(url)
    data = _client().track(track_id)
    artists = ", ".join(a.get("name", "") for a in data.get("artists", []))
    album = data.get("album", {}) or {}
    images = album.get("images", []) or []
    duration_ms = data.get("duration_ms") or 0
    return SpotifyTrack(
        id=track_id,
        title=str(data.get("name") or "Tanpa judul"),
        artists=artists or "Unknown",
        album=str(album.get("name", "")),
        cover=images[0].get("url") if images else None,
        duration_sec=(duration_ms // 1000) if duration_ms else None,
        spotify_url=f"https://open.spotify.com/track/{track_id}",
    )


def search_query(track: SpotifyTrack) -> str:
    return f"{track.artists} - {track.title}"
