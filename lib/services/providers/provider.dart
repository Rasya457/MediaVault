import 'models.dart';

/// Kontrak yang wajib diimplementasi setiap provider platform.
abstract class MediaProvider {
  /// Nama unik provider ini (untuk logging & error message).
  String get providerName;

  /// Kembalikan true jika provider ini sanggup menangani [url].
  bool canHandle(String url);

  /// Ambil metadata media dari [url].
  /// Lempar [ProviderException] jika gagal.
  Future<MediaInfo> fetchInfo(String url);

  /// Ambil URL download langsung untuk [url] dengan kualitas [quality].
  /// [quality] mengacu pada [MediaQuality.itag].
  /// Lempar [ProviderException] jika gagal.
  Future<String> fetchDownloadUrl(String url, {String quality = 'best'});
}

/// Exception terstruktur dari layer provider.
class ProviderException implements Exception {
  const ProviderException({
    required this.message,
    required this.kind,
    this.underlyingError,
  });

  final String message;
  final ProviderErrorKind kind;
  final Object? underlyingError;

  @override
  String toString() => 'ProviderException($kind): $message';
}

/// Kategori error — dipakai UI untuk memilih pesan yang tepat.
enum ProviderErrorKind {
  /// URL tidak dikenali oleh provider mana pun.
  invalidUrl,

  /// Provider down atau timeout.
  providerDown,

  /// Tidak ada media yang bisa diambil (misal konten privat).
  noResult,
}
