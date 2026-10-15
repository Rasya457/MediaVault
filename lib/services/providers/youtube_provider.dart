// YouTube Provider - ditulis ulang clean-room, bukan copy dari repo mana pun.
//
// Status verifikasi E2E 2026-10-15:
// - PRIMARY Innertube langsung on-device: VERIFIED dengan video & Shorts asli
//   (playability OK dengan visitorData, judul/author cocok, direct MP4 & audio
//   tanpa cipher). Tanpa pihak ketiga, source 'direct'.
// - Pilihan kualitas difilter rapi: 1080p, 720p, 480p, 360p, dan Audio MP3.

import 'package:dio/dio.dart';
import '../../core/network/api_client.dart';
import 'provider.dart';
import 'models.dart';
import 'remote_config.dart';

const _kPrimaryId = 'youtube_primary';
const _kFallbackId = 'youtube_fallback';
const _kInnertubeId = 'youtube_innertube';

const _kAndroidKey = 'AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8';
const _kAndroidVersion = '20.10.38';
const _kDefaultPlayerBase = 'https://www.youtube.com/youtubei/v1/player';

bool _canHandleYouTube(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  final host = uri.host.toLowerCase();
  return host.contains('youtube.com') || host == 'youtu.be';
}

/// Ambil video ID dari URL watch, shorts, youtu.be, live, atau embed. Null jika tidak ada.
String? _extractVideoId(String url) {
  final clean = url.trim();
  final uri = Uri.tryParse(clean);
  if (uri == null) return null;

  // 1. Parameter v= (mis. watch?v=...)
  final v = uri.queryParameters['v'];
  if (v != null && v.isNotEmpty) return v;

  // 2. Short domain youtu.be/ID
  if (uri.host.toLowerCase() == 'youtu.be' ||
      uri.host.toLowerCase().endsWith('.youtu.be')) {
    final nonNullSegs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (nonNullSegs.isNotEmpty) return nonNullSegs.first;
  }

  // 3. Path segments (shorts/ID, live/ID, embed/ID, v/ID)
  final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  for (var i = 0; i < segs.length - 1; i++) {
    final prefix = segs[i].toLowerCase();
    if (prefix == 'shorts' ||
        prefix == 'live' ||
        prefix == 'embed' ||
        prefix == 'v') {
      return segs[i + 1];
    }
  }

  // 4. Regex fallback jika ada format khusus
  final regexMatch = RegExp(
          r'(?:v=|\/shorts\/|\/embed\/|\/live\/|\/v\/|youtu\.be\/)([a-zA-Z0-9_-]{11})')
      .firstMatch(clean);
  if (regexMatch != null) {
    return regexMatch.group(1);
  }

  return null;
}

String _resolveQuality(MediaInfo info, String quality) {
  if (info.qualities.isEmpty) {
    throw const ProviderException(
      message: 'tidak ada kualitas tersedia',
      kind: ProviderErrorKind.noResult,
    );
  }
  if (quality == 'best') return info.qualities.first.itag;
  return info.qualities
      .firstWhere((q) => q.itag == quality || q.label == quality,
          orElse: () => info.qualities.first)
      .itag;
}

class YouTubePrimaryProvider implements MediaProvider {
  @override
  String get providerName => 'YtMp3';

  @override
  bool canHandle(String url) => _canHandleYouTube(url);

  @override
  Future<MediaInfo> fetchInfo(String url) async {
    final videoId = _extractVideoId(url);
    if (videoId == null) {
      throw const ProviderException(
        message: 'link YouTube tidak mengandung video ID',
        kind: ProviderErrorKind.invalidUrl,
      );
    }

    final cfg = await RemoteConfig.instance.get(_kPrimaryId);
    if (cfg == null || !cfg.enabled) {
      throw const ProviderException(
        message: 'Primary YouTube provider disabled.',
        kind: ProviderErrorKind.providerDown,
      );
    }

    late final Response<Map<String, dynamic>> response;
    try {
      response = await httpClient.get<Map<String, dynamic>>(
        cfg.url,
        queryParameters: {'url': 'https://www.youtube.com/watch?v=$videoId'},
      );
    } on DioException catch (e) {
      throw ProviderException(
        message: 'endpoint YouTube tidak merespons (${e.type.name})',
        kind: ProviderErrorKind.providerDown,
        underlyingError: e,
      );
    }

    final body = response.data ?? {};
    if (body['status'] != 'ok' || body['result'] is! Map) {
      throw ProviderException(
        message: 'ytmp3: ${body['message'] ?? 'gagal memproses'}',
        kind: ProviderErrorKind.noResult,
      );
    }
    final result = (body['result'] as Map).cast<String, dynamic>();
    final dl = (result['url'] ?? '').toString();
    if (dl.isEmpty) {
      throw const ProviderException(
        message: 'ytmp3: tidak ada URL unduhan.',
        kind: ProviderErrorKind.noResult,
      );
    }

    return MediaInfo(
      title: (result['title'] ?? 'YouTube Video').toString(),
      author: 'YouTube',
      thumbnail: result['thumbnail'] as String?,
      durationSec: (result['duration'] as num?)?.toInt(),
      qualities: [MediaQuality(label: 'Video MP4', itag: dl)],
      source: 'third-party',
      providerName: providerName,
    );
  }

  @override
  Future<String> fetchDownloadUrl(String url, {String quality = 'best'}) async =>
      _resolveQuality(await fetchInfo(url), quality);
}

class YouTubeFallbackProvider implements MediaProvider {
  @override
  String get providerName => 'Yt1s';

  @override
  bool canHandle(String url) => _canHandleYouTube(url);

  @override
  Future<MediaInfo> fetchInfo(String url) async {
    final videoId = _extractVideoId(url);
    if (videoId == null) {
      throw const ProviderException(
        message: 'link YouTube tidak mengandung video ID',
        kind: ProviderErrorKind.invalidUrl,
      );
    }

    final cfg = await RemoteConfig.instance.get(_kFallbackId);
    if (cfg == null || !cfg.enabled) {
      throw const ProviderException(
        message: 'Fallback YouTube provider disabled.',
        kind: ProviderErrorKind.providerDown,
      );
    }

    late final Response<Map<String, dynamic>> response;
    try {
      response = await httpClient.post<Map<String, dynamic>>(
        cfg.url,
        data: {'videoId': videoId},
      );
    } on DioException catch (e) {
      throw ProviderException(
        message: 'endpoint YouTube tidak merespons (${e.type.name})',
        kind: ProviderErrorKind.providerDown,
        underlyingError: e,
      );
    }

    final body = response.data ?? {};
    if (body['status'] != 'ok') {
      throw ProviderException(
        message: 'yt1s: ${body['message'] ?? 'gagal memproses'}',
        kind: ProviderErrorKind.noResult,
      );
    }
    final dl = (body['d_url'] ?? '').toString();
    if (dl.isEmpty) {
      throw const ProviderException(
        message: 'yt1s: tidak ada URL unduhan.',
        kind: ProviderErrorKind.noResult,
      );
    }
    final fquality = (body['fquality'] ?? '').toString();

    return MediaInfo(
      title: (body['title'] ?? 'YouTube Video').toString(),
      author: 'YouTube',
      thumbnail: null,
      durationSec: null,
      qualities: [
        MediaQuality(
          label: fquality.isEmpty ? 'Video' : '${fquality}p',
          itag: dl,
        ),
      ],
      source: 'third-party',
      providerName: providerName,
    );
  }

  @override
  Future<String> fetchDownloadUrl(String url, {String quality = 'best'}) async =>
      _resolveQuality(await fetchInfo(url), quality);
}

class YouTubeInnertubeProvider implements MediaProvider {
  @override
  String get providerName => 'Innertube';

  @override
  bool canHandle(String url) => _canHandleYouTube(url);

  static String? _cachedVisitorData;
  static DateTime? _visitorDataFetchedAt;

  Future<String?> _getVisitorData() async {
    if (_cachedVisitorData != null &&
        _visitorDataFetchedAt != null &&
        DateTime.now().difference(_visitorDataFetchedAt!).inHours < 12) {
      return _cachedVisitorData;
    }
    try {
      final res = await httpClient.get<String>(
        'https://www.youtube.com/',
        options: Options(responseType: ResponseType.plain),
      );
      final html = res.data ?? '';
      final m = RegExp(r'"(?:VISITOR_DATA|visitorData)":\s*"([^"]+)"')
          .firstMatch(html);
      if (m != null) {
        _cachedVisitorData = m.group(1);
        _visitorDataFetchedAt = DateTime.now();
      }
    } catch (_) {}
    return _cachedVisitorData;
  }

  @override
  Future<MediaInfo> fetchInfo(String url) async {
    final videoId = _extractVideoId(url);
    if (videoId == null) {
      throw const ProviderException(
        message: 'link YouTube tidak mengandung video ID',
        kind: ProviderErrorKind.invalidUrl,
      );
    }

    final cfg = await RemoteConfig.instance.get(_kInnertubeId);
    if (cfg != null && !cfg.enabled) {
      throw const ProviderException(
        message: 'Innertube provider disabled.',
        kind: ProviderErrorKind.providerDown,
      );
    }
    final base = (cfg?.url.isNotEmpty ?? false)
        ? cfg!.url
        : _kDefaultPlayerBase;

    final visitorData = await _getVisitorData();

    late final Response<Map<String, dynamic>> response;
    try {
      response = await httpClient.post<Map<String, dynamic>>(
        '$base?key=$_kAndroidKey&prettyPrint=false',
        data: {
          'context': {
            'client': {
              'clientName': 'ANDROID',
              'clientVersion': _kAndroidVersion,
              'androidSdkVersion': 34,
              'visitorData': ?visitorData,
              'hl': 'en',
              'gl': 'US',
            },
          },
          'videoId': videoId,
          'playbackContext': {
            'contentPlaybackContext': {'html5Preference': 'HTML5_PREF_WANTS'},
          },
        },
        options: Options(
          responseType: ResponseType.json,
          headers: {
            'X-YouTube-Client-Name': '3',
            'X-YouTube-Client-Version': _kAndroidVersion,
          },
        ),
      );
    } on DioException catch (e) {
      throw ProviderException(
        message: 'endpoint YouTube tidak merespons (${e.type.name})',
        kind: ProviderErrorKind.providerDown,
        underlyingError: e,
      );
    }

    final body = response.data ?? {};
    final status =
        (body['playabilityStatus'] as Map?)?.cast<String, dynamic>();
    if (status?['status'] != 'OK') {
      throw ProviderException(
        message:
            'youtube: ${status?['reason'] ?? 'video tidak dapat diputar'}',
        kind: ProviderErrorKind.noResult,
      );
    }
    final details =
        (body['videoDetails'] as Map?)?.cast<String, dynamic>() ?? {};
    final streaming =
        (body['streamingData'] as Map?)?.cast<String, dynamic>() ?? {};
    final rawFormats = [
      ...(streaming['formats'] as List? ?? []),
      ...(streaming['adaptiveFormats'] as List? ?? []),
    ].map((f) => (f as Map).cast<String, dynamic>()).toList();

    final qualities = _filterYouTubeQualities(rawFormats);
    if (qualities.isEmpty) {
      throw const ProviderException(
        message: 'youtube: tidak ada stream direct (butuh decipher).',
        kind: ProviderErrorKind.noResult,
      );
    }

    final thumbs =
        (details['thumbnail'] as Map?)?['thumbnails'] as List? ?? [];
    final length = details['lengthSeconds'];
    return MediaInfo(
      title: (details['title'] ?? 'YouTube Video').toString(),
      author: (details['author'] ?? 'YouTube').toString(),
      thumbnail: thumbs.isNotEmpty
          ? (thumbs.last as Map)['url']?.toString()
          : null,
      durationSec: length is num
          ? length.toInt()
          : int.tryParse(length.toString()),
      qualities: qualities,
      source: 'direct',
      providerName: providerName,
      downloadHeaders: const {
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Mobile Safari/537.36',
      },
    );
  }

  @override
  Future<String> fetchDownloadUrl(String url, {String quality = 'best'}) async =>
      _resolveQuality(await fetchInfo(url), quality);
}

/// Filter kualitas YouTube: Mengembalikan format video (1080p, 720p, 480p, 360p)
/// dan Audio MP3. Untuk format adaptif yang belum memiliki audio, pasangkan
/// stream audio terbaik via [MediaQuality.audioUrl] agar digabung otomatis (FFmpeg)
/// sehingga SEMUA opsi video 100% memiliki audio!
List<MediaQuality> _filterYouTubeQualities(
    List<Map<String, dynamic>> rawFormats) {
  const targetResolutions = ['1080p', '720p', '480p', '360p'];

  final videoMap = <String, MediaQuality>{};
  MediaQuality? bestAudio;
  int maxAudioBitrate = 0;
  String? bestAudioUrl;
  int? bestAudioBytes;

  // 1. Dapatkan stream audio terbaik (bitrate tertinggi)
  for (final raw in rawFormats) {
    final url = (raw['url'] ?? '').toString();
    if (url.isEmpty) continue;
    final mime = (raw['mimeType'] ?? '').toString();

    if (mime.startsWith('audio/')) {
      final bitrate = (raw['bitrate'] as num?)?.toInt() ?? 0;
      final contentLength =
          int.tryParse((raw['contentLength'] ?? '').toString());
      final isM4a = mime.contains('mp4') || mime.contains('m4a');
      if (bitrate > maxAudioBitrate || (bitrate == maxAudioBitrate && isM4a)) {
        maxAudioBitrate = bitrate;
        bestAudioUrl = url;
        bestAudioBytes = contentLength;
        bestAudio = MediaQuality(
          label: 'Audio MP3',
          itag: url,
          extension: 'mp3',
          hasAudio: true,
          sizeBytes: contentLength,
        );
      }
    }
  }

  // 2. Petakan format video ke resolusi target
  for (final raw in rawFormats) {
    final url = (raw['url'] ?? '').toString();
    if (url.isEmpty) continue;
    final mime = (raw['mimeType'] ?? '').toString();

    if (mime.startsWith('video/')) {
      final qLabel = (raw['qualityLabel'] ?? raw['quality'] ?? '').toString();
      final hasAudio = raw.containsKey('audioQuality') ||
          raw.containsKey('audioChannels') ||
          mime.contains('mp4a');
      final videoBytes = int.tryParse((raw['contentLength'] ?? '').toString());
      final isMp4 = mime.contains('mp4');

      for (final target in targetResolutions) {
        final height = target.replaceAll('p', '');
        if (qLabel.startsWith(height) || qLabel.contains(target)) {
          final existing = videoMap[target];
          final existingHasAudio = existing?.hasAudio ?? false;

          // Utamakan stream muxed. Jika tidak ada muxed tapi ada audio terpisah,
          // pasangkan audioUrl agar di-merge via FFmpeg.
          if (existing == null ||
              (!existingHasAudio && hasAudio) ||
              (!existingHasAudio && isMp4)) {
            final totalBytes = videoBytes != null
                ? videoBytes + (hasAudio ? 0 : (bestAudioBytes ?? 0))
                : null;

            videoMap[target] = MediaQuality(
              label: target,
              itag: url,
              extension: isMp4 ? 'mp4' : 'webm',
              hasAudio: hasAudio,
              audioUrl: hasAudio ? null : bestAudioUrl,
              sizeBytes: totalBytes,
            );
          }
          break;
        }
      }
    }
  }

  final result = <MediaQuality>[];
  for (final res in targetResolutions) {
    if (videoMap.containsKey(res)) {
      result.add(videoMap[res]!);
    }
  }

  // Fallback jika tidak ada di targetResolutions
  if (result.isEmpty) {
    for (final raw in rawFormats) {
      final url = (raw['url'] ?? '').toString();
      final mime = (raw['mimeType'] ?? '').toString();
      if (url.isNotEmpty && mime.startsWith('video/')) {
        final q =
            (raw['qualityLabel'] ?? raw['quality'] ?? 'Video').toString();
        final hasAudio = raw.containsKey('audioQuality') ||
            raw.containsKey('audioChannels') ||
            mime.contains('mp4a');
        result.add(MediaQuality(
          label: q,
          itag: url,
          extension: 'mp4',
          hasAudio: hasAudio,
          audioUrl: hasAudio ? null : bestAudioUrl,
        ));
        break;
      }
    }
  }

  // Tambahkan Audio MP3
  if (bestAudio != null) {
    result.add(bestAudio);
  }

  return result;
}
