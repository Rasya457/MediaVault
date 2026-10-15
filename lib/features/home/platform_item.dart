import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

/// Satu platform yang didukung MORI.
class PlatformItem {
  const PlatformItem({
    required this.id,
    required this.label,
    required this.iconBuilder,
    required this.domains,
  });

  final String id;
  final String label;

  /// Builder ikon: (color) -> Widget, mendukung FaIcon dan SVG.
  final Widget Function(Color color) iconBuilder;

  final List<String> domains;
}

/// Helper: FaIcon dari FaIconData.
Widget _fa(FaIconData icon, Color color) =>
    FaIcon(icon, color: color, size: 24);

/// Helper: SVG asset.
Widget _svg(String asset, Color color) => SvgPicture.asset(
      asset,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      width: 24,
      height: 24,
    );

/// Daftar 16 platform lengkap — urutan persis sesuai screenshot:
/// TikTok, Instagram, YouTube, Twitter, Spotify, Bilibili, Douyin, RedNote,
/// Threads, Pinterest, Apple Music, Facebook, Bandcamp, Pixiv, Reddit, Terabox.
final List<PlatformItem> kPlatforms = [
  PlatformItem(
    id: 'tiktok',
    label: 'TIKTOK',
    iconBuilder: (c) => _fa(FontAwesomeIcons.tiktok, c),
    domains: const ['tiktok.com', 'vt.tiktok.com'],
  ),
  PlatformItem(
    id: 'instagram',
    label: 'INSTAGRAM',
    iconBuilder: (c) => _fa(FontAwesomeIcons.instagram, c),
    domains: const ['instagram.com', 'instagr.am'],
  ),
  PlatformItem(
    id: 'youtube',
    label: 'YOUTUBE',
    iconBuilder: (c) => _fa(FontAwesomeIcons.youtube, c),
    domains: const ['youtube.com', 'youtu.be', 'm.youtube.com'],
  ),
  PlatformItem(
    id: 'twitter',
    label: 'TWITTER',
    iconBuilder: (c) => _fa(FontAwesomeIcons.xTwitter, c),
    domains: const ['twitter.com', 'x.com', 't.co'],
  ),
  PlatformItem(
    id: 'spotify',
    label: 'SPOTIFY',
    iconBuilder: (c) => _fa(FontAwesomeIcons.spotify, c),
    domains: const ['open.spotify.com', 'spotify.com'],
  ),
  PlatformItem(
    id: 'bilibili',
    label: 'BILIBILI',
    iconBuilder: (c) => _fa(FontAwesomeIcons.bilibili, c),
    domains: const ['bilibili.com', 'b23.tv'],
  ),
  PlatformItem(
    id: 'douyin',
    label: 'DOUYIN',
    iconBuilder: (c) => _fa(FontAwesomeIcons.tiktok, c), // Douyin memakai ikon TikTok
    domains: const ['douyin.com', 'iesdouyin.com'],
  ),
  PlatformItem(
    id: 'rednote',
    label: 'REDNOTE',
    iconBuilder: (c) => _svg('assets/icons/rednote.svg', c),
    domains: const ['xiaohongshu.com', 'xhslink.com'],
  ),
  PlatformItem(
    id: 'threads',
    label: 'THREADS',
    iconBuilder: (c) => _fa(FontAwesomeIcons.threads, c),
    domains: const ['threads.net'],
  ),
  PlatformItem(
    id: 'pinterest',
    label: 'PINTEREST',
    iconBuilder: (c) => _fa(FontAwesomeIcons.pinterest, c),
    domains: const ['pinterest.com', 'pin.it'],
  ),
  PlatformItem(
    id: 'applemusic',
    label: 'APPLE MUSIC',
    iconBuilder: (c) => _fa(FontAwesomeIcons.apple, c),
    domains: const ['music.apple.com'],
  ),
  PlatformItem(
    id: 'facebook',
    label: 'FACEBOOK',
    iconBuilder: (c) => _fa(FontAwesomeIcons.facebook, c),
    domains: const ['facebook.com', 'fb.watch', 'fb.com'],
  ),
  PlatformItem(
    id: 'bandcamp',
    label: 'BANDCAMP',
    iconBuilder: (c) => _fa(FontAwesomeIcons.bandcamp, c),
    domains: const ['bandcamp.com'],
  ),
  PlatformItem(
    id: 'pixiv',
    label: 'PIXIV',
    iconBuilder: (c) => _fa(FontAwesomeIcons.pixiv, c),
    domains: const ['pixiv.net'],
  ),
  PlatformItem(
    id: 'reddit',
    label: 'REDDIT',
    iconBuilder: (c) => _fa(FontAwesomeIcons.reddit, c),
    domains: const ['reddit.com', 'redd.it'],
  ),
  PlatformItem(
    id: 'terabox',
    label: 'TERABOX',
    iconBuilder: (c) => _svg('assets/icons/terabox.svg', c),
    domains: const ['terabox.com', 'terabox.app', '1024terabox.com'],
  ),
];

/// Deteksi platform dari URL dengan dukungan domain khusus & wildcard.
PlatformItem? detectPlatform(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null) return null;
  final host = uri.host.toLowerCase();
  if (host.isEmpty) return null;

  for (final p in kPlatforms) {
    for (final d in p.domains) {
      if (host == d || host.endsWith('.$d')) return p;
    }
  }

  // Fallback domain wildcard (pinterest.*, terabox.*)
  if (host.contains('pinterest.') || host == 'pin.it' || host.endsWith('.pin.it')) {
    return kPlatforms.firstWhere((p) => p.id == 'pinterest');
  }
  if (host.contains('terabox.')) {
    return kPlatforms.firstWhere((p) => p.id == 'terabox');
  }

  return null;
}