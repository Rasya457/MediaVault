"""Whitelist host + cegah SSRF."""
import ipaddress
from urllib.parse import urlparse

from fastapi import HTTPException

ALLOWED_HOSTS: set[str] = {
    "youtube.com",
    "www.youtube.com",
    "m.youtube.com",
    "music.youtube.com",
    "youtu.be",
    "tiktok.com",
    "www.tiktok.com",
    "vm.tiktok.com",
    "vt.tiktok.com",
    "instagram.com",
    "www.instagram.com",
    "facebook.com",
    "www.facebook.com",
    "fb.watch",
    "twitter.com",
    "www.twitter.com",
    "x.com",
    "vimeo.com",
    "www.vimeo.com",
    "dailymotion.com",
    "www.dailymotion.com",
    "twitch.tv",
    "www.twitch.tv",
    "soundcloud.com",
    "www.soundcloud.com",
    "open.spotify.com",
}


def _is_ip_literal(host: str) -> bool:
    try:
        ipaddress.ip_address(host.strip("[]"))
        return True
    except ValueError:
        return False


def _is_private_host(host: str) -> bool:
    h = host.lower().strip("[]")
    if h in {"localhost"} or h.endswith(".local"):
        return True
    try:
        return ipaddress.ip_address(h).is_private or ipaddress.ip_address(h).is_loopback
    except ValueError:
        return False


def is_allowed_url(url: str) -> bool:
    try:
        p = urlparse(url.strip())
    except Exception:
        return False
    if p.scheme not in ("http", "https"):
        return False
    if p.username or p.password:
        return False
    host = (p.hostname or "").lower()
    if not host:
        return False
    if _is_ip_literal(host) or _is_private_host(host):
        return False
    if p.port not in (None, 80, 443):
        return False
    # exact match atau subdomain dari whitelist
    if host in ALLOWED_HOSTS:
        return True
    return any(host.endswith("." + base) for base in ALLOWED_HOSTS)


def validate_url_or_raise(url: str) -> str:
    clean = (url or "").strip()
    if len(clean) < 8 or len(clean) > 2048:
        raise HTTPException(status_code=400, detail="URL tidak valid")
    if not is_allowed_url(clean):
        raise HTTPException(status_code=400, detail="Host tidak diizinkan / potensi SSRF")
    return clean
