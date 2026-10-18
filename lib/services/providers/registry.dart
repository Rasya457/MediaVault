import 'provider.dart';
import 'models.dart';
import 'tiktok_provider.dart';
import 'instagram_provider.dart';
import 'youtube_provider.dart';
import 'spotify_provider.dart';
import 'universal_provider.dart';

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
/// 3. Kalau fallback juga throw, coba universal provider.
class ProviderRegistry {
  ProviderRegistry._();
  static final ProviderRegistry instance = ProviderRegistry._();

  final List<_ProviderPair> _pairs = [
    // TikTok: 3-tier chain (TikDownloader → TikWm → SnapTik)
    _ProviderPair(_TikTokChain(), _TikTokChain()),
    _ProviderPair(InstagramFallbackProvider(), InstagramPrimaryProvider()),
    _ProviderPair(YouTubeInnertubeProvider(), YouTubeThirdPartyProvider()),
    _ProviderPair(SpotifyPrimaryProvider(), SpotifyFallbackProvider()),
    _ProviderPair(UniversalMediaProvider(), UniversalMediaProvider()),
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
        message: 'URL tidak didukung. Pastikan link berasal dari salah satu '
            '16 platform yang didukung (TikTok, IG, YouTube, Spotify, X/Twitter, dll).',
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
        // Fallback yang memang dimatikan tidak boleh menutupi error asli:
        // laporkan kegagalan primary agar pesan relevan dengan masalah.
        if (_isDisabled(fallbackError) && primaryError is ProviderException) {
          return Future.error(primaryError);
        }
        throw _wrapLastError(fallbackError, fallbackName);
      }
    }
  }

  bool _isDisabled(Object e) =>
      e is ProviderException && e.message.toLowerCase().contains('disabled');

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

/// TikTok 3-tier chain: TikWm → TikDownloader → SnapTik.
/// Menggunakan pattern chain provider untuk mencoba 3 sumber secara berurutan.
class _TikTokChain implements MediaProvider {
  final _p1 = TikWmProvider();
  final _p2 = TikTokPrimaryProvider();
  final _p3 = SnapTikProvider();

  @override
  String get providerName => 'TikTok';

  @override
  bool canHandle(String url) => _p1.canHandle(url);

  @override
  Future<MediaInfo> fetchInfo(String url) async {
    try {
      return await _p1.fetchInfo(url);
    } catch (_) {}
    try {
      return await _p2.fetchInfo(url);
    } catch (_) {}
    // Jika semua gagal, lempar exception dari provider ketiga
    return await _p3.fetchInfo(url);
  }

  @override
  Future<String> fetchDownloadUrl(String url, {String quality = 'best'}) async {
    final info = await fetchInfo(url);
    if (info.qualities.isEmpty) {
      throw const ProviderException(
        message: 'Tidak ada kualitas tersedia untuk TikTok.',
        kind: ProviderErrorKind.noResult,
      );
    }
    if (quality == 'best') return info.qualities.first.itag;
    return info.qualities
        .firstWhere((q) => q.itag == quality, orElse: () => info.qualities.first)
        .itag;
  }
}
