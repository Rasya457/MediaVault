// Spotify Provider — alur third-party mengikuti pola scraper referensi
// coflyn/Mori (bundle.js): primary SoundLoaders (spotimate.app) dengan
// userverify -> action -> action/track, fallback SpotiDown (spotidown.app)
// dengan hidden-input -> action -> action/track. Ditulis ulang dalam Dart,
// bukan copy-paste.

import 'dart:convert';

import 'package:dio/dio.dart';
import '../../core/network/api_client.dart';
import 'provider.dart';
import 'models.dart';
import 'remote_config.dart';
import 'youtube_provider.dart';

const _kPrimaryId = 'spotify_primary';
const _kFallbackId = 'spotify_fallback';

/// Batas resolve per-track agar playlist raksasa tidak menghantam
/// endpoint dengan ratusan request berurutan.
const _kMaxTracks = 20;

bool _canHandleSpotify(String url) {
  final clean = url.trim();
  if (clean.toLowerCase().startsWith('spotify:')) return true;
  final uri = Uri.tryParse(clean);
  if (uri == null) return false;
  final host = uri.host.toLowerCase();
  return host == 'open.spotify.com' ||
      host.endsWith('.spotify.com') ||
      host == 'spotify.link' ||
      host.endsWith('.spotify.link');
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

/// Decode respons yang bisa berupa Map maupun String JSON.
Map<String, dynamic> _asJson(dynamic data) {
  if (data is Map) return data.cast<String, dynamic>();
  if (data is String) {
    try {
      final decoded = jsonDecode(data);
      if (decoded is Map) return decoded.cast<String, dynamic>();
    } catch (_) {}
  }
  return {};
}

/// Bersihkan entity HTML + tag dari teks judul/artis.
String _unescape(String s) => s
    .replaceAll(RegExp(r'<[^>]+>'), '')
    .replaceAll('&#039;', "'")
    .replaceAll(RegExp(r'&#0?39;'), "'")
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .trim();

/// Ambil semua input name->value dari satu blok <form>.
Map<String, String> _formInputs(String formHtml) {
  final out = <String, String>{};
  final pat = RegExp(
    '<input[^>]+name="([^"]+)"[^>]+value="([^"]*)"',
    caseSensitive: false,
  );
  final alt = RegExp(
    '<input[^>]+value="([^"]*)"[^>]+name="([^"]+)"',
    caseSensitive: false,
  );
  for (final m in pat.allMatches(formHtml)) {
    out[m.group(1)!] = _unescape(m.group(2) ?? '');
  }
  for (final m in alt.allMatches(formHtml)) {
    out.putIfAbsent(m.group(2)!, () => _unescape(m.group(1) ?? ''));
  }
  return out;
}

/// Resolve short link spotify.com/s/ atau spotify.link ke URL kanonis (best-effort).
Future<String> _resolveShortLink(String url) async {
  final clean = url.trim();
  final lower = clean.toLowerCase();
  if (!lower.contains('spotify.com/s/') && !lower.contains('spotify.link/')) {
    return clean;
  }
  try {
    final res = await httpClient.get<String>(
      clean,
      options: Options(
        responseType: ResponseType.plain,
        headers: {'User-Agent': 'WhatsApp/2.21.19.21 A'},
      ),
    );
    final finalUri = res.realUri.toString();
    if (finalUri.contains('open.spotify.com') &&
        !finalUri.contains('/s/') &&
        !finalUri.contains('spotify.link')) {
      return finalUri;
    }
    final html = res.data ?? '';
    final og = RegExp(
      r'<meta property="og:url" content="([^"]+)"',
      caseSensitive: false,
    ).firstMatch(html)?.group(1);
    if (og != null && og.isNotEmpty) return og;
  } catch (_) {}
  return clean;
}

Never _down(String who, DioException e) => throw ProviderException(
      message: 'endpoint $who tidak merespons (${e.type.name})',
      kind: ProviderErrorKind.providerDown,
      underlyingError: e,
    );

class SpotifyPrimaryProvider implements MediaProvider {
  @override
  String get providerName => 'SoundLoaders';

  @override
  bool canHandle(String url) => _canHandleSpotify(url);

  @override
  Future<MediaInfo> fetchInfo(String url) async {
    final cfg = await RemoteConfig.instance.get(_kPrimaryId);
    if (cfg == null || !cfg.enabled) {
      throw const ProviderException(
        message: 'Primary Spotify provider disabled.',
        kind: ProviderErrorKind.providerDown,
      );
    }
    try {
      final base = cfg.url.replaceAll(RegExp(r'/+$'), '');
      final link = await _resolveShortLink(url);

      // 1. Kunjungi /en1 agar cookie sesi tersimpan di jar.
      try {
        await httpClient.get<String>(
          '$base/en1',
          options: Options(responseType: ResponseType.plain),
        );
      } on DioException catch (e) {
        _down('spotimate', e);
      }

      // 2. Verifikasi user -> token.
      String cfToken = '';
      try {
        final res = await httpClient.post<dynamic>(
          '$base/api/userverify',
          data: 'url=${Uri.encodeComponent(link)}',
          options: Options(
            contentType: Headers.formUrlEncodedContentType,
            headers: {
              'X-Requested-With': 'XMLHttpRequest',
              'Referer': '$base/en1',
              'Origin': base,
            },
          ),
        );
        final body = _asJson(res.data);
        if (body['success'] == true && (body['token'] ?? '').toString().isNotEmpty) {
          cfToken = body['token'].toString();
        }
      } on DioException {
        // Token opsional — lanjut tanpa token seperti referensi.
      }

      // 3. Minta daftar track.
      late final Map<String, dynamic> action;
      try {
        final res = await httpClient.post<dynamic>(
          '$base/action',
          data: FormData.fromMap({'url': link, 'cftoken': cfToken}),
          options: Options(headers: {
            'Referer': '$base/en1',
            'Origin': base,
          }),
        );
        action = _asJson(res.data);
      } on DioException catch (e) {
        _down('spotimate', e);
      }
      if (action['success'] == false) {
        throw ProviderException(
          message:
              'soundloaders: ${action['message'] ?? 'gagal memproses'}.',
          kind: ProviderErrorKind.noResult,
        );
      }
      final parsed = _parseSoundLoadersTracks((action['html'] ?? '').toString());
      if (parsed.tracks.isEmpty) {
        throw const ProviderException(
          message: 'soundloaders: tidak ada track ditemukan. '
              'Link mungkin privat atau salah.',
          kind: ProviderErrorKind.noResult,
        );
      }

      // 4. Resolve tiap track ke link MP3 langsung. Cover dibuang —
      //    audio saja; cover playlist dipakai sebagai thumbnail header.
      final multi = parsed.tracks.length > 1;
      final qualities = <MediaQuality>[];
      final count = parsed.tracks.length.clamp(0, _kMaxTracks);
      for (var i = 0; i < count; i++) {
        final t = parsed.tracks[i];
        final name = t.artist.isNotEmpty ? '${t.artist} - ${t.title}' : t.title;
        final links = await _resolveSoundLoadersTrack(base, link, t);
        if (links.isEmpty) continue;
        for (final l in links) {
          if (l.isCover) continue;
          qualities.add(MediaQuality(
            label: multi ? '${_pad(i + 1, count)} $name [MP3]' : 'MP3',
            itag: l.url,
            extension: 'mp3',
          ));
        }
      }
      if (qualities.isEmpty) {
        throw const ProviderException(
          message: 'soundloaders: tidak ada link audio ditemukan.',
          kind: ProviderErrorKind.noResult,
        );
      }

      final suffix = parsed.type == 'playlist'
          ? ' (Playlist)'
          : parsed.type == 'album'
              ? ' (Album)'
              : '';
      final title = parsed.artist.isNotEmpty
          ? '${parsed.artist} - ${parsed.title}$suffix'
          : '${parsed.title}$suffix';
      return MediaInfo(
        title: title.isEmpty ? 'Spotify Track' : title,
        author: parsed.artist.isEmpty ? 'Spotify' : parsed.artist,
        thumbnail: parsed.thumbnail,
        durationSec: null,
        qualities: qualities,
        source: 'third-party',
        providerName: providerName,
      );
    } catch (_) {
      // Jika SoundLoaders/Spotimate gagal (Cloudflare Turnstile token error dll),
      // langsung lanjut ke pipeline Spotify embed + YouTube audio matcher.
      return await _fetchSpotifyEmbedPipeline(url);
    }
  }

  @override
  Future<String> fetchDownloadUrl(String url, {String quality = 'best'}) async =>
      _resolveQuality(await fetchInfo(url), quality);
}

String _pad(int i, int total) =>
    i.toString().padLeft(total.toString().length, '0');

/// Satu track soundloaders beserta payload resolve-nya.
class _SlTrack {
  _SlTrack({
    required this.data,
    required this.trackToken,
    required this.base,
    required this.title,
    required this.artist,
  });
  final String data;
  final String trackToken;
  final String base;
  final String title;
  final String artist;
}

class _SlParsed {
  _SlParsed({
    required this.title,
    required this.artist,
    required this.thumbnail,
    required this.type,
    required this.tracks,
  });
  final String title;
  final String artist;
  final String? thumbnail;
  final String type;
  final List<_SlTrack> tracks;
}

_SlParsed _parseSoundLoadersTracks(String html) {
  var title = '';
  var artist = '';
  String? thumbnail;
  var type = 'track';

  final thumbMatch = RegExp(
        r'<img[^>]+src="(https://[^"]*(?:scdn\.co|spotimate|soundloaders)[^"]*)"',
        caseSensitive: false,
      ).firstMatch(html) ??
      RegExp(
        r'<img[^>]+src="([^"]+)"[^>]*class="[^"]*rounded-xl[^"]*"',
        caseSensitive: false,
      ).firstMatch(html);
  if (thumbMatch != null) thumbnail = thumbMatch.group(1);

  final titleMatch = RegExp(
        r'<h[23][^>]*itemprop="name"[^>]*>([\s\S]*?)</h[23]>',
        caseSensitive: false,
      ).firstMatch(html) ??
      RegExp(r'<h2[^>]*>([\s\S]*?)</h2>', caseSensitive: false)
          .firstMatch(html) ??
      RegExp(r'<h3[^>]*>([\s\S]*?)</h3>', caseSensitive: false)
          .firstMatch(html);
  if (titleMatch != null) title = _unescape(titleMatch.group(1) ?? '');

  final artistMatch =
      RegExp(r'<p[^>]*><span>([\s\S]*?)</span></p>', caseSensitive: false)
              .firstMatch(html) ??
          RegExp(r'<p class="text-sm text-white/60 mb-8">([\s\S]*?)</p>')
              .firstMatch(html);
  if (artistMatch != null) artist = _unescape(artistMatch.group(1) ?? '');

  if (html.contains('playlist-songs') ||
      html.contains('Playlist') ||
      html.contains('dltracks')) {
    type = html.contains('Album') ? 'album' : 'playlist';
  }

  final tracks = <_SlTrack>[];
  for (final m
      in RegExp(r'<form[^>]*>([\s\S]*?)</form>', caseSensitive: false)
          .allMatches(html)) {
    final form = m.group(1) ?? '';
    if (!form.contains('name="data"') && !form.contains("name='data'")) {
      continue;
    }
    final inputs = _formInputs(form);
    final data = inputs['data'] ?? '';
    if (data.isEmpty) continue;
    var tTitle = '';
    var tArtist = '';
    try {
      final meta = jsonDecode(utf8.decode(base64.decode(data)))
          as Map<String, dynamic>;
      tTitle = (meta['name'] ?? meta['title'] ?? '').toString();
      tArtist = (meta['artist'] ?? meta['singer'] ?? '').toString();
    } catch (_) {}
    tracks.add(_SlTrack(
      data: data,
      trackToken: inputs['token'] ?? inputs['track_token'] ?? '',
      base: inputs['base'] ?? '',
      title: _unescape(tTitle),
      artist: _unescape(tArtist),
    ));
  }
  if (title.isEmpty && tracks.isNotEmpty) title = tracks.first.title;
  if (artist.isEmpty && tracks.isNotEmpty) artist = tracks.first.artist;
  return _SlParsed(
    title: title,
    artist: artist,
    thumbnail: thumbnail,
    type: type,
    tracks: tracks,
  );
}

class _SlLink {
  _SlLink(this.url, this.isCover);
  final String url;
  final bool isCover;
}

/// Resolve satu track via /action/track -> daftar link langsung.
Future<List<_SlLink>> _resolveSoundLoadersTrack(
  String base,
  String pageUrl,
  _SlTrack track,
) async {
  try {
    final res = await httpClient.post<dynamic>(
      '$base/action/track',
      data: FormData.fromMap({
        'data': track.data,
        'base': track.base.isEmpty ? pageUrl : track.base,
        'token': track.trackToken,
      }),
      options: Options(headers: {
        'Referer': '$base/en1',
        'Origin': base,
      }),
    );
    final body = _asJson(res.data);
    final raw = (body['data'] ?? body['html'] ?? '').toString();
    if (raw.isEmpty) return [];
    return _extractAnchors(raw);
  } on DioException {
    return [];
  }
}

/// Ekstrak <a href> valid dari HTML track (pola le() referensi).
List<_SlLink> _extractAnchors(String html) {
  final out = <_SlLink>[];
  final seen = <String>{};
  for (final m in RegExp(
    '<a\\s[^>]*href="([^"]+)"[^>]*>([\\s\\S]*?)</a>',
    caseSensitive: false,
  ).allMatches(html)) {
    final url = m.group(1)!.trim();
    final text = _unescape(m.group(2) ?? '');
    if (url.isEmpty ||
        !url.startsWith('http') ||
        text == 'Download Another Song' ||
        url.contains('tunecable.com') ||
        url.contains('premium') ||
        !seen.add(url)) {
      continue;
    }
    final lower = text.toLowerCase();
    final isCover = lower.contains('cover') ||
        url.contains('cover') ||
        url.contains('scdn.co') ||
        RegExp(r'\.(jpg|jpeg|png|webp)(\?.*)?$').hasMatch(url);
    out.add(_SlLink(url, isCover));
  }
  return out;
}

class SpotifyFallbackProvider implements MediaProvider {
  @override
  String get providerName => 'SpotiDown';

  @override
  bool canHandle(String url) => _canHandleSpotify(url);

  @override
  Future<MediaInfo> fetchInfo(String url) async {
    final cfg = await RemoteConfig.instance.get(_kFallbackId);
    if (cfg != null && cfg.enabled) {
      try {
        final info = await _fetchSpotiDown(url, cfg);
        if (info.qualities.isNotEmpty) {
          return info;
        }
      } catch (_) {
        // SpotiDown scraper failed (CSRF / Cloudflare Turnstile / anti-bot).
        // Lanjut ke pipeline Spotify embed + YouTube audio matcher (arsitektur Mori).
      }
    }
    return await _fetchSpotifyEmbedPipeline(url);
  }

  @override
  Future<String> fetchDownloadUrl(String url, {String quality = 'best'}) async =>
      _resolveQuality(await fetchInfo(url), quality);
}

Future<MediaInfo> _fetchSpotiDown(String url, EndpointConfig cfg) async {
  final base = cfg.url.replaceAll(RegExp(r'/+$'), '');
  final link = await _resolveShortLink(url);

  // 1. Ambil cookie + hidden input dari homepage.
  final hidden = <String, String>{};
  try {
    final res = await httpClient.get<String>(
      '$base/',
      options: Options(responseType: ResponseType.plain),
    );
    final html = res.data ?? '';
    final formMatch = RegExp(
      '<form[^>]*name="spotifyurl"[^>]*>([\\s\\S]*?)</form>',
      caseSensitive: false,
    ).firstMatch(html);
    if (formMatch != null) {
      for (final e in _formInputs(formMatch.group(1) ?? '').entries) {
        if (e.key != 'url') hidden[e.key] = e.value;
      }
    }
  } on DioException catch (e) {
    _down('spotidown', e);
  }

  // 2. Submit URL.
  late final Map<String, dynamic> action;
  try {
    final res = await httpClient.post<dynamic>(
      '$base/action',
      data: {...hidden, 'url': link, 'g-recaptcha-response': 'dummy_token'},
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        headers: {
          'X-Requested-With': 'XMLHttpRequest',
          'Referer': '$base/',
          'Origin': base,
        },
      ),
    );
    action = _asJson(res.data);
  } on DioException catch (e) {
    _down('spotidown', e);
  }
  if (action['error'] == true) {
    throw ProviderException(
      message: 'spotidown: ${action['message'] ?? 'gagal memproses'}.',
      kind: ProviderErrorKind.noResult,
    );
  }
  final html = (action['data'] ?? '').toString();
  final forms = RegExp(
    '<form[^>]*name="submitspurl"[^>]*>([\\s\\S]*?)</form>',
    caseSensitive: false,
  ).allMatches(html).map((m) => m.group(1) ?? '').toList();
  if (forms.isEmpty) {
    throw const ProviderException(
      message: 'spotidown: tidak ada track ditemukan. '
          'Link mungkin privat atau salah.',
      kind: ProviderErrorKind.noResult,
    );
  }

  // 3. Resolve tiap form via /action/track.
  final multi = forms.length > 1;
  final qualities = <MediaQuality>[];
  String title = '';
  String author = '';
  final count = forms.length.clamp(0, _kMaxTracks);
  for (var i = 0; i < count; i++) {
    final inputs = _formInputs(forms[i]);
    var tName = '';
    final rawData = inputs['data'] ?? '';
    if (rawData.isNotEmpty) {
      try {
        final meta = jsonDecode(utf8.decode(base64.decode(rawData)))
            as Map<String, dynamic>;
        final v = (meta['name'] ?? meta['title'] ?? '').toString();
        final a = (meta['artist'] ?? meta['singer'] ?? '').toString();
        tName = a.isNotEmpty && v.isNotEmpty ? '$a - $v' : v;
        if (i == 0) {
          title = v;
          author = a;
        }
      } catch (_) {}
    }
    final links = await _resolveSpotiDownTrack(base, inputs);
    for (final l in links) {
      if (l.isCover) continue; // audio saja — cover tidak diunduh
      qualities.add(MediaQuality(
        label: multi
            ? '${_pad(i + 1, count)} ${tName.isEmpty ? 'Track' : tName} [MP3]'
            : 'MP3',
        itag: l.url,
        extension: 'mp3',
      ));
    }
  }
  if (qualities.isEmpty) {
    throw const ProviderException(
      message: 'spotidown: tidak ada link audio ditemukan.',
      kind: ProviderErrorKind.noResult,
    );
  }
  return MediaInfo(
    title: title.isEmpty ? 'Spotify Track' : title,
    author: author.isEmpty ? 'Spotify' : author,
    thumbnail: null,
    durationSec: null,
    qualities: qualities,
    source: 'third-party',
    providerName: 'SpotiDown',
  );
}

({String type, String id})? _parseSpotifyTypeAndId(String url) {
  final clean = url.trim();
  final urlMatch = RegExp(
    r'(?:https?://)?(?:open\.)?spotify\.(?:com|link)/(?:intl-[a-zA-Z-]+/)?(track|album|playlist)/([a-zA-Z0-9]+)',
    caseSensitive: false,
  ).firstMatch(clean);
  if (urlMatch != null) {
    return (type: urlMatch.group(1)!.toLowerCase(), id: urlMatch.group(2)!);
  }

  final uriMatch = RegExp(
    r'spotify:(track|album|playlist):([a-zA-Z0-9]+)',
    caseSensitive: false,
  ).firstMatch(clean);
  if (uriMatch != null) {
    return (type: uriMatch.group(1)!.toLowerCase(), id: uriMatch.group(2)!);
  }

  final genericMatch = RegExp(
    r'(track|album|playlist)/([a-zA-Z0-9]+)',
    caseSensitive: false,
  ).firstMatch(clean);
  if (genericMatch != null) {
    return (type: genericMatch.group(1)!.toLowerCase(), id: genericMatch.group(2)!);
  }

  return null;
}

Future<MediaQuality?> _matchYouTubeAudio(String artist, String title) async {
  try {
    final query = artist.isNotEmpty && !title.toLowerCase().contains(artist.toLowerCase())
        ? '$artist - $title Audio'
        : '$title Audio';
    final searchRes = await httpClient.post<Map<String, dynamic>>(
      'https://www.youtube.com/youtubei/v1/search',
      data: {
        'context': {
          'client': {
            'clientName': 'WEB',
            'clientVersion': '2.20240101.00.00',
            'hl': 'en',
            'gl': 'US',
          },
        },
        'query': query,
      },
      options: Options(
        responseType: ResponseType.json,
        headers: {
          'Content-Type': 'application/json',
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
        },
      ),
    );
    final data = searchRes.data ?? {};
    final contents = (data['contents']?['twoColumnSearchResultsRenderer']
            ?['primaryContents']?['sectionListRenderer']?['contents'] as List?) ??
        [];
    String? foundVideoId;
    for (final section in contents) {
      final items = (section['itemSectionRenderer']?['contents'] as List?) ?? [];
      for (final item in items) {
        final vid = item['videoRenderer']?['videoId']?.toString();
        if (vid != null && vid.isNotEmpty) {
          foundVideoId = vid;
          break;
        }
      }
      if (foundVideoId != null) break;
    }

    if (foundVideoId != null) {
      try {
        final ytInfo = await YouTubeInnertubeProvider()
            .fetchInfo('https://www.youtube.com/watch?v=$foundVideoId');
        for (final q in ytInfo.qualities) {
          if (q.extension == 'mp3' ||
              q.extension == 'm4a' ||
              ((q.hasAudio ?? false) && q.extension != 'mp4')) {
            return MediaQuality(
              label: 'MP3 (Full Track)',
              itag: q.itag,
              extension: 'mp3',
              hasAudio: true,
              sizeBytes: q.sizeBytes,
            );
          }
        }
        for (final q in ytInfo.qualities) {
          if (q.hasAudio ?? false) {
            return MediaQuality(
              label: 'MP3 (Full Track)',
              itag: q.itag,
              extension: 'mp3',
              hasAudio: true,
              sizeBytes: q.sizeBytes,
            );
          }
        }
      } catch (_) {
        try {
          final dl = await YouTubeThirdPartyProvider().fetchDownloadUrl(
            'https://www.youtube.com/watch?v=$foundVideoId',
            quality: 'mp3',
          );
          if (dl.isNotEmpty) {
            return MediaQuality(
              label: 'MP3 (Full Track)',
              itag: dl,
              extension: 'mp3',
              hasAudio: true,
            );
          }
        } catch (_) {}
      }
    }
  } catch (_) {}
  return null;
}

Future<MediaInfo> _fetchSpotifyEmbedPipeline(String url) async {
  final resolvedUrl = await _resolveShortLink(url);
  final parsed = _parseSpotifyTypeAndId(resolvedUrl);
  if (parsed == null) {
    throw const ProviderException(
      message: 'Link Spotify tidak valid atau format tidak dikenali.',
      kind: ProviderErrorKind.invalidUrl,
    );
  }

  final type = parsed.type;
  final id = parsed.id;
  final embedUrl = 'https://open.spotify.com/embed/$type/$id';

  late final String html;
  try {
    final res = await httpClient.get<String>(
      embedUrl,
      options: Options(
        responseType: ResponseType.plain,
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Accept-Language': 'en-US,en;q=0.9',
        },
      ),
    );
    html = res.data ?? '';
  } on DioException catch (e) {
    _down('spotify-embed', e);
  }

  if (html.isEmpty) {
    throw const ProviderException(
      message: 'Gagal mengambil metadata Spotify (respons kosong).',
      kind: ProviderErrorKind.noResult,
    );
  }

  String title = '';
  String artist = '';
  String? coverUrl;
  int? durationSec;
  String? previewUrl;
  final tracks = <({String title, String artist, String? previewUrl, int? durationSec})>[];

  final nextDataMatch = RegExp(
    r'<script id="__NEXT_DATA__"[^>]*>([\s\S]*?)</script>',
  ).firstMatch(html);

  if (nextDataMatch != null) {
    try {
      final json = jsonDecode(nextDataMatch.group(1)!) as Map<String, dynamic>;
      final entity = (json['props']?['pageProps']?['state']?['data']?['entity']
          as Map?)?.cast<String, dynamic>() ?? {};

      title = (entity['title'] ?? entity['name'] ?? '').toString();
      final artistsList = (entity['artists'] as List?) ?? [];
      if (artistsList.isNotEmpty) {
        artist = (artistsList.first['name'] ?? '').toString();
      } else if (entity['subtitle'] != null) {
        artist = entity['subtitle'].toString();
      }

      final durMs = entity['duration'] as num?;
      if (durMs != null && durMs > 0) {
        durationSec = (durMs / 1000).round();
      }

      previewUrl = entity['audioPreview']?['url']?.toString();

      final images = (entity['visualIdentity']?['image'] as List?) ?? [];
      if (images.isNotEmpty) {
        coverUrl = (images.last['url'] ?? images.first['url'])?.toString();
      }

      final trackList = (entity['trackList'] as List?) ?? [];
      for (final t in trackList) {
        if (t is Map) {
          final tTitle = (t['title'] ?? t['name'] ?? '').toString();
          final tArtist = (t['subtitle'] ?? artist).toString();
          final tPreview = t['audioPreview']?['url']?.toString();
          final tDurMs = t['duration'] as num?;
          final tDurSec = tDurMs != null ? (tDurMs / 1000).round() : null;
          tracks.add((
            title: tTitle,
            artist: tArtist,
            previewUrl: tPreview,
            durationSec: tDurSec,
          ));
        }
      }
    } catch (_) {}
  }

  // Fallback OpenGraph
  if (title.isEmpty) {
    final ogTitle = RegExp(r'<meta property="og:title" content="([^"]+)"')
        .firstMatch(html)
        ?.group(1);
    if (ogTitle != null) title = _unescape(ogTitle);
  }
  if (artist.isEmpty) {
    final ogDesc = RegExp(r'<meta property="og:description" content="([^"]+)"')
        .firstMatch(html)
        ?.group(1);
    if (ogDesc != null) artist = _unescape(ogDesc);
  }
  if (coverUrl == null) {
    final ogImg = RegExp(r'<meta property="og:image" content="([^"]+)"')
        .firstMatch(html)
        ?.group(1);
    if (ogImg != null) coverUrl = ogImg;
  }

  if (title.isEmpty) {
    throw const ProviderException(
      message: 'Tidak dapat menemukan detail lagu Spotify. Pastikan link dapat diakses.',
      kind: ProviderErrorKind.noResult,
    );
  }

  final qualities = <MediaQuality>[];

  // 1. YouTube InnerTube match untuk Full Audio jika single track
  if (type == 'track' || tracks.isEmpty) {
    final ytAudio = await _matchYouTubeAudio(artist, title);
    if (ytAudio != null) {
      qualities.add(ytAudio);
    }
    // 2. Preview MP3 resmi (30s) dari CDN Spotify jika ada
    if (previewUrl != null && previewUrl.isNotEmpty) {
      qualities.add(MediaQuality(
        label: qualities.isEmpty ? 'Audio MP3' : 'MP3 (Preview 30s)',
        itag: previewUrl,
        audioUrl: previewUrl,
        extension: 'mp3',
        hasAudio: true,
      ));
    }
    if (qualities.isEmpty) {
      qualities.add(MediaQuality(
        label: 'MP3',
        itag: 'spotify_track:$title:$artist',
        audioUrl: previewUrl,
        extension: 'mp3',
        hasAudio: true,
      ));
    }
  } else {
    // 3. Album / playlist multiple tracks
    final count = tracks.length.clamp(0, _kMaxTracks);
    for (var i = 0; i < count; i++) {
      final t = tracks[i];
      final tName = t.artist.isNotEmpty ? '${t.artist} - ${t.title}' : t.title;
      final itag = (t.previewUrl != null && t.previewUrl!.isNotEmpty)
          ? t.previewUrl!
          : 'spotify_track:${t.title}:${t.artist}';
      qualities.add(MediaQuality(
        label: '${_pad(i + 1, count)} $tName [MP3]',
        itag: itag,
        audioUrl: t.previewUrl,
        extension: 'mp3',
        hasAudio: true,
      ));
    }
  }

  // Cover tidak diunduh — audio saja. Cover dipakai hanya sebagai
  // thumbnail header di halaman preview.

  if (qualities.isEmpty) {
    throw const ProviderException(
      message: 'spotify: tidak ada stream audio yang dapat diunduh.',
      kind: ProviderErrorKind.noResult,
    );
  }

  final displayTitle = artist.isNotEmpty && !title.toLowerCase().contains(artist.toLowerCase())
      ? '$artist - $title'
      : title;

  return MediaInfo(
    title: displayTitle,
    author: artist.isNotEmpty ? artist : 'Spotify',
    thumbnail: coverUrl,
    durationSec: durationSec,
    qualities: qualities,
    source: 'third-party',
    providerName: 'Spotify',
    downloadHeaders: const {
      'User-Agent':
          'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Mobile Safari/537.36',
    },
  );
}

/// Resolve satu form spotidown via /action/track.
Future<List<_SlLink>> _resolveSpotiDownTrack(
  String base,
  Map<String, String> inputs,
) async {
  try {
    final res = await httpClient.post<dynamic>(
      '$base/action/track',
      data: {...inputs, 'g-recaptcha-response': 'dummy_token'},
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        headers: {
          'X-Requested-With': 'XMLHttpRequest',
          'Referer': '$base/',
          'Origin': base,
        },
      ),
    );
    final body = _asJson(res.data);
    final raw = (body['data'] ?? '').toString();
    if (raw.isEmpty) return [];
    final out = <_SlLink>[];
    final seen = <String>{};
    for (final m in RegExp(
      '<a[^>]+href="(http[^"]+)"[^>]*>([\\s\\S]*?)</a>',
      caseSensitive: false,
    ).allMatches(raw)) {
      final href = m.group(1)!;
      final text = _unescape(m.group(2) ?? '');
      if (href.contains('premium.html') ||
          text == 'Download Another Song' ||
          !seen.add(href)) {
        continue;
      }
      final lower = text.toLowerCase();
      out.add(_SlLink(
        href,
        lower.contains('cover') || href.contains('cover'),
      ));
    }
    return out;
  } on DioException {
    return [];
  }
}

/// Helper resolver audio Spotify publik
class SpotifyProvider {
  /// Resolve track audio stream penuh via YouTube matcher atau provider alternatif
  static Future<String?> resolveFullTrackAudio(String artist, String title) async {
    try {
      final q = await _matchYouTubeAudio(artist, title);
      if (q != null && q.itag.isNotEmpty) {
        return q.itag;
      }
    } catch (_) {}
    return null;
  }
}
