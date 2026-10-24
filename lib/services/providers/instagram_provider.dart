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
/// [isPhoto] dipakai sebagai fallback bila ekstensi tidak terbaca dari URL.
String _guessExtension(String url, {bool isPhoto = false}) {
  final lower = url.toLowerCase();
  if (lower.contains('.mp4')) return 'mp4';
  if (lower.contains('.jpg') || lower.contains('.jpeg')) return 'jpg';
  if (lower.contains('.png')) return 'png';
  if (lower.contains('.heic')) return 'heic';
  if (lower.contains('.webp')) return 'webp';
  if (lower.contains('cdninstagram.com')) return 'jpg';
  // Default berdasarkan tipe konten: foto → jpg, video → mp4.
  return isPhoto ? 'jpg' : 'mp4';
}

/// Tentukan video vs foto seperti scraper referensi Mori:
/// 1) teks tombol ("Download Photo/Video") — sinyal terkuat,
/// 2) payload token JWT (berisi nama file asli),
/// 3) ekstensi URL.
/// [text] boleh kosong. Default: video (unduhan IG mayoritas MP4).
/// [tokenDefaultPhoto]: untuk SnapSave — link `/v2?token=` tanpa marker
/// apapun di halaman yang tak punya jejak video = foto (dibuktikan fixture
/// respons nyata SnapSave untuk post foto).
bool _isVideoLink(
  String url,
  String text, {
  bool tokenDefaultPhoto = false,
}) {
  final upper = text.replaceAll(RegExp(r'\s+'), ' ').toUpperCase();
  if (upper.contains('VIDEO') ||
      upper.contains('MP4') ||
      upper.contains('REEL')) {
    return true;
  }
  if (upper.contains('PHOTO') ||
      upper.contains('IMAGE') ||
      upper.contains('GAMBAR') ||
      upper.contains('FOTO')) {
    return false;
  }
  final sniffed = _sniffJwtPayload(url);
  if (sniffed != null) return sniffed == 'video';
  if (RegExp(r'\.(mp4|mov|webm|mkv)([?&]|$)', caseSensitive: false)
      .hasMatch(url)) {
    return true;
  }
  if (RegExp(r'\.(jpe?g|png|webp|heic)([?&]|$)', caseSensitive: false)
      .hasMatch(url)) {
    return false;
  }
  if (tokenDefaultPhoto && (url.contains('token=') || url.contains('/v2?'))) {
    return false;
  }
  return true;
}

/// Tipe dari payload token=JWT: 'video' / 'photo'. Null bila tidak terbaca.
String? _sniffJwtPayload(String url) {
  try {
    final tokenMatch = RegExp(
            r'token=([A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+)')
        .firstMatch(url);
    if (tokenMatch == null) return null;
    var payload = tokenMatch
        .group(1)!
        .split('.')[1]
        .replaceAll('-', '+')
        .replaceAll('_', '/');
    payload =
        payload.padRight(payload.length + (4 - payload.length % 4) % 4, '=');
    final decoded =
        utf8.decode(base64.decode(payload), allowMalformed: true).toLowerCase();
    if (RegExp(r'\.(mp4|mov|webm|mkv)(\?|"|$)').hasMatch(decoded)) {
      return 'video';
    }
    if (RegExp(r'\.(jpe?g|png|webp|heic)(\?|"|$)').hasMatch(decoded)) {
      return 'photo';
    }
    // Payload teks tanpa titik: {"ext":"jpg"}, "...photo...", dst.
    if (decoded.contains('jpg') ||
        decoded.contains('jpeg') ||
        decoded.contains('png') ||
        decoded.contains('webp') ||
        decoded.contains('photo') ||
        decoded.contains('image')) {
      return 'photo';
    }
    if (decoded.contains('mp4') ||
        decoded.contains('video') ||
        decoded.contains('reel')) {
      return 'video';
    }
  } catch (_) {}
  return null;
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

/// Pasangan URL unduhan + teks tombol/opsi yang mengiringinya.
/// Teks (misal "Download Photo", class "icon-dlvideo" di dalam tombol)
/// adalah sinyal tipe terkuat, jadi wajib ikut terbawa.
typedef _LinkPair = ({String url, String text});

/// Filter link unduhan yang boleh dipakai (buang halaman layanan & tracking).
bool _acceptLink(String link) {
  if (!link.startsWith('http')) return false;
  if (link.contains('indown.net/api') ||
      link.contains('snapsave.app') ||
      link.contains('play.google.com') ||
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
      lower.contains('.heic') ||
      lower.contains('token=');
}

/// Klasifikasi semua link lalu susun: video dulu, foto berikutnya, Audio MP3
/// di akhir. Ini DIPIAKAI BERSAMA oleh parser indown dan SnapSave agar
/// prilaku mode album/video selalu konsisten.
List<MediaQuality> _qualitiesFromLinks(
  Iterable<_LinkPair> found, {
  bool tokenDefaultPhoto = false,
}) {
  final videos = <String>[];
  final photos = <String>[];
  final seen = <String>{};

  for (final item in found) {
    final link = item.url;
    if (!_acceptLink(link) || !seen.add(link)) continue;
    if (_isVideoLink(
      link,
      item.text,
      tokenDefaultPhoto: tokenDefaultPhoto,
    )) {
      videos.add(link);
    } else {
      photos.add(link);
    }
  }

  final qualities = <MediaQuality>[];
  for (var i = 0; i < videos.length; i++) {
    qualities.add(MediaQuality(
      label: _numbered('Video HD', i + 1, videos.length),
      itag: videos[i],
      extension: 'mp4',
      hasAudio: true,
    ));
  }
  for (var i = 0; i < photos.length; i++) {
    qualities.add(MediaQuality(
      label: _numbered('Foto HD', i + 1, photos.length),
      itag: photos[i],
      extension: _guessExtension(photos[i], isPhoto: true),
    ));
  }

  // Opsi Audio MP3 hanya untuk konten yang benar-benar punya video/reel
  // — carousel foto murni tidak diberi MP3 palsu.
  final videoQualities =
      qualities.where((q) => q.extension == 'mp4' || (q.hasAudio ?? false)).toList();
  if (videoQualities.length == 1) {
    qualities.add(MediaQuality(
      label: 'Audio MP3',
      itag: videoQualities.first.itag,
      extension: 'mp3',
      hasAudio: true,
    ));
  } else if (videoQualities.length > 1) {
    for (var i = 0; i < videoQualities.length; i++) {
      qualities.add(MediaQuality(
        label: 'Audio MP3 (${i + 1})',
        itag: videoQualities[i].itag,
        extension: 'mp3',
        hasAudio: true,
      ));
    }
  }

  return qualities;
}

/// Parse hasil indown: pasangan (URL, teks tombol) tiap link unduhan.
List<MediaQuality> _parseIndownItems(String html) {
  final found = <_LinkPair>[];
  for (final m in RegExp(
    r'<a\b[^>]*?href="([^"]+)"[^>]*>(.*?)</a>',
    dotAll: true,
  ).allMatches(html)) {
    found.add((url: m.group(1)!, text: m.group(2) ?? ''));
  }
  // Fallback: URL mentah tanpa <a> (JSON / JS).
  if (found.isEmpty) {
    for (final m in RegExp(r'https?://[^\s"<>\\]+').allMatches(html)) {
      final link =
          m.group(0)!.replaceAll(r'\/', '/').replaceAll('&amp;', '&');
      if (_acceptLink(link)) found.add((url: link, text: ''));
    }
  }
  return _qualitiesFromLinks(found);
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

/// Unescape JS string literal: \n \t \r \" \' \\ \/ dan \uXXXX.
String _unescapeJs(String raw) {
  return raw.replaceAllMapped(
    RegExp(r'''\\(u[0-9a-fA-F]{4}|n|t|r|["'\\/])'''),
    (m) {
      final g = m.group(1)!;
      switch (g) {
        case 'n':
          return '\n';
        case 't':
          return '\t';
        case 'r':
          return '\r';
        case '"':
        case "'":
          return g;
        case '/':
          return '/';
        case '\\':
          return '\\';
      }
      if (g.startsWith('u') && g.length == 5) {
        final cp = int.tryParse(g.substring(1), radix: 16);
        if (cp != null) return String.fromCharCode(cp);
      }
      return g;
    },
  );
}

/// Buka bentuk respons JS yang berisi `innerHTML = "..."` /
/// `document.write("...")` (belum terangkai decodeSnapSave), atauraun slice
/// `<ul ...>...</ul>` langsung di dalam script. Pola referensi Mori.
String? _extractInnerHtml(String js) {
  const markers = [
    'innerHTML = "',
    "innerHTML = '",
    'innerHTML="',
    "innerHTML='",
    'document.write("',
    "document.write('",
  ];
  for (final marker in markers) {
    final start = js.indexOf(marker);
    if (start < 0) continue;
    final contentStart = start + marker.length;
    final closing = marker.substring(marker.length - 1);
    final end = js.lastIndexOf(closing);
    if (end <= contentStart) continue;
    final unescaped = _unescapeJs(js.substring(contentStart, end));
    if (unescaped.contains('href=')) return unescaped;
  }
  final ulStart = js.indexOf('<ul');
  final ulEnd = js.lastIndexOf('</ul>');
  if (ulStart >= 0 && ulEnd > ulStart) {
    final slice = js.substring(ulStart, ulEnd + 5);
    if (slice.contains('href=')) return slice;
  }
  return null;
}

/// Parse respons SnapSave: pasangan tombol <a> + opsi <select> (kualitas
/// disimpan sebagai value URL). Regex `\\?"` menangani HTML polos maupun
/// hasil yang masih ter-escape.
List<MediaQuality> _parseSnapItems(String html) {
  final found = <_LinkPair>[];
  for (final m in RegExp(
    r'<a\b[^>]*?href=\\?"([^"\\]+)\\?"[^>]*>(.*?)</a>',
    dotAll: true,
  ).allMatches(html)) {
    found.add((url: m.group(1)!, text: m.group(2) ?? ''));
  }
  // Opsi select: <option value="URL" ...>720p</option>
  for (final m in RegExp(
    r'<option[^>]*?value=\\?"([^"\\]+)\\?"[^>]*>(.*?)</option>',
    dotAll: true,
  ).allMatches(html)) {
    found.add((url: m.group(1)!, text: m.group(2) ?? ''));
  }
  if (found.isEmpty) {
    for (final m in RegExp(r'href=\\?"([^"\\]+)\\?"').allMatches(html)) {
      found.add((url: m.group(1)!, text: ''));
    }
  }
  // Halaman murni-foto (tanpa .mp4 / icon-dlvideo) → link /v2?token adalah
  // foto; sedikit jejak video dari manapun → kembali default video.
  final pageHasVideoMarker =
      html.contains('.mp4') || html.contains('icon-dlvideo');
  return _qualitiesFromLinks(
    found,
    tokenDefaultPhoto: !pageHasVideoMarker,
  );
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

    // Pembungkus respons dipecah bertingkat (pola referensi Mori):
    // 1) hunter script (Dean-Edwards),
    // 2) bentuk JS `innerHTML = "..."` / `document.write("...")`,
    // 3) slice <ul class="download-box">...</ul>,
    // 4) mentah apa adanya.
    final decoded = decodeSnapSave(raw) ?? raw;
    var html = _extractInnerHtml(raw) ?? _extractInnerHtml(decoded) ?? '';
    if (html.isEmpty) html = decoded;
    if (!html.contains('href=')) {
      html = _extractInnerHtml(html) ?? '';
    }
    if (html.isEmpty) html = decoded;

    final qualities = _parseSnapItems(html);
    if (qualities.isEmpty) {
      throw const ProviderException(
        message: 'snapsave: tidak ada link ditemukan.',
        kind: ProviderErrorKind.noResult,
      );
    }

    // Thumbnail: img kotak thumbnail dulu, img lain, lalu link foto pertama
    // (URL foto itu sendiri layak sebagai pratinjau).
    final thumbMatch = RegExp(
      r'<div[^>]*class=\\?"download-items__thumb\\?"[^>]*>.*?<img[^>]*src=\\?"([^"\\]+)\\?"',
      dotAll: true,
    ).firstMatch(html);
    var thumbnail = thumbMatch?.group(1);
    if (thumbnail == null) {
      final anyImg = RegExp(r'<img[^>]*src=\\?"(https?://[^"\\]+)\\?"')
          .firstMatch(html);
      thumbnail = anyImg?.group(1);
    }
    if (thumbnail == null) {
      for (final q in qualities) {
        if (q.extension != 'mp4' && q.extension != 'mp3') {
          thumbnail = q.itag;
          break;
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


