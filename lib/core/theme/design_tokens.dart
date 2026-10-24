// Design tokens MORI — "Kaca Pagi" (light) & "Kaca Malam" (dark).
// Follow DESIGN.md: one harbor-blue accent family (#2F6AA0) reserved for
// actions/focus/selection; platform brand colors are semantic identifiers
// on tile icons only. All other colors neutral (warm paper / dark harbor).

import 'package:flutter/material.dart';

/// Palet lengkap satu tema. Ambil instance via [MoriScheme.of] supaya
/// widget otomatis mengikuti light/dark dari MaterialApp theme.
class MoriScheme {
  const MoriScheme({
    required this.brightness,
    required this.background,
    required this.surface,
    required this.surfaceVariant,
    required this.ink,
    required this.secondary,
    required this.faint,
    required this.hairline,
    required this.accent,
    required this.accentFill,
    required this.accentDeep,
    required this.accentTint,
    required this.onAccent,
    required this.error,
    required this.success,
    required this.navGlassTop,
    required this.navGlassBottom,
    required this.navGlassBorder,
    required this.navPillTop,
    required this.navPillBottom,
    required this.navPillBorder,
    required this.inverseSurface,
    required this.onInverseSurface,
  });

  final Brightness brightness;
  final Color background;
  final Color surface;
  final Color surfaceVariant;

  /// Teks utama.
  final Color ink;

  /// Teks sekunder: hint, subtitle, label seksi, ikon non-aktif.
  final Color secondary;

  /// Paling redup: ikon disabled, chevron, teks waktu tersier.
  final Color faint;

  /// Border kartu/field dan divider.
  final Color hairline;

  /// Aksen interaktif untuk foreground: ikon aksi, radio/fokus, link.
  final Color accent;

  /// Aksen untuk isi tombol primer dan switch.
  final Color accentFill;

  /// Varian tekan aksen.
  final Color accentDeep;

  /// Fill seleksi tipis (quality tile, preview sukses, tab aktif tombol).
  final Color accentTint;

  /// Teks di atas [accentFill].
  final Color onAccent;

  final Color error;
  final Color success;

  // --- Kaca navigation bar (satu-satunya permukaan kaca di sistem) ---
  final Color navGlassTop;
  final Color navGlassBottom;
  final Color navGlassBorder;
  final Color navPillTop;
  final Color navPillBottom;
  final Color navPillBorder;

  /// Inverse (snackbar): light → pill ink, dark → pill terang.
  final Color inverseSurface;
  final Color onInverseSurface;

  static MoriScheme of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;

  static const light = MoriScheme(
    brightness: Brightness.light,
    background: Color(0xFFF5F4F0),   // Morri paper — hangat, nyaris netral
    surface: Color(0xFFFFFFFF),
    surfaceVariant: Color(0xFFEBEAE5),
    ink: Color(0xFF202B36),          // Deep Slate Ink
    secondary: Color(0xFF5B6B78),    // Harbor Slate
    faint: Color(0xFF97A2AD),
    hairline: Color(0xFFE3E1DA),
    accent: Color(0xFF2F6AA0),       // Steel Harbor Blue
    accentFill: Color(0xFF2F6AA0),
    accentDeep: Color(0xFF244F77),   // Harbor Deep
    accentTint: Color(0xFFE3EDF6),   // Harbor Tint
    onAccent: Color(0xFFFFFFFF),
    error: Color(0xFFB04438),        // Brick Signal
    success: Color(0xFF2E9E6B),      // Verdant Check
    navGlassTop: Color(0xCCFFFFFF),
    navGlassBottom: Color(0xAAF5F4F0),   // neutral warm glass (no blue tint)
    navGlassBorder: Color(0xE0FFFFFF),
    navPillTop: Color(0xD5FFFFFF),
    navPillBottom: Color(0x80FFFFFF),
    navPillBorder: Color(0xEEFFFFFF),
    inverseSurface: Color(0xFF1C1C1E),
    onInverseSurface: Color(0xFFFFFFFF),
  );

  static const dark = MoriScheme(
    brightness: Brightness.dark,
    background: Color(0xFF0F151C),
    surface: Color(0xFF1A2530),
    surfaceVariant: Color(0xFF232F3B),
    ink: Color(0xFFE8EDF2),
    secondary: Color(0xFF9FB2C2),
    faint: Color(0xFF67798B),
    hairline: Color(0xFF2A3642),
    // Aksen dinaikkan terang di dunia gelap; tombol tetap isi medium agar
    // teks putih tetap >=4.5:1.
    accent: Color(0xFF7FB2D9),
    accentFill: Color(0xFF4A79A8),
    accentDeep: Color(0xFF3B6690),
    accentTint: Color(0xFF24384A),
    onAccent: Color(0xFFFFFFFF),
    error: Color(0xFFE07B66),
    success: Color(0xFF4FC08B),
    navGlassTop: Color(0xD91A2530),
    navGlassBottom: Color(0x99101620),
    navGlassBorder: Color(0x33FFFFFF),
    navPillTop: Color(0xFF24303C),
    navPillBottom: Color(0xCC1A2530),
    navPillBorder: Color(0x40FFFFFF),
    inverseSurface: Color(0xFFE8EDF2),
    onInverseSurface: Color(0xFF0F151C),
  );
}

/// Warna ikon brand per platform — identifier semantik, BUKAN aksen UI.
/// Dipakai hanya pada ikon tile platform & thumbnail kosong; dilarang untuk
/// tombol, link, border, atau elemen aksi lainnya (One Accent Rule).
abstract class MoriBrand {
  static const tiktok = Color(0xFF161823);
  static const tiktokDark = Color(0xFFF5F5F5);
  static const instagram = Color(0xFFE1306C);
  static const instagramDark = Color(0xFFFF6F9F);
  static const youtube = Color(0xFFFF0033);
  static const spotify = Color(0xFF1DB954);
  static const spotifyDark = Color(0xFF1ED760);
  static const x = Color(0xFF1D2430);
  static const xDark = Color(0xFFEDF1F5);
  static const bilibili = Color(0xFFFB7299);
  static const douyin = Color(0xFF161823);
  static const douyinDark = Color(0xFFF5F5F5);
  static const rednote = Color(0xFFFF2442);
  static const rednoteDark = Color(0xFFFF566E);
  static const threads = Color(0xFF14161A);
  static const threadsDark = Color(0xFFEDF1F5);
  static const pinterest = Color(0xFFE60023);
  static const pinterestDark = Color(0xFFFF3348);
  static const appleMusic = Color(0xFFFA243C);
  static const appleMusicDark = Color(0xFFFA4D60);
  static const facebook = Color(0xFF1877F2);
  static const facebookDark = Color(0xFF4C9AFF);
  static const bandcamp = Color(0xFF1DA0C3);
  static const bandcampDark = Color(0xFF33BEE2);
  static const pixiv = Color(0xFF0096FA);
  static const pixivDark = Color(0xFF47AEFF);
  static const reddit = Color(0xFFFF4500);
  static const redditDark = Color(0xFFFF6B33);
  static const terabox = Color(0xFF2F61F5);
  static const teraboxDark = Color(0xFF7C9BFF);
}

/// Konstanta adegan video (player di atas konten). Sengaja TIDAK mengikuti
/// tema — dunia menonton selalu gelap dengan kontrol frosted putih
/// (DESIGN.md: "permukaan video tetap gelap").
abstract class MoriVideoScene {
  /// Bar kontrol frosted di atas video.
  static const barFill = Color(0xE0FFFFFF);

  /// Border bar di atas isi putih.
  static const barBorder = Color(0x26202B36);

  /// Warna progress pada bar putih: aksen light (tetap terbaca di kedua tema).
  static const played = Color(0xFF007AFF);
  static const buffered = Color(0x59202B36);
  static const track = Color(0x1F202B36);

  /// Fullscreen player: dunia hitam murni.
  static const fullscreenFill = Color(0x99FFFFFF);
  static const fullscreenBorder = Color(0x4DFFFFFF);
  static const fullscreenIcon = Color(0xFFF7F9FB);
  static const fullscreenPlayed = Color(0xFF7FB2D9);
  static const fullscreenBuffered = Color(0x66FFFFFF);
  static const fullscreenTrack = Color(0x33FFFFFF);
}

abstract class MoriRadius {
  /// Field & tombol 14px (DESIGN.md).
  static const double field = 14.0;
  static const double button = 14.0;

  /// Tile 12px.
  static const double tile = 12.0;

  /// Card 16px.
  static const double card = 16.0;

  /// Kapsul (badge/nav).
  static const double pill = 9999.0;

  /// Kontrol kecil.
  static const double small = 8.0;
}

abstract class MoriSpacing {
  static const double pagePad = 20.0;
  static const double titleTop = 28.0;
  static const double afterTitle = 24.0;
  static const double afterField = 14.0;
  static const double afterBtn = 28.0;
  static const double afterLabel = 14.0;
  static const double gridGap = 12.0;

  /// Tinggi minimum tile: 44.
  static const double tileHeight = 44.0;
}

abstract class MoriText {
  static const double titleSize = 34.0;
  static const double labelSize = 12.0;
  static const double fieldSize = 16.0;
  static const double btnSize = 16.0;
  static const double tileSize = 14.0;

  /// Wordmark/section display: tracking positif seperti DESIGN.md display.
  static const double titleLetterSpacing = 1.6;
  static const double labelLetterSpacing = 2.0;
  static const double btnLetterSpacing = 2.0;
  static const double tileLetterSpacing = -0.2;
  static const double navLetterSpacing = 0.4;

  static const double navLabelSize = 10.5;
}

abstract class MoriBorder {
  static const double field = 1.0;
  static const double tile = 1.0;
  static const double fab = 1.0;
  static const double nav = 1.0;

  /// Seleksi (quality tile): aksen penuh 1.5px.
  static const double selected = 1.5;
}

abstract class MoriShadow {
  /// Bayangan semua tint ink (Tinted Shadow Rule); glow berwarna dilarang.
  static const product = <BoxShadow>[
    BoxShadow(
      color: Color(0x1F202B36),
      blurRadius: 16,
      offset: Offset(0, 6),
    ),
  ];

  static const card = <BoxShadow>[
    BoxShadow(
      color: Color(0x0F202B36),
      blurRadius: 10,
      offset: Offset(0, 2),
    ),
  ];

  static const soft = card;

  static const nav = <BoxShadow>[
    BoxShadow(
      color: Color(0x1F202B36),
      blurRadius: 24,
      offset: Offset(0, 8),
    ),
  ];

  static const button = <BoxShadow>[
    BoxShadow(
      color: Color(0x29202B36),
      blurRadius: 12,
      offset: Offset(0, 4),
    ),
  ];
}
