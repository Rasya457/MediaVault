# MediaVault

Flutter media downloader (video/audio/foto) multi-platform. Tanpa server,
tanpa VPS, tanpa biaya hosting — ekstraksi jalan on-device via provider
pihak ketiga + remote config OTA.

## Keputusan arsitektur (final)

- **Opsi A: tanpa VPS.** Semua ekstraksi di HP. Folder `backend/` TIDAK dipakai
  produksi — disimpan hanya sebagai opsi self-host.
- **Pola provider-fallback** (terinspirasi pola Mori, clean-room, BUKAN copy code —
  Mori & Nimiyo berlisensi GPL-3.0): tiap platform punya 2 provider
  (primary + fallback). URL endpoint dibaca dari remote config, bisa diganti
  tanpa update APK.
- **MVP platform:** TikTok, Instagram, YouTube, Spotify (track saja, audio hasil
  match — UI wajib jujur soal sumber). Apple Music: dicoret (DRM).
- **UI/desain:** BELUM fix. File widget tetap stub sampai warna & desain ditentukan.
  Yang boleh diisi: data layer saja.

## Struktur

```
backend/                      # FastAPI + yt-dlp (ARSIP/opsi self-host, bukan produksi)
  app/main.py                 # entry, register router
  app/config.py               # env (API_KEY, SPOTIFY_*, dll)
  app/routers/                # health.py, info.py, download.py
  app/services/               # extractor.py, formats.py, cleanup.py, spotify.py
  app/schemas/models.py       # pydantic request/response
  app/utils/                  # url_validator.py (whitelist+SSRF), filename.py
  tests/                      # test_url_validator.py, test_spotify.py (12 passed)
  Dockerfile, requirements.txt, .env.example

lib/                          # Flutter (jalur produksi)
  main.dart                   # bootstrap (template, edit minimal)
  app.dart                    # STUB — MaterialApp/tema/routing (tunggu desain)
  core/constants/app_config.dart   # remoteConfigUrl, timeout (tanpa warna/teks UI)
  core/network/api_client.dart     # Dio: timeout 15s/60s, UA browser, retry 1x
  core/theme/app_theme.dart        # STUB — jangan isi
  core/utils/                 # url_helper, format_helper (stub)
  features/{home,preview,history}/  # widget STUB + service stub
  features/download/  # DONE: service+controller+E2E device (widget masih stub)
  services/share_intent_service.dart  # DONE: Share teks/URL Android+E2E adb
  services/providers/         # >>> LAYER UTAMA (lihat Pola provider) <<<
    provider.dart             # abstract MediaProvider + ProviderException
    models.dart               # MediaInfo (source: direct|third-party)
    registry.dart             # fallback chain per platform
    remote_config.dart + endpoints.json  # OTA URL endpoint
    tiktok/instagram/youtube/spotify_provider.dart  # pair primary+fallback
```

## Pola provider (wajib dipatuhi)

1. Satu file per platform, 2 class provider per file (primary + fallback).
2. JANGAN hardcode URL endpoint di class — wajib via remote config.
3. Tiap file provider wajib komentar: endpoint dipakai + tanggal verifikasi hidup.
4. Error dibungkus ProviderException (link salah | provider down | tanpa hasil).
5. DILARANG copy code dari repo GPL (Mori/Nimiyo/scrapr). Daftar endpoint/fakta
   boleh ditiru, implementasi tulis ulang.

## Perintah

Backend (opsional, hanya self-host):

```
C:\Users\Rasya\AppData\Local\Python\pythoncore-3.14-64\python.exe -m pip install -r backend/requirements.txt
(cd backend/) ... -m uvicorn app.main:app --host 127.0.0.1 --port 8000
... -m pytest tests/ -q
```

JANGAN pakai bare `python` (nyasar ke venv Hermes tanpa deps).

Flutter:

```
flutter pub get | flutter analyze | flutter test
```

## Referensi (ide saja, bukan dependensi)

- https://github.com/nimidz/Nimiyo-Downloader — acuan fitur & alur UX
- https://github.com/coflyn/Mori — acuan pola provider-fallback + OTA hot-patch
- https://github.com/yt-dlp/yt-dlp — dipakai hanya oleh backend (arsip)
