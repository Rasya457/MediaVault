from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    app_name: str = "MediaVault API"
    app_version: str = "0.1.0"

    # Kosong = tanpa auth (mode terbuka). Isi untuk wajibkan x-api-key.
    API_KEY: str = ""
    MAX_CONCURRENT: int = 3

    DOWNLOAD_DIR: str = "./downloads"
    TMP_DIR: str = "./tmp"
    COOKIE_FILE: str = "./cookies/cookies.txt"

    CLEANUP_AFTER_SEC: int = 3600

    # Spotify API (https://developer.spotify.com/dashboard). Kosong = fitur Spotify mati.
    SPOTIFY_CLIENT_ID: str = ""
    SPOTIFY_CLIENT_SECRET: str = ""

    CORS_ORIGINS: list[str] = ["*"]


settings = Settings()
