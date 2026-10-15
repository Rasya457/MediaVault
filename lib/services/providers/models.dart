/// Kualitas yang tersedia untuk satu media.
class MediaQuality {
  const MediaQuality({
    required this.label,
    required this.itag,
    this.extension = 'mp4',
    this.hasAudio,
    this.audioUrl,
    this.sizeBytes,
  });

  /// Label tampil ke user, misal 'HD (No Watermark)'.
  final String label;

  /// Identifier internal sekaligus URL utama:
  /// itag YouTube, atau URL langsung (TikTok).
  /// Untuk format yang perlu merge, ini adalah URL video-only.
  final String itag;

  /// Ekstensi file hasil akhir.
  final String extension;

  /// true = muxed (video + audio dalam satu stream),
  /// false = video-only (adaptive), null = tidak diketahui.
  final bool? hasAudio;

  /// URL stream audio terpisah. Terisi hanya kalau [needsMerge] true.
  final String? audioUrl;

  /// Perkiraan ukuran total (video + audio) dalam byte, kalau diketahui.
  final int? sizeBytes;

  /// True kalau video dan audio harus diunduh terpisah lalu digabung.
  bool get needsMerge => hasAudio == false && audioUrl != null;

  /// URL stream video (alias dari [itag] supaya kode downloader lebih jelas).
  String get videoUrl => itag;

  /// Ukuran dalam format singkat, misal '48.3 MB'. Null kalau tidak diketahui.
  String? get sizeLabel {
    final s = sizeBytes;
    if (s == null || s <= 0) return null;
    const units = ['B', 'KB', 'MB', 'GB'];
    var v = s.toDouble();
    var i = 0;
    while (v >= 1024 && i < units.length - 1) {
      v /= 1024;
      i++;
    }
    return '${v.toStringAsFixed(i == 0 ? 0 : 1)} ${units[i]}';
  }

  @override
  String toString() =>
      'MediaQuality($label, .$extension, hasAudio: $hasAudio, '
      'needsMerge: $needsMerge, size: $sizeBytes)';
}

/// Hasil metadata media dari provider.
class MediaInfo {
  const MediaInfo({
    required this.title,
    required this.author,
    this.thumbnail,
    this.durationSec,
    required this.qualities,
    required this.source,
    required this.providerName,
    this.downloadHeaders = const {},
  });

  final String title;
  final String author;
  final String? thumbnail;
  final int? durationSec;
  final List<MediaQuality> qualities;

  /// 'direct' = URL berasal langsung dari platform CDN.
  /// 'third-party' = URL diproses lewat layanan pihak ketiga.
  final String source;

  /// Nama provider yang berhasil menangani request ini.
  final String providerName;

  /// Header yang wajib dikirim saat mengunduh URL di [qualities]
  /// (misal User-Agent client Innertube). Kosong untuk provider lain.
  final Map<String, String> downloadHeaders;
}