from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.config import settings
from app.routers import download, health, info


def create_app() -> FastAPI:
    app = FastAPI(title=settings.app_name, version=settings.app_version)
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.CORS_ORIGINS,
        allow_credentials=False,
        allow_methods=["GET", "POST", "OPTIONS"],
        allow_headers=["*"],
    )
    app.include_router(health.router, tags=["system"])
    app.include_router(info.router, tags=["media"])
    app.include_router(download.router, tags=["media"])

    Path(settings.DOWNLOAD_DIR).mkdir(parents=True, exist_ok=True)
    Path(settings.TMP_DIR).mkdir(parents=True, exist_ok=True)
    Path(settings.COOKIE_FILE).parent.mkdir(parents=True, exist_ok=True)
    return app


app = create_app()
