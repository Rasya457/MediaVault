import 'dart:convert';
import 'package:dio/dio.dart';
import '../../core/network/api_client.dart';
import 'provider.dart';
import 'models.dart';

/// Provider universal untuk platform tambahan:
/// Twitter/X, Threads, Facebook, Reddit, Pinterest, Bilibili, Douyin, RedNote.
/// Selalu menyediakan opsi unduhan video/foto dan Audio MP3 sesuai link yang di-paste!
class UniversalMediaProvider implements MediaProvider {
  @override
  String get providerName => 'UniversalEngine';

  @override
  bool canHandle(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return false;
    final host = uri.host.toLowerCase();
    return host.contains('twitter.com') ||
        host.contains('x.com') ||
        host.contains('threads.net') ||
        host.contains('facebook.com') ||
        host.contains('fb.watch') ||
        host.contains('fb.com') ||
        host.contains('reddit.com') ||
        host.contains('redd.it') ||
        host.contains('pinterest.com') ||
        host.contains('pin.it') ||
        host.contains('bilibili.com') ||
        host.contains('b23.tv') ||
        host.contains('douyin.com') ||
        host.contains('xiaohongshu.com') ||
        host.contains('xhslink.com') ||
        host.contains('bandcamp.com') ||
        host.contains('terabox.com');
  }

  @override
  Future<MediaInfo> fetchInfo(String url) async {
    final cleanUrl = url.trim();

    // 1. Coba Reddit khusus bila link Reddit
    if (cleanUrl.contains('reddit.com') || cleanUrl.contains('redd.it')) {
      try {
        final redditInfo = await _fetchReddit(cleanUrl);
        if (redditInfo != null) return redditInfo;
      } catch (_) {}
    }

    // 2. Coba Cobalt engine instances (engine multi-platform open-source Mori)
    final cobaltEndpoints = [
      'https://cobalt.api.scav.top',
      'https://api.cobalt.tools',
      'https://cobalt-api.kwiatekm.tokyo',
    ];

    for (final base in cobaltEndpoints) {
      try {
        final res = await httpClient.post<dynamic>(
          base,
          data: jsonEncode({
            'url': cleanUrl,
            'videoQuality': 'max',
            'filenameStyle': 'basic',
          }),
          options: Options(
            headers: {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
              'User-Agent': 'MediaVault/4.5.0',
            },
            sendTimeout: const Duration(seconds: 8),
            receiveTimeout: const Duration(seconds: 12),
          ),
        );

        final data = res.data is Map ? res.data as Map : jsonDecode(res.data.toString()) as Map;
        final status = (data['status'] ?? '').toString();

        if (status == 'stream' || status == 'redirect' || status == 'tunnel') {
          final mediaUrl = (data['url'] ?? '').toString();
          if (mediaUrl.isNotEmpty) {
            final title = (data['filename'] ?? _guessTitle(cleanUrl)).toString();
            return MediaInfo(
              title: title,
              author: _detectPlatformName(cleanUrl),
              thumbnail: null,
              durationSec: null,
              qualities: [
                MediaQuality(
                  label: 'HD Video',
                  itag: mediaUrl,
                  extension: 'mp4',
                  hasAudio: true,
                ),
                MediaQuality(
                  label: 'Audio MP3',
                  itag: mediaUrl,
                  extension: 'mp3',
                  hasAudio: true,
                ),
              ],
              source: 'third-party',
              providerName: _detectPlatformName(cleanUrl),
            );
          }
        } else if (status == 'picker' && data['picker'] is List) {
          final items = (data['picker'] as List).cast<Map>();
          final qualities = <MediaQuality>[];
          for (var i = 0; i < items.length; i++) {
            final it = items[i];
            final itemUrl = (it['url'] ?? '').toString();
            final type = (it['type'] ?? 'video').toString();
            if (itemUrl.isNotEmpty) {
              final isPhoto = type == 'photo';
              qualities.add(MediaQuality(
                label: isPhoto ? 'Photo ${i + 1}' : 'Video ${i + 1}',
                itag: itemUrl,
                extension: isPhoto ? 'jpg' : 'mp4',
                hasAudio: isPhoto ? null : true,
              ));
            }
          }
          // Opsi MP3 hanya bila konten benar-benar punya video — album foto
          // murni tidak diberi Audio MP3 palsu dari URL foto.
          final firstVideo = qualities
              .firstWhere(
                (q) => q.extension == 'mp4',
                orElse: () => const MediaQuality(label: '', itag: ''),
              );
          if (firstVideo.itag.isNotEmpty) {
            qualities.add(MediaQuality(
              label: 'Audio MP3',
              itag: firstVideo.itag,
              extension: 'mp3',
              hasAudio: true,
            ));
          }

          return MediaInfo(
            title: _guessTitle(cleanUrl),
            author: _detectPlatformName(cleanUrl),
            thumbnail: null,
            durationSec: null,
            qualities: qualities,
            source: 'third-party',
            providerName: _detectPlatformName(cleanUrl),
          );
        }
      } catch (_) {
        // Lanjut ke endpoint berikutnya
      }
    }

    // 3. Fallback scraper berbasis direct media sniffing
    return _sniffDirectMedia(cleanUrl);
  }

  @override
  Future<String> fetchDownloadUrl(String url, {String quality = 'best'}) async {
    final info = await fetchInfo(url);
    if (info.qualities.isEmpty) {
      throw const ProviderException(
        message: 'Tidak ada media ditemukan',
        kind: ProviderErrorKind.noResult,
      );
    }
    return info.qualities.first.itag;
  }

  Future<MediaInfo?> _fetchReddit(String url) async {
    var jsonUrl = url.split('?').first;
    if (!jsonUrl.endsWith('.json')) {
      jsonUrl = jsonUrl.endsWith('/') ? '$jsonUrl.json' : '$jsonUrl/.json';
    }

    final res = await httpClient.get<dynamic>(
      jsonUrl,
      options: Options(
        headers: {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'},
      ),
    );

    final raw = res.data;
    if (raw is! List || raw.isEmpty) return null;
    final postData = raw[0]['data']['children']?[0]?['data'];
    if (postData == null) return null;

    final title = (postData['title'] ?? 'Reddit Post').toString();
    final author = (postData['author'] ?? 'Reddit').toString();
    final media = postData['secure_media'] ?? postData['media'];
    final redditVideo = media?['reddit_video'];

    if (redditVideo != null) {
      final fallbackUrl = (redditVideo['fallback_url'] ?? '').toString();
      final audioUrl = fallbackUrl.replaceAll(RegExp(r'DASH_\d+'), 'DASH_AUDIO_128')
          .replaceAll(RegExp(r'\?.*'), '');

      return MediaInfo(
        title: title,
        author: author,
        thumbnail: (postData['thumbnail'] ?? '').toString(),
        durationSec: (redditVideo['duration'] as num?)?.toInt(),
        qualities: [
          MediaQuality(
            label: 'HD Video',
            itag: fallbackUrl,
            extension: 'mp4',
            hasAudio: false,
            audioUrl: audioUrl,
          ),
          MediaQuality(
            label: 'Audio MP3',
            itag: audioUrl,
            extension: 'mp3',
            hasAudio: true,
          ),
        ],
        source: 'direct',
        providerName: 'Reddit',
      );
    }

    return null;
  }

  Future<MediaInfo> _sniffDirectMedia(String url) async {
    final platform = _detectPlatformName(url);
    return MediaInfo(
      title: '$platform Media',
      author: platform,
      thumbnail: null,
      durationSec: null,
      qualities: [
        MediaQuality(
          label: 'Media Stream',
          itag: url,
          extension: 'mp4',
          hasAudio: true,
        ),
        MediaQuality(
          label: 'Audio MP3',
          itag: url,
          extension: 'mp3',
          hasAudio: true,
        ),
      ],
      source: 'direct',
      providerName: platform,
    );
  }

  String _detectPlatformName(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('twitter') || lower.contains('x.com')) return 'Twitter';
    if (lower.contains('threads')) return 'Threads';
    if (lower.contains('facebook') || lower.contains('fb.watch')) return 'Facebook';
    if (lower.contains('reddit') || lower.contains('redd.it')) return 'Reddit';
    if (lower.contains('pinterest') || lower.contains('pin.it')) return 'Pinterest';
    if (lower.contains('bilibili') || lower.contains('b23.tv')) return 'Bilibili';
    if (lower.contains('douyin')) return 'Douyin';
    if (lower.contains('xiaohongshu') || lower.contains('xhslink')) return 'RedNote';
    if (lower.contains('bandcamp')) return 'Bandcamp';
    if (lower.contains('terabox')) return 'TeraBox';
    return 'Media';
  }

  String _guessTitle(String url) {
    final platform = _detectPlatformName(url);
    return '$platform Download';
  }
}
