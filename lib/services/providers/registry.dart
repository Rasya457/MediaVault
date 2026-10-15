import 'provider.dart';
import 'models.dart';
import 'tiktok_provider.dart';
import 'instagram_provider.dart';
import 'youtube_provider.dart';
import 'spotify_provider.dart';

/// Pasangan primary + fallback untuk satu platform.
class _ProviderPair {
  const _ProviderPair(this.primary, this.fallback);
  final MediaProvider primary;
  final MediaProvider fallback;
}

/// Registry yang mengelola semua provider dan logika fallback.
///
/// Urutan eksekusi untuk setiap operasi:
/// 1. Pilih pair provider yang [canHandle] URL.
/// 2. Coba primary - kalau throw, lanjut ke fallback.
/// 3. Kalau fallback juga throw, bungkus dengan [ProviderException]
///    yang ramah user sesuai jenis error.
class ProviderRegistry {
  ProviderRegistry._();
  static final ProviderRegistry instance = ProviderRegistry._();

  final List<_ProviderPair> _pairs = [
    _ProviderPair(TikTokPrimaryProvider(), TikWmProvider()),
    _ProviderPair(InstagramFallbackProvider(), InstagramPrimaryProvider()),
    _ProviderPair(YouTubeInnertubeProvider(), YouTubeFallbackProvider()),
    _ProviderPair(SpotifyPrimaryProvider(), SpotifyFallbackProvider()),
  ];

  _ProviderPair? _findPair(String url) {
    for (final pair in _pairs) {
      if (pair.primary.canHandle(url)) return pair;
    }
    return null;
  }

  Future<MediaInfo> fetchInfo(String url) async {
    final pair = _findPair(url);
    if (pair == null) {
      throw const ProviderException(
        message: 'URL tidak dikenali. Pastikan link berasal dari '
            'TikTok, Instagram, YouTube, atau Spotify.',
        kind: ProviderErrorKind.invalidUrl,
      );
    }
    return _tryWithFallback(
      primary: () => pair.primary.fetchInfo(url),
      fallback: () => pair.fallback.fetchInfo(url),
      primaryName: pair.primary.providerName,
      fallbackName: pair.fallback.providerName,
    );
  }

  Future<String> fetchDownloadUrl(
    String url, {
    String quality = 'best',
  }) async {
    final pair = _findPair(url);
    if (pair == null) {
      throw const ProviderException(
        message: 'URL tidak dikenali. Pastikan link berasal dari '
            'TikTok, Instagram, YouTube, atau Spotify.',
        kind: ProviderErrorKind.invalidUrl,
      );
    }
    return _tryWithFallback(
      primary: () => pair.primary.fetchDownloadUrl(url, quality: quality),
      fallback: () => pair.fallback.fetchDownloadUrl(url, quality: quality),
      primaryName: pair.primary.providerName,
      fallbackName: pair.fallback.providerName,
    );
  }

  Future<T> _tryWithFallback<T>({
    required Future<T> Function() primary,
    required Future<T> Function() fallback,
    required String primaryName,
    required String fallbackName,
  }) async {
    try {
      return await primary();
    } catch (primaryError) {
      try {
        return await fallback();
      } catch (fallbackError) {
        throw _wrapLastError(fallbackError, fallbackName);
      }
    }
  }

  ProviderException _wrapLastError(Object error, String providerName) {
    if (error is ProviderException) return error;

    final msg = error.toString().toLowerCase();
    if (msg.contains('timeout') || msg.contains('connection')) {
      return ProviderException(
        message: 'Layanan $providerName tidak merespons. '
            'Periksa koneksi atau coba lagi nanti.',
        kind: ProviderErrorKind.providerDown,
        underlyingError: error,
      );
    }
    if (msg.contains('not found') ||
        msg.contains('no result') ||
        msg.contains('private')) {
      return ProviderException(
        message: 'Media tidak ditemukan. '
            'Konten mungkin privat atau sudah dihapus.',
        kind: ProviderErrorKind.noResult,
        underlyingError: error,
      );
    }
    return ProviderException(
      message: 'Terjadi kesalahan tak terduga dari $providerName.',
      kind: ProviderErrorKind.providerDown,
      underlyingError: error,
    );
  }
}
