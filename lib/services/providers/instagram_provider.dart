import 'dart:convert';
import 'package:dio/dio.dart';
import '../../core/network/api_client.dart';
import 'provider.dart';
import 'models.dart';
import 'remote_config.dart';

const _kPrimaryId = 'instagram_primary';
const _kFallbackId = 'instagram_fallback';

bool _canHandleInstagram(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  return uri.host.toLowerCase().contains('instagram.com');
}

/// Bentuk kanonis URL Instagram untuk POST: buang query tracking
/// (utm_*, psln, exln, si) dan fragment. Kanonis cukup untuk resolve
/// dan menghilangkan permukaan gagal dari parameter tracking.
String _canonicalUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.host.isEmpty) return url;
  return Uri(scheme: uri.scheme, host: uri.host, path: uri.path).toString();
}

/// Decoder untuk script ter-obfuscate SnapSave (Dean Edwards / Hunter packer).
String? decodeSnapSave(String script) {
  final evalMatch = RegExp(
    r'eval\(function\(h,u,n,t,e,r\)\{.*?\}\((.*?)\)\)',
    dotAll: true,
  ).firstMatch(script);
  if (evalMatch == null) return null;

  final argsRaw = evalMatch.group(1);
  if (argsRaw == null) return null;

  final argMatch = RegExp(
    r'"(.*?)",\s*(\d+),\s*"(.*?)",\s*(\d+),\s*(\d+),\s*(\d+)',
    dotAll: true,
  ).firstMatch(argsRaw);
  if (argMatch == null) return null;

  final h = argMatch.group(1)!;
  final n = argMatch.group(3)!;
  final t = int.parse(argMatch.group(4)!);
  final e = int.parse(argMatch.group(5)!);

  const charset =
      '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ+/';
  if (e >= n.length) return null;
  final delimiter = n[e];
  final chunks = h.split(delimiter);
  final byteValues = <int>[];

  for (final chunk in chunks) {
    if (chunk.isEmpty) continue;
    var s = chunk;
    for (var j = 0; j < n.length; j++) {
      s = s.replaceAll(n[j], j.toString());
    }
    var val = 0;
    final chars = s.split('').reversed.toList();
    var power = 1;
    for (final char in chars) {
      final idx = charset.substring(0, e).indexOf(char);
      if (idx != -1) {
        val += idx * power;
      }
      power *= e;
    }
    byteValues.add(val - t);
  }

  return utf8.decode(byteValues, allowMalformed: true);
}

/// Ambil URL unduhan dari HTML dengan beberapa varian markup.
List<String> _extractLinks(String html, String mustContain) {
  final urls = <String>[];
  final seen = <String>{};
  void add(String? u) {
    final v = (u ?? '').replaceAll(r'\/', '/');
    if (v.startsWith('http') && v.contains(mustContain) && seen.add(v)) {
      urls.add(v);
    }
  }

  final q = String.fromCharCode(34);
  final qs = String.fromCharCode(39);
  final hrefPat = RegExp('href=[$q$qs]([^$q$qs]+)[$q$qs]');
  final dataPat = RegExp('data-(?:url|href)=[$q$qs]([^$q$qs]+)[$q$qs]');
  final jsonPat = RegExp('[$q$qs]contentUrl[$q$qs]\\s*:\\s*[$q$qs]([^$q$qs]+)[$q$qs]');
  for (final m in hrefPat.allMatches(html)) {
    add(m.group(1));
  }
  for (final m in dataPat.allMatches(html)) {
    add(m.group(1));
  }
  for (final m in jsonPat.allMatches(html)) {
    add(m.group(1));
  }
  return urls;
}

Future<String> _getPlain(String url) async {
  try {
    final res = await httpClient.get<String>(
      url,
      options: Options(responseType: ResponseType.plain),
    );
    return res.data ?? '';
  } on DioException catch (e) {
    throw ProviderException(
      message: 'endpoint Instagram tidak merespons (${e.type.name})',
      kind: ProviderErrorKind.providerDown,
      underlyingError: e,
    );
  }
}

Future<String> _postForm(
  String url,
  Map<String, String> fields, {
  String? referer,
}) async {
  try {
    final headers = <String, String>{};
    if (referer != null) {
      headers['Referer'] = referer;
      headers['Origin'] = Uri.parse(referer).origin;
    }
    final res = await httpClient.post<String>(
      url,
      data: fields,
      options: Options(
        responseType: ResponseType.plain,
        contentType: Headers.formUrlEncodedContentType,
        headers: headers,
      ),
    );
    return res.data ?? '';
  } on DioException catch (e) {
    throw ProviderException(
      message: 'endpoint Instagram tidak merespons (${e.type.name})',
      kind: ProviderErrorKind.providerDown,
      underlyingError: e,
    );
  }
}

/// Petunjuk diagnostik: judul halaman (dipotong) bila ada.
String _pageHint(String html) {
  final m = RegExp(r'<title[^>]*>([^<]{1,80})').firstMatch(html);
  final title = m?.group(1)?.trim() ?? '';
  return title.isEmpty ? '' : ' (halaman: "$title")';
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

class InstagramPrimaryProvider implements MediaProvider {
  @override
  String get providerName => 'InDown';

  @override
  bool canHandle(String url) => _canHandleInstagram(url);

  @override
  Future<MediaInfo> fetchInfo(String url) async {
    final cfg = await RemoteConfig.instance.get(_kPrimaryId);
    if (cfg == null || !cfg.enabled) {
      throw const ProviderException(
        message: 'Primary Instagram provider disabled.',
        kind: ProviderErrorKind.providerDown,
      );
    }

    final tokenPage = cfg.url;
    final page = await _getPlain(tokenPage);
    final token =
        RegExp(r'name="_token" value="([^"]+)"').firstMatch(page)?.group(1);
    if (token == null || token.isEmpty) {
      throw const ProviderException(
        message: 'indown: token sesi tidak ditemukan.',
        kind: ProviderErrorKind.providerDown,
      );
    }

    final origin = Uri.parse(tokenPage).origin;
    final html = await _postForm(
      '$origin/download',
      {
        'referer': tokenPage,
        'locale': 'en',
        '_token': token,
        'link': _canonicalUrl(url),
      },
      referer: tokenPage,
    );

    final fetchLinks = _extractLinks(html, 'indown.io/fetch?');
    final directLinks = [
      ..._extractLinks(html, '.mp4'),
      ..._extractLinks(html, '.jpg'),
      ..._extractLinks(html, '.jpeg'),
      ..._extractLinks(html, '.png'),
      ..._extractLinks(html, '.heic'),
      ..._extractLinks(html, 'cdninstagram.com'),
    ].where((l) => !l.contains('indown.io')).toSet().toList();

    if (fetchLinks.isEmpty && directLinks.isEmpty) {
      throw ProviderException(
        message:
            'indown: tidak ada link unduhan ditemukan${_pageHint(html)}.',
        kind: ProviderErrorKind.noResult,
      );
    }

    return MediaInfo(
      title: 'Instagram Media',
      author: 'Instagram',
      thumbnail: null,
      durationSec: null,
      qualities: [
        for (final link in fetchLinks)
          MediaQuality(label: 'Video HD', itag: link),
        for (final link in directLinks)
          MediaQuality(
            label: 'Video (direct)',
            itag: link,
            extension: link.contains('.mp4') ? 'mp4' : 'jpg',
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

class InstagramFallbackProvider implements MediaProvider {
  @override
  String get providerName => 'SnapSave';

  @override
  bool canHandle(String url) => _canHandleInstagram(url);

  @override
  Future<MediaInfo> fetchInfo(String url) async {
    final cfg = await RemoteConfig.instance.get(_kFallbackId);
    if (cfg == null || !cfg.enabled) {
      throw const ProviderException(
        message: 'Fallback Instagram provider disabled.',
        kind: ProviderErrorKind.providerDown,
      );
    }

    final raw = await _postForm(
      cfg.url,
      {'url': _canonicalUrl(url)},
      referer: 'https://snapsave.app/',
    );

    // Unpack hunter script jika ada, atau gunakan raw jika plain HTML (misal di test)
    final decoded = decodeSnapSave(raw) ?? raw;

    final qualities = <MediaQuality>[];
    final seen = <String>{};
    String? thumbnail;

    // Ambil thumbnail dari download-items__thumb atau img src
    final thumbMatch = RegExp(
      r'<div[^>]*class=\\?"download-items__thumb\\?"[^>]*>.*?<img[^>]*src=\\?"([^"\\]+)\\?"',
      dotAll: true,
    ).firstMatch(decoded);
    thumbnail = thumbMatch?.group(1);
    if (thumbnail == null) {
      final anyImg = RegExp(r'<img[^>]*src=\\?"(https?://[^"\\]+)\\?"')
          .firstMatch(decoded);
      thumbnail = anyImg?.group(1);
    }

    // Ekstrak item terstruktur (video / foto carousel)
    final itemBlocks = RegExp(
      r'<div[^>]*class=\\?"download-items\\?"[^>]*>(.*?)</div>\s*</div>',
      dotAll: true,
    ).allMatches(decoded);

    if (itemBlocks.isNotEmpty) {
      var itemIndex = 1;
      for (final block in itemBlocks) {
        final blockContent = block.group(1) ?? '';
        final isVideo = blockContent.contains('icon-dlvideo') ||
            blockContent.contains('.mp4');
        final hrefMatch =
            RegExp(r'href=\\?"([^"\\]+)\\?"').firstMatch(blockContent);
        if (hrefMatch != null) {
          final link = hrefMatch.group(1)!;
          if (link.startsWith('http') &&
              !link.contains('play.google.com') &&
              seen.add(link)) {
            final label = itemBlocks.length == 1
                ? (isVideo ? 'Video HD' : 'Photo HD')
                : (isVideo ? 'Video $itemIndex' : 'Photo $itemIndex');
            qualities.add(MediaQuality(
              label: label,
              itag: link,
              extension: isVideo ? 'mp4' : 'jpg',
            ));
            itemIndex++;
          }
        }
      }
    }

    // Jika blok spesifik tidak ada, fallback ke pencarian regex href
    if (qualities.isEmpty) {
      final hrefMatches = RegExp(r'href=\\?"([^"\\]+)\\?"').allMatches(decoded);
      var idx = 1;
      for (final m in hrefMatches) {
        final link = m.group(1)!;
        if (link.startsWith('http') &&
            !link.contains('play.google.com') &&
            (link.contains('rapidcdn.app') ||
                link.contains('.mp4') ||
                link.contains('cdninstagram')) &&
            seen.add(link)) {
          final isVideo =
              link.contains('.mp4') || decoded.contains('icon-dlvideo');
          qualities.add(MediaQuality(
            label: idx == 1
                ? (isVideo ? 'Video HD' : 'Media HD')
                : (isVideo ? 'Video (alt)' : 'Media $idx'),
            itag: link,
            extension: isVideo ? 'mp4' : 'jpg',
          ));
          idx++;
        }
      }
    }

    if (qualities.isEmpty) {
      throw const ProviderException(
        message: 'snapsave: tidak ada link ditemukan.',
        kind: ProviderErrorKind.noResult,
      );
    }

    final hasVideo = qualities.any((q) => q.extension == 'mp4');
    return MediaInfo(
      title: hasVideo ? 'Instagram Video' : 'Instagram Photo',
      author: 'Instagram',
      thumbnail: thumbnail,
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


