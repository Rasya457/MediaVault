from pydantic import BaseModel, Field


class HealthResponse(BaseModel):
    status: str = "ok"
    version: str = "0.1.0"


class InfoRequest(BaseModel):
    url: str = Field(min_length=8, max_length=2048)


class FormatOption(BaseModel):
    format_id: str
    quality_label: str
    ext: str
    filesize: int | None = None
    is_audio: bool = False
    fps: float | None = None


class InfoResponse(BaseModel):
    title: str
    uploader: str | None = None
    duration: int | None = None
    thumbnail: str | None = None
    webpage_url: str
    formats: list[FormatOption]


class DownloadRequest(BaseModel):
    url: str = Field(min_length=8, max_length=2048)
    quality: str = Field(default="best", max_length=16)
    audio_only: bool = False
    container: str = Field(default="mp4", max_length=8)
