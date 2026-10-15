import asyncio

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException
from fastapi.responses import FileResponse

from app.config import settings
from app.deps import _semaphore, verify_api_key
from app.schemas.models import DownloadRequest
from app.services.cleanup import remove_file_safe
from app.services.extractor import download_media, download_spotify_match
from app.services.spotify import (
    SpotifyConfigError,
    SpotifyUnsupportedError,
    get_track,
    is_spotify_url,
)
from app.utils.url_validator import validate_url_or_raise

router = APIRouter()


@router.post("/download")
async def download(payload: DownloadRequest, bg: BackgroundTasks, _auth: None = Depends(verify_api_key)):
    url = validate_url_or_raise(payload.url)
    async with _semaphore:
        try:
            if is_spotify_url(url):
                track = await asyncio.to_thread(get_track, url)
                path, filename, _matched = await download_spotify_match(track)
            else:
                path, filename = await download_media(url, payload.quality, payload.audio_only, payload.container)
        except SpotifyConfigError as exc:
            raise HTTPException(status_code=503, detail=str(exc)) from exc
        except SpotifyUnsupportedError as exc:
            raise HTTPException(status_code=400, detail=str(exc)) from exc
        except HTTPException:
            raise
        except Exception as exc:
            raise HTTPException(status_code=422, detail=f"Gagal download: {exc}") from exc
    # opsional: hapus setelah terkirim agar disk tidak penuh
    if settings.CLEANUP_AFTER_SEC <= 0:
        bg.add_task(remove_file_safe, path)
    return FileResponse(path, filename=filename, media_type="application/octet-stream")
