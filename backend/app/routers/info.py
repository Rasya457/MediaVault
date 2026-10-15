import asyncio

from fastapi import APIRouter, Depends, HTTPException

from app.deps import verify_api_key
from app.schemas.models import FormatOption, InfoRequest, InfoResponse
from app.services.extractor import get_info
from app.services.formats import simplify_formats
from app.services.spotify import (
    SpotifyConfigError,
    SpotifyUnsupportedError,
    get_track,
    is_spotify_url,
)
from app.utils.url_validator import validate_url_or_raise

router = APIRouter()


async def _spotify_info(url: str) -> InfoResponse:
    try:
        track = await asyncio.to_thread(get_track, url)
    except SpotifyConfigError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    except SpotifyUnsupportedError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except Exception as exc:
        raise HTTPException(status_code=422, detail=f"Gagal ambil info Spotify: {exc}") from exc
    return InfoResponse(
        title=f"{track.artists} - {track.title}",
        uploader=track.artists,
        duration=track.duration_sec,
        thumbnail=track.cover,
        webpage_url=track.spotify_url,
        formats=[
            FormatOption(
                format_id="spotify-audio",
                quality_label="Audio (dicocokkan dari YouTube)",
                ext="mp3",
                is_audio=True,
            )
        ],
    )


@router.post("/info", response_model=InfoResponse)
async def fetch_info(payload: InfoRequest, _auth: None = Depends(verify_api_key)) -> InfoResponse:
    url = validate_url_or_raise(payload.url)
    if is_spotify_url(url):
        return await _spotify_info(url)
    try:
        data = await get_info(url)
    except Exception as exc:
        raise HTTPException(status_code=422, detail=f"Gagal ambil info: {exc}") from exc
    return InfoResponse(
        title=str(data.get("title") or "Tanpa judul"),
        uploader=data.get("uploader") or data.get("channel"),
        duration=data.get("duration"),
        thumbnail=data.get("thumbnail"),
        webpage_url=str(data.get("webpage_url") or url),
        formats=[FormatOption(**f) for f in simplify_formats(data.get("formats") or [])],
    )
