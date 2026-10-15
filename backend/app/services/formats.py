"""Mapping kualitas sederhana -> format string yt-dlp."""

QUALITY_HEIGHTS = {
    "360p": 360,
    "480p": 480,
    "720p": 720,
    "1080p": 1080,
    "1440p": 1440,
    "2160p": 2160,
    "best": 0,
    "audio": 0,
}


def build_format(quality: str = "best", audio_only: bool = False) -> str:
    if audio_only or quality == "audio":
        return "bestaudio/best"
    h = QUALITY_HEIGHTS.get(quality, 0)
    if h <= 0:
        return "bestvideo+bestaudio/best"
    return f"bestvideo[height<={h}]+bestaudio/best[height<={h}]/best"


def simplify_formats(raw_formats: list[dict]) -> list[dict]:
    """Kelompokkan ke opsi hemat: audio + 360/720/1080/best."""
    buckets: dict[str, dict] = {}
    for f in raw_formats or []:
        fid = str(f.get("format_id", ""))
        ext = str(f.get("ext", "mp4"))
        vcodec = f.get("vcodec")
        height = f.get("height") or 0
        filesize = f.get("filesize") or f.get("filesize_approx")
        fps = f.get("fps")
        is_audio = vcodec in (None, "none")
        if is_audio:
            key = "audio"
            label = "Audio"
        elif height and height <= 360:
            key, label = "360p", "360p"
        elif height and height <= 720:
            key, label = "720p", "720p"
        elif height and height <= 1080:
            key, label = "1080p", "1080p"
        else:
            key, label = "best", "Best"
        prev = buckets.get(key)
        # pilih filesize terbesar sebagai representasi bucket
        if prev is None or (filesize or 0) > (prev.get("filesize") or 0):
            buckets[key] = {
                "format_id": fid,
                "quality_label": label,
                "ext": ext,
                "filesize": filesize,
                "is_audio": is_audio,
                "fps": fps,
            }
    order = ["audio", "360p", "720p", "1080p", "best"]
    return [buckets[k] for k in order if k in buckets]
