// TikTok Provider — ditulis ulang clean-room, bukan copy dari repo mana pun.
//
// Status verifikasi E2E 2026-10-14 dengan link asli:
// - PRIMARY tikdownloader.io/api/ajaxSearch: VERIFIED. Respons {status:ok,
//   data: HTML} berisi <h3>judul</h3> + link snapcdn (tombol utama) + link
//   mp4 langsung. Contoh judul mengandung entity HTML (&#x1F639;) → di-decode.
// - FALLBACK tikwm GET api/?url=: VERIFIED. Respons {code:0,
//   data:{title, author{nickname}, cover, play, wmplay, music, duration}}.
// - tiktokio.com/api/v1/tk-htmx: MATI (404 pada 2026-10-14) — tidak dipakai.

import 'dart:convert';
import 'package:dio/dio.dart';
import '../../core/network/api_client.dart';
import 'provider.dart';
import 'models.dart';
import 'remote_config.dart';

const _kPrimaryId = 'tiktok_primary';
const _kFallbackId = 'tiktok_fallback';

String _cleanTikTokUrl(String url) {
  final trimmed = url.trim();
  final uri = Uri.tryParse(trimmed);
  if (uri == null || uri.host.isEmpty) return trimmed;
  return Uri(
    scheme: uri.scheme.isEmpty ? 'https' : uri.scheme,
    userInfo: uri.userInfo.isEmpty ? null : uri.userInfo,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: uri.path,
  ).toString();
}

bool _canHandleTikTok(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  return uri.host.toLowerCase().contains('tiktok.com');
}

Map<String, dynamic> _parseMapResponse(dynamic data) {
  if (data == null) return <String, dynamic>{};
  if (data is Map<String, dynamic>) return data;
  if (data is Map) return data.cast<String, dynamic>();
  if (data is String && data.trim().isNotEmpty) {
    try {
      final decoded = jsonDecode(data);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return decoded.cast<String, dynamic>();
    } catch (_) {}
  }
  return <String, dynamic>{};
}

/// POST form dengan error jaringan dibungkus ProviderException.
Future<Map<String, dynamic>> _postJson(
  String url, {
  Object? data,
  Options? options,
}) async {
  try {
    final response = await httpClient.post<dynamic>(
      url,
      data: data,
      options: options,
    );
    return _parseMapResponse(response.data);
  } on ProviderException {
    rethrow;
  } on DioException catch (e) {
    throw ProviderException(
      message: 'endpoint TikTok tidak merespons (${e.type.name})',
      kind: ProviderErrorKind.providerDown,
      underlyingError: e,
    );
  } catch (e) {
    throw ProviderException(
      message: 'gagal memproses respons TikTok: $e',
      kind: ProviderErrorKind.providerDown,
      underlyingError: e,
    );
  }
}

/// GET JSON dengan error jaringan dibungkus ProviderException.
Future<Map<String, dynamic>> _getJson(
  String url, {
  Map<String, dynamic>? query,
}) async {
  try {
    final response = await httpClient.get<dynamic>(
      url,
      queryParameters: query,
      options: Options(responseType: ResponseType.json),
    );
    return _parseMapResponse(response.data);
  } on ProviderException {
    rethrow;
  } on DioException catch (e) {
    throw ProviderException(
      message: 'endpoint TikTok tidak merespons (${e.type.name})',
      kind: ProviderErrorKind.providerDown,
      underlyingError: e,
    );
  } catch (e) {
    throw ProviderException(
      message: 'gagal memproses respons TikTok: $e',
      kind: ProviderErrorKind.providerDown,
      underlyingError: e,
    );
  }
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
      .firstWhere((q) => q.itag == quality,
          orElse: () => info.qualities.first)
      .itag;
}

/// Decode entity HTML (&#x1F639; &#39; &amp; &lt; &gt; &quot;).
/// Judul dari scraper pihak ketiga sering masih ter-encode.
String _unescapeHtml(String s) {
  const named = {
    'amp': '&',
    'lt': '<',
    'gt': '>',
    'quot': '"',
    'apos': "'",
  };
  return s.replaceAllMapped(
    RegExp(r'&(#x[0-9a-fA-F]+|#\d+|\w+);'),
    (m) {
      final body = m.group(1)!;
      if (body.startsWith('#x') || body.startsWith('#X')) {
        final cp = int.tryParse(body.substring(2), radix: 16);
        if (cp != null) return String.fromCharCode(cp);
      } else if (body.startsWith('#')) {
        final cp = int.tryParse(body.substring(1));
        if (cp != null) return String.fromCharCode(cp);
      }
      return named[body] ?? m.group(0)!;
    },
  );
}

class TikTokPrimaryProvider implements MediaProvider {
  @override
  String get providerName => 'TikDownloader';

  @override
  bool canHandle(String url) => _canHandleTikTok(url);

  @override
  Future<MediaInfo> fetchInfo(String url) async {
    final cfg = await RemoteConfig.instance.get(_kPrimaryId);
    if (cfg == null || !cfg.enabled) {
      throw const ProviderException(
        message: 'Primary TikTok provider disabled.',
        kind: ProviderErrorKind.providerDown,
      );
    }
    final cleanUrl = _cleanTikTokUrl(url);

    final response = await _postJson(
      cfg.url,
      data: 'q=${Uri.encodeComponent(cleanUrl)}&lang=en',
      options: Options(
        contentType: 'application/x-www-form-urlencoded',
        headers: {'Referer': 'https://tikdownloader.io/'},
      ),
    );

    final body = response;
    if (body['status'] != 'ok') {
      throw ProviderException(
        message: 'tikdownloader.io: ${body['message'] ?? 'gagal memproses'}',
        kind: ProviderErrorKind.noResult,
      );
    }

    // Parse HTML response — link ada di atribut href, urutan dokumen
    // dipertahankan (link tombol utama = snapcdn dulu).
    final html = (body['data'] as String? ?? '');
    final links = _extractLinks(html);
    if (links.isEmpty) {
      throw const ProviderException(
        message: 'Tidak ada link ditemukan di respons tikdownloader.',
        kind: ProviderErrorKind.noResult,
      );
    }

    // Extract title dari HTML jika ada (masih ter-encode → decode).
    final titleMatch = RegExp(r'<h3[^>]*>([^<]+)<\/h3>').firstMatch(html);
    final rawTitle = titleMatch?.group(1)?.trim() ?? '';
    final audioLink = _extractAudioLink(html);

    return MediaInfo(
      title: rawTitle.isEmpty ? 'TikTok Video' : _unescapeHtml(rawTitle),
      author: 'TikTok',
      thumbnail: null,
      durationSec: null,
      qualities: [
        MediaQuality(label: 'HD (No Watermark)', itag: links.first),
        for (final extra in links.skip(1))
          MediaQuality(label: 'Video (alt)', itag: extra),
        MediaQuality(
          label: 'Audio MP3',
          itag: audioLink ?? links.first,
          extension: 'mp3',
          hasAudio: true,
        ),
      ],
      source: 'third-party',
      providerName: providerName,
    );
  }

  @override
  Future<String> fetchDownloadUrl(String url, {String quality = 'best'}) async =>
      _resolveQuality(await fetchInfo(url), quality);

  String? _extractAudioLink(String html) {
    final pattern = RegExp(
      r'href="([^"]*(?:\.mp3|snapcdn\.app/get[^"]*type=audio)[^"]*)"',
      caseSensitive: false,
    );
    for (final m in pattern.allMatches(html)) {
      final link = m.group(1);
      if (link != null && link.startsWith('http')) {
        return link;
      }
    }
    return null;
  }

  List<String> _extractLinks(String html) {
    final pattern =
        RegExp(r'href="(https://[^"]*(?:\.mp4|snapcdn\.app/get)[^"]*)"');
    return pattern
        .allMatches(html)
        .map((m) => m.group(1)!)
        .where((l) => l.isNotEmpty)
        .toList();
  }
}

class TikWmProvider implements MediaProvider {
  @override
  String get providerName => 'TikWm';

  @override
  bool canHandle(String url) => _canHandleTikTok(url);

  @override
  Future<MediaInfo> fetchInfo(String url) async {
    final cfg = await RemoteConfig.instance.get(_kFallbackId);
    if (cfg == null || !cfg.enabled) {
      throw const ProviderException(
        message: 'Fallback TikTok provider disabled.',
        kind: ProviderErrorKind.providerDown,
      );
    }

    final cleanUrl = _cleanTikTokUrl(url);
    final response = await _getJson(cfg.url, query: {'url': cleanUrl});

    final body = response;
    if (body['code'] != 0 || body['data'] is! Map) {
      throw ProviderException(
        message: 'tikwm: ${body['msg'] ?? 'gagal memproses'}',
        kind: ProviderErrorKind.noResult,
      );
    }
    final data = (body['data'] as Map).cast<String, dynamic>();

    final play = (data['play'] ?? '').toString();
    final wmplay = (data['wmplay'] ?? '').toString();
    final music = (data['music'] ?? '').toString();
    if (play.isEmpty && wmplay.isEmpty && music.isEmpty) {
      throw const ProviderException(
        message: 'tikwm: tidak ada URL media.',
        kind: ProviderErrorKind.noResult,
      );
    }
    final author = data['author'];
    final nickname =
        author is Map ? (author['nickname'] ?? '').toString() : '';
    final duration = data['duration'];

    String toFullUrl(String url) =>
        url.startsWith('http') ? url : 'https://www.tikwm.com$url';

    final audioUrl = music.isNotEmpty
        ? toFullUrl(music)
        : (play.isNotEmpty ? toFullUrl(play) : null);

    return MediaInfo(
      title: (data['title'] ?? 'TikTok Video').toString(),
      author: nickname.isEmpty ? 'TikTok' : nickname,
      thumbnail: data['cover'] as String?,
      durationSec: duration is num ? duration.toInt() : null,
      qualities: [
        if (play.isNotEmpty)
          MediaQuality(label: 'HD (No Watermark)', itag: toFullUrl(play)),
        if (wmplay.isNotEmpty)
          MediaQuality(label: 'SD (Watermark)', itag: toFullUrl(wmplay)),
        if (audioUrl != null)
          MediaQuality(
            label: 'Audio MP3',
            itag: audioUrl,
            extension: 'mp3',
            hasAudio: true,
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

/// Tertiary TikTok provider — SnapTik minimal POST API.
/// Parses JSON {error:false, data: [...]} berisi link download.
const _kTertiaryId = 'tiktok_tertiary';

class SnapTikProvider implements MediaProvider {
  @override
  String get providerName => 'SnapTik';

  @override
  bool canHandle(String url) => _canHandleTikTok(url);

  @override
  Future<MediaInfo> fetchInfo(String url) async {
    final cfg = await RemoteConfig.instance.get(_kTertiaryId);
    if (cfg == null || !cfg.enabled) {
      throw const ProviderException(
        message: 'Tertiary TikTok provider disabled.',
        kind: ProviderErrorKind.providerDown,
      );
    }
    final cleanUrl = _cleanTikTokUrl(url);
    final response = await _postJson(
      cfg.url,
      data: 'url=${Uri.encodeComponent(cleanUrl)}&lang=en&token=',
      options: Options(
        contentType: 'application/x-www-form-urlencoded',
        headers: {
          'Referer': 'https://snaptik.app/',
          'Origin': 'https://snaptik.app',
        },
      ),
    );

    // SnapTik returns either {error:false, data:[...]} or HTML script
    final dataField = response['data'];
    final List<dynamic> items = dataField is List
        ? dataField
        : dataField is String
            ? _parseSnapTikScript(dataField)
            : [];

    // Filter for HD (no watermark) and audio links
    final videoLinks = <String>[];
    String? audioLink;
    for (final item in items) {
      if (item is Map) {
        final href = (item['url'] ?? item['src'] ?? '').toString();
        if (href.isEmpty || !href.startsWith('http')) continue;
        final label = (item['label'] ?? item['type'] ?? '').toString().toLowerCase();
        if (label.contains('hd') || label.contains('no watermark') || label.isEmpty) {
          videoLinks.add(href);
        } else if (label.contains('mp3') || label.contains('audio') || label.contains('music')) {
          audioLink ??= href;
        }
      } else if (item is String && item.startsWith('http')) {
        videoLinks.add(item);
      }
    }

    // Fallback: parse HTML from script if data field is a script string
    if (videoLinks.isEmpty && response['data'] is String) {
      final parsed = _parseSnapTikScript(response['data'] as String);
      for (final link in parsed) {
        if (link is String && link.startsWith('http')) {
          videoLinks.add(link);
        }
      }
    }

    if (videoLinks.isEmpty && audioLink == null) {
      throw const ProviderException(
        message: 'snaptik: tidak ada link media ditemukan.',
        kind: ProviderErrorKind.noResult,
      );
    }

    final title = response['title']?.toString() ?? 'TikTok Video';
    final qualities = <MediaQuality>[
      if (videoLinks.isNotEmpty)
        MediaQuality(label: 'HD (No Watermark)', itag: videoLinks.first),
      for (final extra in videoLinks.skip(1))
        MediaQuality(label: 'Video (alt)', itag: extra),
      if (audioLink != null)
        MediaQuality(
          label: 'Audio MP3',
          itag: audioLink,
          extension: 'mp3',
          hasAudio: true,
        )
      else if (videoLinks.isNotEmpty)
        MediaQuality(
          label: 'Audio MP3',
          itag: videoLinks.first,
          extension: 'mp3',
          hasAudio: true,
        ),
    ];

    return MediaInfo(
      title: title,
      author: 'TikTok',
      thumbnail: null,
      durationSec: null,
      qualities: qualities,
      source: 'third-party',
      providerName: providerName,
    );
  }

  /// Parse JavaScript-embedded links from SnapTik HTML response.
  List<dynamic> _parseSnapTikScript(String script) {
    final links = <String>[];
    // Match href or src attributes with video/download URLs
    final pattern = RegExp(
      r'''(?:href|src|url)\s*[=:]\s*["']?(https://[^"'\s,>]+\.(?:mp4|m4a|mp3)[^"'\s,>]*)''',
      caseSensitive: false,
    );
    for (final m in pattern.allMatches(script)) {
      final link = m.group(1);
      if (link != null && !links.contains(link)) {
        links.add(link);
      }
    }
    return links;
  }

  @override
  Future<String> fetchDownloadUrl(String url, {String quality = 'best'}) async =>
      _resolveQuality(await fetchInfo(url), quality);
}
