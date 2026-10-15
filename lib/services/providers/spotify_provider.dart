// Spotify Provider — ditulis ulang clean-room, bukan copy dari repo mana pun.
//
// Status verifikasi E2E 2026-10-14: TERHALANG.
// - spotidown.app/api → 404. Form homepage-nya butuh reCAPTCHA → tidak bisa
//   dipakai via HTTP sederhana.
// - spotifydown.com/api/download → 404, homepage kosong.
// Bentuk di bawah mengikuti spec test (belum terbukti). DINONAKTIFKAN di
// endpoints.json sampai endpoint terverifikasi. Link playlist/album butuh
// ekspansi multi-track (di luar scope MVP track).
// Opsi ke depan: Spotify Web API (metadata) + match YouTube on-device.

import 'package:dio/dio.dart';
import '../../core/network/api_client.dart';
import 'provider.dart';
import 'models.dart';
import 'remote_config.dart';

const _kPrimaryId = 'spotify_primary';
const _kFallbackId = 'spotify_fallback';

bool _canHandleSpotify(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  return uri.host.toLowerCase() == 'open.spotify.com';
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

class SpotifyPrimaryProvider implements MediaProvider {
  @override
  String get providerName => 'SpotiDown';

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

    late final Response<Map<String, dynamic>> response;
    try {
      response = await httpClient.get<Map<String, dynamic>>(
        cfg.url,
        queryParameters: {'url': url},
        options: Options(responseType: ResponseType.json),
      );
    } on DioException catch (e) {
      throw ProviderException(
        message: 'endpoint Spotify tidak merespons (${e.type.name})',
        kind: ProviderErrorKind.providerDown,
        underlyingError: e,
      );
    }

    final body = response.data ?? {};
    if (body['success'] != true) {
      throw ProviderException(
        message: 'spotidown: ${body['message'] ?? 'gagal memproses'}',
        kind: ProviderErrorKind.noResult,
      );
    }
    final link = (body['link'] ?? '').toString();
    if (link.isEmpty) {
      throw const ProviderException(
        message: 'spotidown: tidak ada link audio.',
        kind: ProviderErrorKind.noResult,
      );
    }
    final meta = body['metadata'] as Map<String, dynamic>? ?? {};
    final durationMs = (meta['duration'] as num?)?.toInt() ?? 0;

    return MediaInfo(
      title: (meta['title'] ?? 'Spotify Track').toString(),
      author: (meta['artist'] ?? 'Spotify').toString(),
      thumbnail: meta['cover'] as String?,
      durationSec: durationMs > 0 ? durationMs ~/ 1000 : null,
      qualities: [
        MediaQuality(label: 'Audio MP3', itag: link, extension: 'mp3'),
      ],
      source: 'third-party',
      providerName: providerName,
    );
  }

  @override
  Future<String> fetchDownloadUrl(String url, {String quality = 'best'}) async =>
      _resolveQuality(await fetchInfo(url), quality);
}

class SpotifyFallbackProvider implements MediaProvider {
  @override
  String get providerName => 'SpotifyDown';

  @override
  bool canHandle(String url) => _canHandleSpotify(url);

  @override
  Future<MediaInfo> fetchInfo(String url) async {
    final cfg = await RemoteConfig.instance.get(_kFallbackId);
    if (cfg == null || !cfg.enabled) {
      throw const ProviderException(
        message: 'Fallback Spotify provider disabled.',
        kind: ProviderErrorKind.providerDown,
      );
    }

    late final Response<Map<String, dynamic>> response;
    try {
      response = await httpClient.get<Map<String, dynamic>>(
        cfg.url,
        queryParameters: {'url': url},
        options: Options(responseType: ResponseType.json),
      );
    } on DioException catch (e) {
      throw ProviderException(
        message: 'endpoint Spotify tidak merespons (${e.type.name})',
        kind: ProviderErrorKind.providerDown,
        underlyingError: e,
      );
    }

    final body = response.data ?? {};
    if (body['success'] != true) {
      throw ProviderException(
        message: 'spotifydown: ${body['message'] ?? 'gagal memproses'}',
        kind: ProviderErrorKind.noResult,
      );
    }
    final link = (body['link'] ?? '').toString();
    if (link.isEmpty) {
      throw const ProviderException(
        message: 'spotifydown: tidak ada link audio.',
        kind: ProviderErrorKind.noResult,
      );
    }
    final meta = body['metadata'] as Map<String, dynamic>? ?? {};
    final durationMs = (meta['duration_ms'] as num?)?.toInt() ?? 0;

    return MediaInfo(
      title: (meta['name'] ?? 'Spotify Track').toString(),
      author: (meta['artists'] ?? 'Spotify').toString(),
      thumbnail: meta['cover_url'] as String?,
      durationSec: durationMs > 0 ? durationMs ~/ 1000 : null,
      qualities: [
        MediaQuality(label: 'Audio MP3', itag: link, extension: 'mp3'),
      ],
      source: 'third-party',
      providerName: providerName,
    );
  }

  @override
  Future<String> fetchDownloadUrl(String url, {String quality = 'best'}) async =>
      _resolveQuality(await fetchInfo(url), quality);
}
