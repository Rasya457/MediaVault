# Product

<!-- impeccable:product-schema 1 -->

## Platform

adaptive

## Users

Pengguna umum Indonesia yang menyimpan video, foto, dan lagu dari media sosial ke perangkat untuk dipakai offline. Tidak diasumsikan paham teknis — alur harus tempel-link-langsung-jadi.

## Product Purpose

MediaVault (MORI) mengunduh media dari TikTok, Instagram, YouTube, dan Spotify (platform inti) serta platform tambahan via UniversalEngine ke perangkat pengguna. Alur inti: tempel atau bagikan link → pratinjau hasil → pilih kualitas → tersimpan ke galeri. Sukses berarti file benar-benar ada di galeri dan bisa dibuka, tanpa akun.

## Positioning

Privasi on-device untuk platform inti: tanpa akun, tanpa analytics, tanpa hosting media perantara. Semua resolve dan unduh TikTok/Instagram/YouTube/Spotify berjalan langsung di perangkat, tidak seperti downloader yang memproses lewat server sendiri. Platform tambahan di-resolve melalui instance publik Cobalt (pihak ketiga) — dikomunikasikan apa adanya, tidak diperjuangkan sebagai posisi privasi penuh.

## Operating Context

- Bahasa UI Indonesia; pesan error berbahasa Indonesia yang bisa ditindak (bukan kode mentah).
- Entri link via tempel manual, deteksi clipboard, dan Android share-intent dari aplikasi lain.
- Konfigurasi endpoint scraper via `lib/services/providers/endpoints.json` (bundled, cache 1 jam).
- Pola scraper mengikuti referensi open-source coflyn/Mori (Capacitor/Tauri) yang ditulis ulang dalam Dart.
- Platform tambahan di-handle UniversalEngine dengan daftar instance Cobalt publik yang fallback berurutan (`cobalt.api.scav.top` → `api.cobalt.tools` → `cobalt-api.kwiatekm.tokyo`).
- Tidak ada base URL backend di client — setiap provider mengatur URL-nya sendiri (`lib/core/network/api_client.dart`).
- Video adaptif YouTube (video-only + audio-only) digabung on-device via FFmpeg sebelum masuk galeri.
- Penyimpanan foto/video ke galeri sistem via plugin gal; audio ke folder aplikasi.

## Capabilities and Constraints

- Platform sumber inti: TikTok, Instagram, YouTube, Spotify (single track; playlist/album Spotify diunduh via antrian batch per track, dibatasi 20 track).
- Platform sumber tambahan (terkonfirmasi shipped, via UniversalEngine/Cobalt): Twitter/X, Threads, Facebook, Reddit, Pinterest, Bilibili, Douyin, Xiaohongshu/RedNote, Bandcamp, Terabox — video/foto dan Audio MP3 sesuai link.
- @MORI backend: layanan FastAPI di `backend/` (router info/download/health, auth API key, dukungan cookie, pencocokan Spotify→YouTube, batas unduh semaphore, auto-cleanup file) bagian dari produk. Saat ini client Flutter belum memanggil backend ini; resolve tetap on-device untuk platform inti.
- Riwayat unduhan tersimpan lokal (shared_preferences, dengan thumbnail playlist/album) dan tampil di halaman History — sudah terkonfirmasi dalam kode.
- Unduhan paralel playlist/album berjalan pada 5 worker aktif (fixed di kode, belum ada setelan pengguna).
- Rantai fallback per platform: Innertube direct → konversi third-party untuk YouTube; InDown → SnapSave untuk Instagram; SoundLoaders → SpotiDown untuk Spotify.
- Format `.webm`/`.mkv` tidak bisa masuk galeri Android — pengguna diarahkan memilih MP4.
- Kualitas Instagram mengikuti file asli CDN (satu file per item carousel), bukan opsi resolusi.
- Belum diputuskan: kunci PIN/biometrik di aplikasi.

## Brand Commitments

Nama MORI / MediaVault. Klaim "tanpa watermark, tanpa akun, tanpa pelacakan" mengikuti posisi privasi di atas.

## Evidence on Hand

- Suite test otomatis di `test/` (provider TikTok/Instagram/YouTube/Spotify, download controller, batch download controller, preview page); belum ada test khusus UniversalEngine atau history repository.
- Verifikasi E2E provider tercatat sebagai komentar di tiap file provider — perlakukan sebagai klaim berkala, bukan jaminan hidup.
- Tidak ada testimoni pengguna, data pelanggan, atau aset pemasaran — jangan fabrikasi.

## Product Principles

1. Privasi bukan fitur, melainkan arsitektur: tanpa akun, tanpa analytics, media tidak melewati server sendiri — resolve platform inti berjalan on-device; platform tambahan hanya melewati engine Cobalt yang diketahui.
2. Tiga ketukan selesai: dari link ke file tersimpan tanpa keputusan yang tidak perlu.
3. Jujur saat gagal: katakan sisi mana yang rusak dan apa yang bisa dicoba, dalam Bahasa Indonesia.
4. Tahan endpoint mati: setiap sumber punya cadangan, dan kegagalan cadangan tidak menutupi error asli.
