import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../services/providers/models.dart';
import 'download_service.dart';
import 'media_merger.dart';
import 'storage_service.dart';

enum DownloadStatus { idle, downloading, success, error }

/// State unduhan satu file. ChangeNotifier murni agar tidak mengunci
/// pilihan state management.
class DownloadController extends ChangeNotifier {
  final DownloadService _downloads;
  final StorageService _storage;
  final MediaMerger _merger;

  DownloadController({
    DownloadService? downloadService,
    StorageService? storageService,
    MediaMerger? mediaMerger,
  })  : _downloads = downloadService ?? DownloadService(),
        _storage = storageService ?? StorageService(),
        _merger = mediaMerger ?? const FFmpegMediaMerger();

  DownloadStatus status = DownloadStatus.idle;

  /// 0..1 saat total diketahui, -1 jika tidak.
  double progress = 0;
  String? savedLabel;
  String? errorMessage;
  CancelToken? _cancelToken;

  Future<void> downloadMedia({
    required String url,
    required String filename,
    MediaQuality? quality,
    Map<String, String>? headers,
  }) async {
    status = DownloadStatus.downloading;
    progress = 0;
    savedLabel = null;
    errorMessage = null;
    notifyListeners();

    _cancelToken = CancelToken();
    try {
      final File file;
      if (quality != null && quality.needsMerge && quality.audioUrl != null) {
        final pair = await _downloads.downloadPairToTemp(
          videoUrl: quality.videoUrl,
          audioUrl: quality.audioUrl!,
          baseName: filename.replaceAll(RegExp(r'\.[^.]+$'), ''),
          videoExt: 'mp4',
          audioExt: 'm4a',
          headers: headers,
          cancelToken: _cancelToken,
          onProgress: (received, total) {
            progress = total > 0 ? received / total : -1;
            notifyListeners();
          },
        );
        try {
          final outPath =
              '${pair.video.parent.path}/merged_${_sanitize(filename)}';
          file = await _merger.mergeVideoAudio(
            video: pair.video,
            audio: pair.audio,
            outputPath: outPath,
          );
        } finally {
          await _downloads.cleanup([pair.video, pair.audio]);
        }
      } else {
        file = await _downloads.downloadToTemp(
          url: url,
          filename: filename,
          headers: headers,
          onProgress: (received, total) {
            progress = total > 0 ? received / total : -1;
            notifyListeners();
          },
          cancelToken: _cancelToken,
        );
      }

      savedLabel = await _store(file, filename);
      status = DownloadStatus.success;
      notifyListeners();
    } on DownloadCancelled {
      status = DownloadStatus.idle;
      progress = 0;
      notifyListeners();
    } catch (e) {
      status = DownloadStatus.error;
      errorMessage = _friendly(e);
      notifyListeners();
    }
  }

  void cancel() => _cancelToken?.cancel();

  Future<String> _store(File file, String filename) async {
    final ext = filename.split('.').last.toLowerCase();
    switch (mediaKindForExtension(ext)) {
      case MediaKind.image:
        await _storage.saveImage(file);
        return 'Foto tersimpan di galeri (${StorageService.album})';
      case MediaKind.video:
        await _storage.saveVideo(file);
        return 'Video tersimpan di galeri (${StorageService.album})';
      case MediaKind.audio:
        await _storage.saveAudio(file);
        return 'Audio tersimpan di aplikasi';
      case null:
        throw StorageException('Format tidak didukung: .$ext');
    }
  }

  static String _sanitize(String name) {
    final clean = name.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '').trim();
    return clean.isEmpty ? 'download' : clean;
  }

  String _friendly(Object e) {
    if (e is StorageException) return e.message;
    if (e is DioException) return 'Unduhan gagal (${e.type.name})';
    return 'Unduhan gagal: $e';
  }
}
