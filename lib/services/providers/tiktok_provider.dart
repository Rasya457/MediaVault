// TikTok Provider — ditulis ulang clean-room, bukan copy dari repo mana pun.
//
// Status verifikasi E2E 2026-10-14 dengan link asli:
// - PRIMARY tikdownloader.io/api/ajaxSearch: VERIFIED. Respons {status:ok,
//   data: HTML} berisi <h3>judul</h3> + link snapcdn (tombol utama) + link
//   mp4 langsung. Contoh judul mengandung entity HTML (&#x1F639;) → di-decode.
// - FALLBACK tikwm GET api/?url=: VERIFIED. Respons {code:0,
//   data:{title, author{nickname}, cover, play, wmplay, music, duration}}.
// - tiktokio.com/api/v1/tk-htmx: MATI (404 pada 2026-10-14) — tidak dipakai.

import 'package:dio/dio.dart';
import '../../core/network/api_client.dart';
import 'provider.dart';
import 'models.dart';
import 'remote_config.dart';

const _kPrimaryId = 'tiktok_primary';
const _kFallbackId = 'tiktok_fallback';

bool _canHandleTikTok(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  return uri.host.toLowerCase().contains('tiktok.com');
}

/// POST form dengan error jaringan dibungkus ProviderException.
Future<Response<Map<String, dynamic>>> _postJson(
  String url, {
  Object? data,
  Options? options,
}) async {
  try {
    return await httpClient.post<Map<String, dynamic>>(
      url,
      data: data,
      options: options,
    );
  } on DioException catch (e) {
    throw ProviderException(
      message: 'endpoint TikTok tidak merespons (${e.type.name})',
      kind: ProviderErrorKind.providerDown,
      underlyingError: e,
    );
  }
}

/// GET JSON dengan error jaringan dibungkus ProviderException.
Future<Response<Map<String, dynamic>>> _getJson(
  String url, {
  Map<String, dynamic>? query,
}) async {
  try {
    return await httpClient.get<Map<String, dynamic>>(
      url,
      queryParameters: query,
      options: Options(responseType: ResponseType.json),
    );
  } on DioException catch (e) {
    throw ProviderException(
      message: 'endpoint TikTok tidak merespons (${e.type.name})',
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

    final response = await _postJson(
      cfg.url,
      data: 'q=${Uri.encodeComponent(url)}&lang=en',
      options: Options(
        contentType: 'application/x-www-form-urlencoded',
        headers: {'Referer': 'https://tikdownloader.io/'},
      ),
    );

    final body = response.data ?? {};
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

    return MediaInfo(
      title: rawTitle.isEmpty ? 'TikTok Video' : _unescapeHtml(rawTitle),
      author: 'TikTok',
      thumbnail: null,
      durationSec: null,
      qualities: [
        MediaQuality(label: 'HD (No Watermark)', itag: links.first),
        for (final extra in links.skip(1))
          MediaQuality(label: 'Video (alt)', itag: extra),
      ],
      source: 'third-party',
      providerName: providerName,
    );
  }

  @override
  Future<String> fetchDownloadUrl(String url, {String quality = 'best'}) async =>
      _resolveQuality(await fetchInfo(url), quality);

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

    final response = await _getJson(cfg.url, query: {'url': url});

    final body = response.data ?? {};
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

    return MediaInfo(
      title: (data['title'] ?? 'TikTok Video').toString(),
      author: nickname.isEmpty ? 'TikTok' : nickname,
      thumbnail: data['cover'] as String?,
      durationSec: duration is num ? duration.toInt() : null,
      qualities: [
        if (play.isNotEmpty)
          MediaQuality(label: 'HD (No Watermark)', itag: play),
        if (wmplay.isNotEmpty)
          MediaQuality(label: 'SD (Watermark)', itag: wmplay),
        if (music.isNotEmpty)
          MediaQuality(
            label: 'Audio MP3',
            itag: music,
            extension: 'mp3',
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
