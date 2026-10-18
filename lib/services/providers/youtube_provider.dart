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
const _kWebVersion = '2.20260101.00.00';
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

// YouTube Provider — alur third-party mengikuti pola scraper referensi
// coflyn/Mori (bundle.js): convert via hub.convert1s.com lalu polling
// statusUrl hingga completed. Bukan copy-paste, ditulis ulang dalam Dart.

/// Delay polling konversi. Dioverride test jadi Duration.zero.
Duration ytmp3PollDelay = const Duration(milliseconds: 1500);

class YouTubePrimaryProvider implements MediaProvider {
  @override
  String get providerName => 'Ytmp3';

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

    final watchUrl = 'https://www.youtube.com/watch?v=$videoId';
    final meta = await _fetchOembed(watchUrl);

    final qualities = <MediaQuality>[];
    for (final q in ['720p', '360p']) {
      final dl = await _convertMp4(cfg.url, watchUrl, q);
      if (dl != null) {
        qualities.add(MediaQuality(label: 'MP4 ${dl.quality}', itag: dl.url));
      }
    }
    final audio = await _convertMp3(cfg.url, watchUrl);
    if (audio != null) {
      qualities.add(
        MediaQuality(label: 'MP3', itag: audio, extension: 'mp3'),
      );
    }
    if (qualities.isEmpty) {
      throw const ProviderException(
        message: 'ytmp3: gagal mengonversi video. Coba lagi nanti.',
        kind: ProviderErrorKind.noResult,
      );
    }

    return MediaInfo(
      title: meta.title,
      author: 'YouTube',
      thumbnail: meta.thumbnail,
      durationSec: null,
      qualities: qualities,
      source: 'third-party',
      providerName: providerName,
    );
  }

  @override
  Future<String> fetchDownloadUrl(String url, {String quality = 'best'}) async =>
      _resolveQuality(await fetchInfo(url), quality);
}

/// Judul + thumbnail best-effort via oEmbed. Gagal = default.
Future<({String title, String? thumbnail})> _fetchOembed(
  String watchUrl,
) async {
  try {
    final res = await httpClient.get<Map<String, dynamic>>(
      'https://www.youtube.com/oembed',
      queryParameters: {'url': watchUrl, 'format': 'json'},
    );
    final body = res.data ?? {};
    return (
      title: (body['title'] ?? 'YouTube Video').toString(),
      thumbnail: body['thumbnail_url'] as String?,
    );
  } catch (_) {
    return (title: 'YouTube Video', thumbnail: null);
  }
}

Map<String, String> _ggHeaders() => {
      'Origin': 'https://media.ytmp3.gg',
      'Referer': 'https://media.ytmp3.gg/',
      'Accept': 'application/json, text/plain, */*',
    };

/// Minta konversi MP4 [quality] lalu polling hingga completed.
/// Null kalau gagal di tahap mana pun (pemanggil lanjut ke opsi berikut).
Future<({String url, String quality})?> _convertMp4(
  String endpoint,
  String watchUrl,
  String quality,
) async {
  final statusUrl = await _ggRequest(endpoint, watchUrl, 'video', 'mp4',
      quality: quality);
  if (statusUrl == null) return null;
  final done = await _ggPoll(statusUrl);
  if (done == null) return null;
  return (url: done.url, quality: done.quality.isEmpty ? quality : done.quality);
}

/// Minta konversi MP3. Null kalau gagal.
Future<String?> _convertMp3(String endpoint, String watchUrl) async {
  final statusUrl =
      await _ggRequest(endpoint, watchUrl, 'audio', 'mp3');
  if (statusUrl == null) return null;
  final done = await _ggPoll(statusUrl);
  return done?.url;
}

/// POST konversi ke hub. Kembalikan statusUrl, atau null bila ditolak.
Future<String?> _ggRequest(
  String endpoint,
  String watchUrl,
  String type,
  String format, {
  String quality = '',
}) async {
  try {
    final res = await httpClient.post<Map<String, dynamic>>(
      endpoint,
      data: {
        'url': watchUrl,
        'os': 'macos',
        'output': {'type': type, 'format': format, 'quality': quality},
        'audio': {'bitrate': '128k'},
      },
      options: Options(headers: _ggHeaders()),
    );
    final body = res.data ?? {};
    if (body['error'] == true) return null;
    final statusUrl = (body['statusUrl'] ?? '').toString();
    return statusUrl.isEmpty ? null : statusUrl;
  } on DioException {
    return null;
  }
}

/// Polling statusUrl hingga completed (max 30x). Kembalikan URL + kualitas.
Future<({String url, String quality})?> _ggPoll(String statusUrl) async {
  for (var i = 0; i < 30; i++) {
    await Future<void>.delayed(ytmp3PollDelay);
    Map<String, dynamic> body;
    try {
      final res = await httpClient.get<Map<String, dynamic>>(
        statusUrl,
        options: Options(headers: _ggHeaders()),
      );
      body = res.data ?? {};
    } on DioException {
      return null;
    }
    final status = (body['status'] ?? '').toString();
    if (status == 'completed' &&
        (body['downloadUrl'] ?? '').toString().isNotEmpty) {
      return (
        url: (body['downloadUrl'] ?? '').toString(),
        quality: (body['selectedQuality'] ?? '').toString(),
      );
    }
    if (status == 'error' || status == 'failed') return null;
  }
  return null;
}

/// Fallback YouTube via ycdn (pola referensi coflyn/Mori "mobi"):
/// init -> convert -> ikuti redirect -> polling progress hingga >=3.
/// Ditulis ulang dalam Dart, bukan copy-paste.
class YouTubeFallbackProvider implements MediaProvider {
  @override
  String get providerName => 'Ytmp3Mobi';

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

    final watchUrl = 'https://www.youtube.com/watch?v=$videoId';
    final meta = await _fetchOembed(watchUrl);

    final qualities = <MediaQuality>[];
    final mp4 = await _mobiConvert(cfg.url, videoId, 'mp4');
    if (mp4 != null) {
      qualities.add(MediaQuality(label: 'MP4', itag: mp4));
    }
    final mp3 = await _mobiConvert(cfg.url, videoId, 'mp3');
    if (mp3 != null) {
      qualities.add(
        MediaQuality(label: 'MP3', itag: mp3, extension: 'mp3'),
      );
    }
    if (qualities.isEmpty) {
      throw const ProviderException(
        message: 'ytmp3.mobi: gagal mengonversi video. Coba lagi nanti.',
        kind: ProviderErrorKind.noResult,
      );
    }

    return MediaInfo(
      title: meta.title,
      author: 'YouTube',
      thumbnail: meta.thumbnail,
      durationSec: null,
      qualities: qualities,
      source: 'third-party',
      providerName: providerName,
    );
  }

  @override
  Future<String> fetchDownloadUrl(String url, {String quality = 'best'}) async =>
      _resolveQuality(await fetchInfo(url), quality);
}

Map<String, String> _mobiHeaders() => {
      'Origin': 'https://ytmp3.mobi',
      'Referer': 'https://ytmp3.mobi/en8/',
      'Accept': '*/*',
    };

String _mobiNonce() => DateTime.now().millisecondsSinceEpoch.toString();

/// Satu konversi mobi untuk format [fmt] ('mp4'/'mp3'). Null bila gagal.
Future<String?> _mobiConvert(
  String initBase,
  String videoId,
  String fmt,
) async {
  try {
    final initRes = await httpClient.get<Map<String, dynamic>>(
      '$initBase?p=y&23=1llum1n471&_=${_mobiNonce()}',
      options: Options(headers: _mobiHeaders()),
    );
    final init = initRes.data ?? {};
    if (init['error'] == true) return null;
    var convertUrl = (init['convertURL'] ?? '').toString();
    if (convertUrl.isEmpty) return null;

    // Ikuti rantai redirect.
    Map<String, dynamic> cur = {};
    for (var i = 0; i < 5; i++) {
      final res = await httpClient.get<Map<String, dynamic>>(
        '$convertUrl&v=$videoId&f=$fmt&_=${_mobiNonce()}',
        options: Options(headers: _mobiHeaders()),
      );
      cur = res.data ?? {};
      if (cur['error'] == true) return null;
      final next = (cur['redirectURL'] ?? '').toString();
      if ((cur['redirect'] as num? ?? 0) > 0 && next.isNotEmpty) {
        convertUrl = next;
        continue;
      }
      break;
    }

    var downloadUrl = (cur['downloadURL'] ?? '').toString();
    final progressUrl = (cur['progressURL'] ?? '').toString();
    var progress = (cur['progress'] as num? ?? 0).toDouble();
    if (downloadUrl.isNotEmpty && progress >= 3) {
      return _mobiNormalize(downloadUrl);
    }

    // Polling progress hingga selesai (max 20x).
    for (var i = 0; i < 20 && progressUrl.isNotEmpty; i++) {
      if (progress >= 3 && downloadUrl.isNotEmpty) break;
      await Future<void>.delayed(ytmp3PollDelay);
      final pres = await httpClient.get<Map<String, dynamic>>(
        '$progressUrl&_=${_mobiNonce()}',
        options: Options(headers: _mobiHeaders()),
      );
      final pbody = pres.data ?? {};
      if (pbody['error'] == true) return null;
      progress = (pbody['progress'] as num? ?? progress).toDouble();
      final dl = (pbody['downloadURL'] ?? '').toString();
      if (dl.isNotEmpty) downloadUrl = dl;
      if (progress >= 3 && downloadUrl.isNotEmpty) {
        return _mobiNormalize(downloadUrl);
      }
    }
    return null;
  } on DioException {
    return null;
  }
}

/// Normalisasi URL relatif ycdn ke absolut.
String _mobiNormalize(String url) {
  if (url.startsWith('//')) return 'https:$url';
  if (url.startsWith('/')) return 'https://ytmp3.mobi$url';
  return url;
}

/// Rantai third-party: coba convert1s dulu, gagal total baru mobi.
/// Dipakai registry sebagai fallback Innertube.
class YouTubeThirdPartyProvider implements MediaProvider {
  @override
  String get providerName => 'Ytmp3';

  @override
  bool canHandle(String url) => _canHandleYouTube(url);

  @override
  Future<MediaInfo> fetchInfo(String url) async {
    try {
      return await YouTubePrimaryProvider().fetchInfo(url);
    } on ProviderException catch (e) {
      if (e.kind == ProviderErrorKind.invalidUrl ||
          e.kind == ProviderErrorKind.providerDown) {
        rethrow;
      }
    }
    return YouTubeFallbackProvider().fetchInfo(url);
  }

  @override
  Future<String> fetchDownloadUrl(String url, {String quality = 'best'}) async =>
      _resolveQuality(await fetchInfo(url), quality);
}

/// Konfigurasi client Innertube untuk satu percobaan player API.
class _InnertubeClient {
  const _InnertubeClient({
    required this.name,
    required this.version,
    required this.headerName,
    this.androidSdkVersion,
    this.visitorData,
  });

  final String name;
  final String version;
  final String headerName;
  final int? androidSdkVersion;
  final String? visitorData;
}

/// Petakan playabilityStatus non-OK ke error yang jujur: verifikasi bot
/// / login = providerDown (sementara), sisanya noResult (permanen).
ProviderException _playabilityError(Map<String, dynamic>? status) {
  final rawStatus = (status?['status'] ?? '').toString();
  final reason = (status?['reason'] ?? 'video tidak dapat diputar').toString();
  final sub = (status?['subreason'] ?? '').toString();
  final blob = '$rawStatus $reason $sub'.toLowerCase();
  if (blob.contains('bot') ||
      blob.contains('confirm you') ||
      blob.contains('sign in to confirm')) {
    return ProviderException(
      message: 'youtube: verifikasi bot/login ($reason). Coba lagi nanti.',
      kind: ProviderErrorKind.providerDown,
    );
  }
  return ProviderException(
    message: 'youtube: $reason',
    kind: ProviderErrorKind.noResult,
  );
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

    // Coba ANDROID dulu (biasanya memberi direct MP4), lalu WEB sebagai
    // cadangan saat ANDROID diblokir verifikasi bot. Client pertama yang
    // mengembalikan playability OK + stream direct dipakai.
    ProviderException? lastError;
    final clients = [
      _InnertubeClient(
        name: 'ANDROID',
        version: _kAndroidVersion,
        headerName: '3',
        androidSdkVersion: 34,
        visitorData: visitorData,
      ),
      const _InnertubeClient(name: 'WEB', version: _kWebVersion, headerName: '1'),
    ];
    for (final client in clients) {
      try {
        return await _fetchWithClient(base, videoId, client);
      } on ProviderException catch (e) {
        // Gagal jaringan (endpoint tidak merespons) langsung diteruskan
        // agar tidak disamarkan. Verifikasi bot / cipher-kosong lanjut
        // ke client berikutnya.
        if (e.kind == ProviderErrorKind.providerDown &&
            e.message.contains('tidak merespons')) {
          rethrow;
        }
        lastError = e;
      }
    }
    throw lastError ??
        const ProviderException(
          message: 'youtube: tidak ada stream direct (butuh decipher).',
          kind: ProviderErrorKind.noResult,
        );
  }

  /// Satu percobaan player API dengan [client]. Lempar [ProviderException]
  /// jika playability bukan OK atau tidak ada stream direct.
  Future<MediaInfo> _fetchWithClient(
    String base,
    String videoId,
    _InnertubeClient client,
  ) async {
    late final Response<Map<String, dynamic>> response;
    try {
      response = await httpClient.post<Map<String, dynamic>>(
        '$base?key=$_kAndroidKey&prettyPrint=false',
        data: {
          'context': {
            'client': {
              'clientName': client.name,
              'clientVersion': client.version,
              if (client.androidSdkVersion != null)
                'androidSdkVersion': client.androidSdkVersion,
              if (client.visitorData != null)
                'visitorData': client.visitorData,
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
            'X-YouTube-Client-Name': client.headerName,
            'X-YouTube-Client-Version': client.version,
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
      throw _playabilityError(status);
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

/// Ambil URL stream direct saja. Format `signatureCipher`/`cipher` butuh
/// decipher JS player yang tidak stabil on-device — URL mentahnya pasti
/// 403, jadi dibuang dan biarkan fallback error yang jelas.
String _extractStreamUrl(Map<String, dynamic> raw) =>
    (raw['url'] ?? '').toString();

/// Filter kualitas YouTube: Mengembalikan format video (1080p, 720p, 480p, 360p)
/// dan Audio MP3. Untuk format adaptif yang belum memiliki audio, pasangkan
/// stream audio dengan kontainer yang cocok via [MediaQuality.audioUrl] agar
/// digabung otomatis (FFmpeg): video mp4 (avc1) -> audio m4a/aac sehingga merge
/// cukup remux copy tanpa encoder; video webm (vp9) -> audio opus.
List<MediaQuality> _filterYouTubeQualities(
    List<Map<String, dynamic>> rawFormats) {
  const targetResolutions = ['1080p', '720p', '480p', '360p'];

  final videoMap = <String, MediaQuality>{};
  MediaQuality? bestAudio;
  String? bestM4aUrl;
  int? bestM4aBytes;
  int bestM4aBitrate = 0;
  String? bestOpusUrl;
  int? bestOpusBytes;
  int bestOpusBitrate = 0;

  // 1. Kumpulkan stream audio terbaik per kontainer (bitrate tertinggi).
  for (final raw in rawFormats) {
    final url = _extractStreamUrl(raw);
    if (url.isEmpty) continue;
    final mime = (raw['mimeType'] ?? '').toString();

    if (mime.startsWith('audio/')) {
      final bitrate = (raw['bitrate'] as num?)?.toInt() ?? 0;
      final contentLength =
          int.tryParse((raw['contentLength'] ?? '').toString());
      if (mime.contains('mp4')) {
        if (bitrate > bestM4aBitrate) {
          bestM4aBitrate = bitrate;
          bestM4aUrl = url;
          bestM4aBytes = contentLength;
        }
      } else {
        if (bitrate > bestOpusBitrate) {
          bestOpusBitrate = bitrate;
          bestOpusUrl = url;
          bestOpusBytes = contentLength;
        }
      }
    }
  }

  // Audio pilihan untuk opsi "Audio MP3": m4a lebih aman (dekoder universal),
  // opus sebagai cadangan.
  if (bestM4aUrl != null || bestOpusUrl != null) {
    bestAudio = MediaQuality(
      label: 'Audio MP3',
      itag: bestM4aUrl ?? bestOpusUrl!,
      extension: 'mp3',
      hasAudio: true,
      sizeBytes: bestM4aUrl != null ? bestM4aBytes : bestOpusBytes,
    );
  }

  // 2. Petakan format video ke resolusi target.
  for (final raw in rawFormats) {
    final url = _extractStreamUrl(raw);
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
          if (existing == null) {
            videoMap[target] = _buildVideoQuality(
              label: target,
              url: url,
              isMp4: isMp4,
              hasAudio: hasAudio,
              videoBytes: videoBytes,
              bestM4aUrl: bestM4aUrl,
              bestM4aBytes: bestM4aBytes,
              bestOpusUrl: bestOpusUrl,
              bestOpusBytes: bestOpusBytes,
            );
          } else if (!(existing.hasAudio ?? false)) {
            // Utamakan muxed; lalu mp4 (remux copy) di atas webm.
            final existingIsMp4 = existing.extension == 'mp4';
            if (hasAudio || (isMp4 && !existingIsMp4)) {
              videoMap[target] = _buildVideoQuality(
                label: target,
                url: url,
                isMp4: isMp4,
                hasAudio: hasAudio,
                videoBytes: videoBytes,
                bestM4aUrl: bestM4aUrl,
                bestM4aBytes: bestM4aBytes,
                bestOpusUrl: bestOpusUrl,
                bestOpusBytes: bestOpusBytes,
              );
            }
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
      final url = _extractStreamUrl(raw);
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
          audioUrl: hasAudio ? null : bestM4aUrl ?? bestOpusUrl,
        ));
        break;
      }
    }
  }

  // Tambahkan Audio MP3
  if (bestAudio != null) {
    result.add(bestAudio);
  } else if (result.isNotEmpty) {
    final videoWithAudio = result.firstWhere(
      (v) => v.hasAudio ?? false,
      orElse: () => result.first,
    );
    result.add(MediaQuality(
      label: 'Audio MP3',
      itag: videoWithAudio.itag,
      extension: 'mp3',
      hasAudio: true,
    ));
  }

  return result;
}

/// Bangun satu kualitas video (muxed atau pasangan adaptif).
MediaQuality _buildVideoQuality({
  required String label,
  required String url,
  required bool isMp4,
  required bool hasAudio,
  required int? videoBytes,
  required String? bestM4aUrl,
  required int? bestM4aBytes,
  required String? bestOpusUrl,
  required int? bestOpusBytes,
}) {
  // Pasangkan audio dengan kontainer yang cocok: mp4 -> m4a (remux copy),
  // webm -> opus. M4a juga cadangan untuk webm bila opus tidak ada.
  final audioUrl = hasAudio
      ? null
      : (isMp4 ? (bestM4aUrl ?? bestOpusUrl) : (bestOpusUrl ?? bestM4aUrl));
  final audioBytes =
      isMp4 ? (bestM4aBytes ?? bestOpusBytes) : (bestOpusBytes ?? bestM4aBytes);
  final totalBytes =
      videoBytes != null ? videoBytes + (hasAudio ? 0 : (audioBytes ?? 0)) : null;

  return MediaQuality(
    label: label,
    itag: url,
    extension: isMp4 ? 'mp4' : 'webm',
    hasAudio: hasAudio,
    audioUrl: audioUrl,
    sizeBytes: totalBytes,
  );
}
