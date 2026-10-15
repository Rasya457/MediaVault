import 'dart:io';

import 'package:dio/dio.dart';

import '../../core/network/api_client.dart' show httpClient;

/// Dilempar saat unduhan dibatalkan via [CancelToken].
class DownloadCancelled implements Exception {
  const DownloadCancelled();
}

/// Unduh file via HTTP ke direktori temp. Murni Dart + Dio
/// (tanpa plugin platform) sehingga unit-testable penuh.
class DownloadService {
  final Dio dio;

  DownloadService({Dio? dio}) : dio = dio ?? httpClient;

  /// Unduh [url] ke file temp bernama [filename].
  ///
  /// [headers] dikirim apa adanya (misal User-Agent client Innertube).
  /// Progress via [onProgress]; batalkan via [cancelToken].
  /// Setiap unduhan masuk subfolder temp unik, jadi nama file yang sama
  /// tidak saling menimpa dan basename hasilnya tetap [filename].
  Future<File> downloadToTemp({
    required String url,
    required String filename,
    Map<String, String>? headers,
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final dir = await Directory.systemTemp.createTemp('mv_');
    final path = '${dir.path}/${_sanitize(filename)}';
    try {
      await dio.download(
        url,
        path,
        onReceiveProgress: onProgress,
        cancelToken: cancelToken,
        deleteOnError: true,
        options: headers == null ? null : Options(headers: headers),
      );
    } on DioException catch (e) {
      await _deleteDir(dir);
      if (e.type == DioExceptionType.cancel) {
        throw const DownloadCancelled();
      }
      rethrow;
    } catch (_) {
      await _deleteDir(dir);
      rethrow;
    }
    return File(path);
  }

  /// Unduh stream video-only dan audio-only berurutan, dengan progress
  /// gabungan (0..total video + audio) lewat [onProgress].
  ///
  /// Kalau salah satu gagal atau dibatalkan, file yang sudah terunduh
  /// otomatis dihapus. Hasilnya siap di-merge (ffmpeg) oleh pemanggil.
  Future<({File video, File audio})> downloadPairToTemp({
    required String videoUrl,
    required String audioUrl,
    required String baseName,
    String videoExt = 'mp4',
    String audioExt = 'm4a',
    Map<String, String>? headers,
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    var videoDone = 0;
    var videoTotal = 0;
    var audioDone = 0;
    var audioTotal = 0;

    void report() {
      if (onProgress == null) return;
      // Total gabungan baru valid kalau kedua total sudah diketahui.
      // Sebelum itu, laporkan total 0 supaya UI menampilkan indeterminate.
      final bothKnown = videoTotal > 0 && audioTotal > 0;
      onProgress(
        videoDone + audioDone,
        bothKnown ? videoTotal + audioTotal : 0,
      );
    }

    final video = await downloadToTemp(
      url: videoUrl,
      filename: '$baseName.video.$videoExt',
      headers: headers,
      cancelToken: cancelToken,
      onProgress: (r, t) {
        videoDone = r;
        if (t > 0) videoTotal = t;
        report();
      },
    );

    try {
      final audio = await downloadToTemp(
        url: audioUrl,
        filename: '$baseName.audio.$audioExt',
        headers: headers,
        cancelToken: cancelToken,
        onProgress: (r, t) {
          audioDone = r;
          if (t > 0) audioTotal = t;
          report();
        },
      );
      return (video: video, audio: audio);
    } catch (_) {
      await cleanup([video]);
      rethrow;
    }
  }

  /// Hapus file temp beserta subfolder unik miliknya (aman dipanggil
  /// berulang atau pada file yang sudah tidak ada).
  Future<void> cleanup(Iterable<File> files) async {
    for (final f in files) {
      try {
        if (await f.exists()) await f.delete();
        final parent = f.parent;
        if (parent.path != Directory.systemTemp.path &&
            parent.uri.pathSegments
                .where((s) => s.isNotEmpty)
                .last
                .startsWith('mv_')) {
          await _deleteDir(parent);
        }
      } catch (_) {
        // Best-effort: file temp yang gagal dihapus dibersihkan OS nanti.
      }
    }
  }

  static Future<void> _deleteDir(Directory dir) async {
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
  }

  static String _sanitize(String name) {
    final clean = name.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '').trim();
    return clean.isEmpty ? 'download' : clean;
  }
}