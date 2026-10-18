---
name: MORI MediaVault
description: Sistem visual aplikasi pengunduh media — dua dunia (Kaca Pagi terang & Kaca Malam gelap) dengan satu aksen biru-baja dan warna brand platform sebagai identifier.
colors:
  primary: "#2F6AA0"
  primary-deep: "#244F77"
  paper: "#F5F4F0"
  surface: "#FFFFFF"
  mist: "#EBEAE5"
  ink: "#202B36"
  slate: "#5B6B78"
  hairline: "#E3E1DA"
  brick: "#B04438"
  verdant: "#2E9E6B"
  accent-tint: "#E3EDF6"
  dark-paper: "#0F151C"
  dark-surface: "#1A2530"
  dark-mist: "#232F3B"
  dark-ink: "#E8EDF2"
  dark-slate: "#9FB2C2"
  dark-accent: "#7FB2D9"
  dark-accent-fill: "#4A79A8"
typography:
  display:
    fontFamily: "Geist"
    fontSize: "34px"
    fontWeight: 800
    lineHeight: 1
    letterSpacing: "+1.6px"
  title:
    fontFamily: "Geist"
    fontSize: "17px"
    fontWeight: 700
    lineHeight: 1.3
  body:
    fontFamily: "Geist"
    fontSize: "17px"
    fontWeight: 400
    lineHeight: 1.5
  label:
    fontFamily: "Geist"
    fontSize: "12px"
    fontWeight: 700
    lineHeight: 1.4
    letterSpacing: "+2px"
rounded:
  field: "14px"
  button: "14px"
  tile: "12px"
  card: "16px"
  nav-pill: "31px"
spacing:
  page: "20px"
  grid-gap: "12px"
components:
  button-primary:
    backgroundColor: "{colors.primary}"
    textColor: "#FFFFFF"
    rounded: "{rounded.button}"
    padding: "14px 24px"
  input-search:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.ink}"
    rounded: "{rounded.field}"
    padding: "12px 14px"
  nav-glass:
    backgroundColor: "scheme.navGlassTop → navGlassBottom"
    textColor: "{colors.slate}"
    rounded: "{rounded.nav-pill}"
  tile-platform:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.ink}"
    iconColor: "MoriBrand (per platform)"
    rounded: "{rounded.tile}"
    padding: "8px 16px"
---

# Design System: MORI MediaVault

## Overview

**Creative North Star: "Kaca Pagi" (light) & "Kaca Malam" (dark)**

Sebelumnya: kertas kebiruan #F2F5F9 dengan lima varian biru (#007AFF, #38BDF8, #0056B3, #0066CC, #2F6AA0) yang saling tumpang tindih, grays Tailwind default, dan copy App Store Apple — perilaku slop yang dibersihkan. Sekarang:

- **Kaca Pagi (light):** kertas hangat nyaris netral (#F5F4F0), permukaan putih, satu aksen **Steel Harbor Blue #2F6AA0** — lebih hangat, lebih dekat kertas tulis, bukan kertas biru. Sistem aksen 2-tone: aksen penuh untuk isi tombol/fokus, tint muda #E3EDF6 untuk fill seleksi.
- **Kaca Malam (dark):** navy hitam pekat (#0F151C), permukaan #1A2530, aksen interaktif dinaikkan terang (#7FB2D9) biar tetap terbaca, isi tombol #4A79A8 dengan teks putih 4.6:1. Bukan invert — scheme penuh sendiri (`MoriScheme.dark`), mengikuti setting OS (`ThemeMode.system`) karena ini aplikasi media: pengguna menonton di malam hari.
- **Warna brand platform** (TikTok, YouTube merah, Spotify hijau, IG magenta, dst.) hadir sebagai **identifier semantik** khusus ikon tile grid platform — sumber warna yang membuat UI hidup tanpa menyentuh sistem aksen.

**Key Characteristics:**
- Satu aksen berlapis: isi tombol aksen penuh, seleksi memakai tint muda, fokus border aksen penuh.
- Dua dunia tema penuh (light/dark) via `MoriScheme.light` / `MoriScheme.dark`; semua UI mengambil warna lewat `MoriScheme.of(context)`.
- Ikon tile platform memakai warna brand asli (per-brightness, didefinisikan di `MoriBrand`).
- Bahasa UI Indonesia konsisten: ANALISIS, UNDUH, TEMPEL, RIWAYAT, PENGATURAN, PRATINJAU, PLATFORM DIDUKUNG, MEMUTAR PRATINJAU.

## Colors

### Light — "Kaca Pagi"
- **Steel Harbor Blue** (#2F6AA0): aksi primer (`accentFill`), border fokus, ikon/radio terpilih. Putih di atasnya 5.8:1.
- **Harbor Deep** (#244F77): pressed state (mengganti #0056B3 yang lari hue).
- **Harbor Tint** (#E3EDF6): fill seleksi quality tile, container sukses, tab multi-link aktif.
- **Morning Paper** (#F5F4F0): ground seluruh layar — hangat, nyaris netral (mengganti kertas kebiruan #F2F5F9).
- **Glass White** (#FFFFFF): kartu, field, tile.
- **Mist Panel** (#EBEAE5): lapis netral kedua, track progress, badge, dropdown bg.
- **Deep Slate Ink** (#202B36): teks utama — 13:1 di atas kertas.
- **Harbor Slate** (#5B6B78): TUNGGAL keluarga abu teks: sekunder, hint, label seksi, ikon nonaktif, nomor lagu (mengganti duo #5A6E83/#6B7280). 5.0:1 di atas kertas, ≥4.5:1 di semua permukaan.
- **Faint** (#97A2AD): hanya disabled, chevron, timestamp tersier — bukan teks yang harus dibaca.
- **Hairline** (#E3E1DA): border kartu/field dan divider (mengganti #D1D5DB/#E2E8F0 Tailwind).
- **Brick Signal** (#B04438): error — teks, border Dismissible, bg snackbar error, tombol dialog destruktif.
- **Verdant Check** (#2E9E6B): check sukses dan ringkasan unduhan. Status semantik, bukan aksen.

### Dark — "Kaca Malam"
- **Ground** #0F151C · **Surface** #1A2530 · **Mist** #232F3B · **Hairline** #2A3642.
- **Teks:** ink #E8EDF2 (≈13:1), slate #9FB2C2, faint #67798B.
- **Aksen interaktif** #7FB2D9 (6.9:1 di atas surface) — ikon aktif, fokus, radio; **isi tombol** #4A79A8 + teks putih 4.6:1; **deep** #3B6690; **tint** #24384A untuk fill seleksi.
- **Status:** error #E07B66 (5.3:1), success #4FC08B (6.8:1).
- **Nav kaca malam:** glass #1A2530→#10161D, border putih 20%; pill #24303C→#1A2530, border putih 25%.

### Named Rules
**The One Accent Rule.** Steel Harbor Blue muncul di ≤10% layar: aksi primer, item terpilih, ring fokus, indikator unduhan. Biru yang bocor ke ikon informasi/panel statis adalah kegagalan (di versi lama: ikon settings, badge history, dropdown — semua sudah dinetralkan ke slate).

**The Brand Identifier Rule.** `MoriBrand` (16 platform, pasangan light/dark) hanya untuk ikon grid platform & thumbnail kosong. Dilarang untuk tombol, link, border, badge aktif, atau aksen apa pun — warna merek adalah identitas platform, bukan warna UI.

**The Theme Source Rule.** Satu-satunya sumber warna UI adalah `MoriScheme.of(context)` (light atau dark). Hardcode hex di widget adalah regresi — kecuali di [MoriVideoScene], yang sengaja konstan: dunia menonton selalu gelap dengan bar kontrol frosted putih (baik di tema terang maupun gelap), fullscreen murni hitam dengan aksen terang #7FB2D9.

## Typography

**Satu keluarga:** Geist.

### Hierarchy (dibangun)
- **Wordmark/Display** (800, 34px, tracking +1.6): "MORI", "RIWAYAT", "PENGATURAN", "PRATINJAU". Tracking positif — versi lama memakai −0.4 pada full-caps 34px (typo-sin, dihapus).
- **Title** (700, 17px, 1.3): judul media, nama item.
- **Body** (400, 17px, 1.5; field 16px).
- **Label** (700, 12px / 13px, tracking +2): penanda seksi & tombol.
- **Track label** (600, 14px, tracking −0.2); nav 10.5px medium/semibold tracking +0.4.

### Named Rules
**The One Family Rule.** Geist mengerjakan semuanya.

## Layout

Satu kolom dengan padding 20px; grid platform 2 kolom × gap 12px (tile tinggi ≥44px); home: judul → field link (50px, multi-line opsional) → tombol → label seksi → grid. Preview & settings memakai list vertikal dengan section header ber-tracking. Bar nav mengambang (kapsul 62px, margin bawah 14 / safe-area+6, lebar ≤400px).

## Elevation & Depth

Bayangan standar `MoriShadow` — semua tint ink (#202B36-based): product (0,6,16 @12%), card (0,2,10 @6%), button (0,4,12 @16%), nav (0,8-10,24-28). Di dunia gelap bayangan di-set transparan; kedalaman disampaikan lewat border hairline putih rendah, bukan bayangan hitam di atas hitam.

### Named Rules
**The Tinted Shadow Rule.** Tidak pernah glow berwarna. Bayangan capsule tab aktif yang dulu 0x18007AFF (halo biru) kini ikut tint ink.

## Shapes

Field/tombol 14px, tile 12px, card 16px, kapsul nav 31px, kontrol kecil 8px. Quality tile 12px (dulu pill 9999 yang tidak konsisten dengan skala tile); badge/baris progres tetap kapsul. Border 1px hairline; seleksi 1.5px aksen penuh.

## Components

### Buttons
- **Primary:** fill `accentFill` (theme-aware), teks putih, tinggi 50px, label caps tracking +2 w700/800, bayangan Button press saat enabled, hilang saat loading (spinner putih). Warna maintenance lewat `=filledButtonTheme`, bukan per-widget.
- **Destructive (dialog):** fill Brick Signal.
- **Cancel (mode batch):** outline error 1.2px.
- **Disabled:** Mist/no shadow.

### Chips / Badges
Badge metadata (provider, FALLBACK/DIRECT CDN, jumlah lagu, tipe file): pill netral — surface + border hairline + teks slate. Bukan aksen. "MEMUTAR PRATINJAU": pill `accentFill` — state aktif pemutar, satu-satunya aksen di preview audio.

### Cards / Containers
Cover `scheme.surface`, border 1px hairline, radius 12–16px, shadow Card/Resting. Container sukses unduh: `accentTint` + border hairline + check Verdant.

### Inputs / Fields
Fill surface, border hairline 14px, prefix & suffix ikon slate; fokus → border aksen 1.5px (tanpa glow, tanpa perubahan fill); bg snackbar informatif memakai inverseSurface (ink di light, terang di dark) — didefinisikan di theme.

### Navigation
Kapsul kaca mengambang: gradient glass per-scheme (`navGlassTop/Bottom/Border`), specular tipis di tepi atas, tab aktif dengan kapsul elastis (stretch ∝ sin) — warna ikon di-lerp slate→aksen mengikuti posisi animasi; drag antar-tab dengan haptic per tab. Tidak ada halo biru.

### Video Player (Kaca Malam tertanam)
`MoriVideoScene`: poster dim overlay 25% putih ikon; bar kontrol frosted #FFFFFF@88 + border ink 15%; played #2F6AA0 (tetap terbaca di kedua tema karena duduk di bar putih); buffered/track ink-alpha. Fullscreen: latar hitam, tombol keluar lingkaran putih frosted + ikon putih, progress played #7FB2D9.

## Do's and Don'ts

### Do:
- **Do** ambil warna dari `MoriScheme.of(context)` — tidak pernah hardcode.
- **Do** pakai Steel Harbor Blue hanya untuk aksi, seleksi, fokus, indikator unduhan.
- **Do** pakai `MoriBrand` hanya sebagai ikon platform.
- **Do** tint semua bayangan ke ink; di dark, biarkan border bekerja.
- **Do** jaga kontras ≥4.5:1 untuk semua teks yang harus dibaca (nilai per token tercantum di Colors).
- **Do** pastikan dunia video tetap dark/frosted Putih — di kedua tema.

### Don't:
- **Don't** menambahkan biru kedua (iOS Blue #007AFF, sky #38BDF8, dst. sudah dihapus — jangan kembali).
- **Don't** memakai warna Tailwind default (#6B7280, #E2E8F0, #D1D5DB) sebagai palet.
- **Don't** memakai gradien dekoratif, glow neon, atau halo berwarna.
- **Don't** memakai kaca/blur di luar navigation bar.
- **Don't** menulis copy bahasa Inggris di UI (placeholder, tombol, label) — UI Bahasa Indonesia.
- **Don't** membalik tema per-section; yang membedakan hanya MoriVideoScene.
