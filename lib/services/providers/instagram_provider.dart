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
      .firstWhere((q) => q.itag == quality || q.label == quality,
          orElse: () => info.qualities.first)
      .itag;
}

/// Label unik untuk daftar link sejenis: satu item -> [single],
/// banyak item -> "$single 1", "$single 2", ...
String _numbered(String single, int index, int total) =>
    total <= 1 ? single : '$single $index';

/// Tebak ekstensi dari URL unduhan Instagram.
String _guessExtension(String url) {
  final lower = url.toLowerCase();
  if (lower.contains('.mp4')) return 'mp4';
  if (lower.contains('.jpg') || lower.contains('.jpeg')) return 'jpg';
  if (lower.contains('.png')) return 'png';
  if (lower.contains('.heic')) return 'heic';
  if (lower.contains('.webp')) return 'webp';
  if (lower.contains('cdninstagram.com')) return 'jpg';
  return 'mp4';
}

/// Tebak foto vs video dari URL, termasuk sniff payload JWT
/// (pola referensi: token=header.payload.sig berisi ekstensi asli).
bool _isPhotoUrl(String url) {
  final lower = url.toLowerCase();
  if (lower.contains('.mp4') ||
      lower.contains('.mov') ||
      lower.contains('.webm') ||
      lower.contains('.mkv')) {
    return false;
  }
  if (lower.contains('.jpg') ||
      lower.contains('.jpeg') ||
      lower.contains('.png') ||
      lower.contains('.webp') ||
      lower.contains('.heic')) {
    return true;
  }
  try {
    final tokenMatch = RegExp(r'token=([A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+)')
        .firstMatch(url);
    if (tokenMatch != null) {
      var payload = tokenMatch.group(1)!.split('.')[1]
          .replaceAll('-', '+')
          .replaceAll('_', '/');
      payload = payload.padRight(
        payload.length + (4 - payload.length % 4) % 4, '=');
      final decoded = utf8.decode(base64.decode(payload), allowMalformed: true);
      if (RegExp(r'\.(jpe?g|png|webp)(\?|"|$)').hasMatch(decoded)) {
        return true;
      }
      if (RegExp(r'\.(mp4|mov|webm|mkv)(\?|"|$)').hasMatch(decoded)) {
        return false;
      }
    }
  } catch (_) {}
  // Default: video (link unduhan IG mayoritas MP4).
  return false;
}

/// Judul dari path URL: reel/ID -> "Instagram Reel (ID)".
String _instagramTitle(String url) {
  final uri = Uri.tryParse(url);
  final segs = uri?.pathSegments.where((s) => s.isNotEmpty).toList() ?? [];
  String kind = 'Post';
  String id = '';
  for (var i = 0; i < segs.length; i++) {
    final s = segs[i].toLowerCase();
    if (s == 'reel' || s == 'reels') {
      kind = 'Reel';
      if (i + 1 < segs.length) id = segs[i + 1];
    } else if (s == 'p') {
      kind = 'Post';
      if (i + 1 < segs.length) id = segs[i + 1];
    } else if (s == 'tv') {
      kind = 'Video';
      if (i + 1 < segs.length) id = segs[i + 1];
    } else if (s == 'stories') {
      kind = 'Story';
    }
  }
  return id.isEmpty ? 'Instagram $kind' : 'Instagram $kind ($id)';
}

class InstagramPrimaryProvider implements MediaProvider {
  @override
  String get providerName => 'InDown';

  @override
  bool canHandle(String url) => _canHandleInstagram(url);

  /// Alur indown.net (pola referensi coflyn/Mori "indown"): POST ajaxSearch
  /// form {q, vt:reel, t:media, lang:en, v:v2}, respons JSON {data: html},
  /// lalu parse kotak unduhan per item carousel. Ditulis ulang dalam Dart.
  @override
  Future<MediaInfo> fetchInfo(String url) async {
    final cfg = await RemoteConfig.instance.get(_kPrimaryId);
    if (cfg == null || !cfg.enabled) {
      throw const ProviderException(
        message: 'Primary Instagram provider disabled.',
        kind: ProviderErrorKind.providerDown,
      );
    }

    final canonical = _canonicalUrl(url);
    late final Map<String, dynamic> body;
    try {
      final res = await httpClient.post<Map<String, dynamic>>(
        cfg.url,
        data: {
          'q': canonical,
          'vt': 'reel',
          't': 'media',
          'lang': 'en',
          'v': 'v2',
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: {
            'X-Requested-With': 'XMLHttpRequest',
            'Origin': 'https://indown.net',
            'Referer': 'https://indown.net/',
          },
        ),
      );
      body = res.data ?? {};
    } on DioException catch (e) {
      throw ProviderException(
        message: 'endpoint Instagram tidak merespons (${e.type.name})',
        kind: ProviderErrorKind.providerDown,
        underlyingError: e,
      );
    }

    final html = (body['data'] ?? '').toString();
    if (html.isEmpty) {
      throw ProviderException(
        message: 'indown: ${(body['message'] ?? 'tidak ada hasil')}. '
            'Postingan mungkin privat.',
        kind: ProviderErrorKind.noResult,
      );
    }

    final qualities = _parseIndownItems(html);
    if (qualities.isEmpty) {
      throw ProviderException(
        message: 'indown: tidak ada link unduhan ditemukan${_pageHint(html)}.',
        kind: ProviderErrorKind.noResult,
      );
    }

    return MediaInfo(
      title: _instagramTitle(url),
      author: 'Instagram',
      thumbnail: _firstThumbnail(html, qualities),
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

/// Parse hasil indown: kumpulkan semua link unduhan sesuai urutan dokumen,
/// klasifikasikan foto vs video per link. Tiap link = satu item carousel;
/// label dinomori agar tidak kembar di pemilih kualitas.
List<MediaQuality> _parseIndownItems(String html) {
  final qualities = <MediaQuality>[];
  final seen = <String>{};

  bool accept(String link) {
    if (!link.startsWith('http') || !seen.add(link)) return false;
    if (link.contains('indown.net/api') ||
        link.contains('facebook.com') ||
        link.contains('ads')) {
      return false;
    }
    final lower = link.toLowerCase();
    return lower.contains('rapidcdn.app') ||
        lower.contains('snapcdn') ||
        lower.contains('cdninstagram') ||
        lower.contains('fbcdn') ||
        lower.contains('.mp4') ||
        lower.contains('.mov') ||
        lower.contains('.jpg') ||
        lower.contains('.jpeg') ||
        lower.contains('.png') ||
        lower.contains('.webp') ||
        lower.contains('token=');
  }

  final links = <String>[];
  for (final m in RegExp('href="([^"]+)"').allMatches(html)) {
    final link = m.group(1)!.replaceAll('&amp;', '&');
    if (accept(link)) links.add(link);
  }
  // Fallback: URL mentah tanpa <a> (JSON / JS).
  if (links.isEmpty) {
    for (final m in RegExp(r'https?://[^\s"<>\\]+').allMatches(html)) {
      final link =
          m.group(0)!.replaceAll(r'\/', '/').replaceAll('&amp;', '&');
      if (accept(link)) links.add(link);
    }
  }

  for (var i = 0; i < links.length; i++) {
    final photo = _isPhotoUrl(links[i]);
    qualities.add(MediaQuality(
      label: photo
          ? _numbered('Foto HD', i + 1, links.length)
          : _numbered('Video HD', i + 1, links.length),
      itag: links[i],
      extension: photo ? _guessExtension(links[i]) : 'mp4',
      hasAudio: photo ? null : true,
    ));
  }

  // Tambahkan opsi Audio MP3 jika konten memiliki video / reel
  final videoQualities =
      qualities.where((q) => q.extension == 'mp4' || (q.hasAudio ?? false)).toList();
  if (videoQualities.isNotEmpty) {
    if (videoQualities.length == 1) {
      qualities.add(MediaQuality(
        label: 'Audio MP3',
        itag: videoQualities.first.itag,
        extension: 'mp3',
        hasAudio: true,
      ));
    } else {
      for (var i = 0; i < videoQualities.length; i++) {
        qualities.add(MediaQuality(
          label: 'Audio MP3 (${i + 1})',
          itag: videoQualities[i].itag,
          extension: 'mp3',
          hasAudio: true,
        ));
      }
    }
  }

  return qualities;
}

/// Thumbnail item pertama: img kotak pertama, fallback URL foto itu sendiri.
String? _firstThumbnail(String html, List<MediaQuality> qualities) {
  final img = RegExp('<img[^>]+src="([^"]+)"').firstMatch(html)?.group(1);
  if (img != null && img.startsWith('http')) return img;
  for (final q in qualities) {
    if (q.extension != 'mp4') return q.itag;
  }
  return null;
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

    final videoQualities =
        qualities.where((q) => q.extension == 'mp4' || (q.hasAudio ?? false)).toList();
    if (videoQualities.isNotEmpty) {
      if (videoQualities.length == 1) {
        qualities.add(MediaQuality(
          label: 'Audio MP3',
          itag: videoQualities.first.itag,
          extension: 'mp3',
          hasAudio: true,
        ));
      } else {
        for (var i = 0; i < videoQualities.length; i++) {
          qualities.add(MediaQuality(
            label: 'Audio MP3 (${i + 1})',
            itag: videoQualities[i].itag,
            extension: 'mp3',
            hasAudio: true,
          ));
        }
      }
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


