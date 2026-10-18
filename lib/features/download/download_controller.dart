import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../services/providers/models.dart';
import '../../services/providers/spotify_provider.dart';
import '../history/history_repository.dart';
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
        _merger = mediaMerger ?? FFmpegMediaMerger();

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
    String? title,
    String? platform,
    String? thumbnail,
  }) async {
    status = DownloadStatus.downloading;
    progress = 0;
    savedLabel = null;
    errorMessage = null;
    notifyListeners();

    _cancelToken = CancelToken();
    try {
      String dlUrl = url;
      Map<String, String>? dlHeaders = headers;

      if (dlUrl.startsWith('spotify') ||
          (platform?.toLowerCase() == 'spotify' && dlUrl.contains('p.scdn.co'))) {
        try {
          final resolved = await SpotifyProvider.resolveFullTrackAudio(
            platform ?? '',
            title ?? '',
          );
          if (resolved != null && resolved.isNotEmpty) {
            dlUrl = resolved;
            dlHeaders = const {
              'User-Agent':
                  'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Mobile Safari/537.36',
            };
          }
        } catch (_) {}
      }

      File file;
      final isMp3 = (quality != null && quality.extension.toLowerCase() == 'mp3') ||
          filename.toLowerCase().endsWith('.mp3');

      if (isMp3) {
        // Unduh stream sumber (bisa audio stream atau video stream)
        // lalu ekstrak & konversi ke file MP3 resmi via FFmpeg.
        final rawTemp = await _downloads.downloadToTemp(
          url: dlUrl,
          filename: 'raw_${_sanitize(filename)}',
          headers: dlHeaders,
          onProgress: (received, total) {
            progress = total > 0 ? (received / total) * 0.8 : -1;
            notifyListeners();
          },
          cancelToken: _cancelToken,
        );
        try {
          final outPath = '${rawTemp.parent.path}/${_sanitize(filename)}';
          try {
            file = await _merger.convertToMp3(
              input: rawTemp,
              outputPath: outPath,
            );
          } catch (_) {
            if (await rawTemp.exists() && await rawTemp.length() > 0) {
              file = await rawTemp.copy(outPath);
            } else {
              rethrow;
            }
          }
          progress = 1.0;
          notifyListeners();
        } finally {
          await _downloads.cleanup([rawTemp]);
        }
      } else if (quality != null && quality.needsMerge && quality.audioUrl != null) {
        final pair = await _downloads.downloadPairToTemp(
          videoUrl: quality.videoUrl,
          audioUrl: quality.audioUrl!,
          baseName: filename.replaceAll(RegExp(r'\.[^.]+$'), ''),
          videoExt: quality.extension,
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

      savedLabel = await _store(file);
      status = DownloadStatus.success;

      // Catat riwayat unduhan
      try {
        await HistoryRepository.instance.add(
          DownloadHistoryEntry(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            url: url,
            title: title ?? filename,
            platform: platform ?? 'Media',
            quality: quality?.label ?? 'Default',
            extension: _extensionOf(file.path),
            timestamp: DateTime.now(),
            thumbnail: thumbnail,
            savedPath: file.path,
          ),
        );
      } catch (e) {
        debugPrint('Gagal menyimpan ke riwayat: $e');
      }

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

  Future<String> _store(File file) async {
    final ext = _extensionOf(file.path);
    if (ext == 'webm' || ext == 'mkv') {
      throw const StorageException(
        'Video .webm tidak bisa masuk galeri. Pilih kualitas MP4.',
      );
    }
    switch (mediaKindForExtension(ext)) {
      case MediaKind.image:
        await _storage.saveImage(file);
        return 'Foto tersimpan di galeri (${StorageService.album})';
      case MediaKind.video:
        await _storage.saveVideo(file);
        return 'Video tersimpan di galeri (${StorageService.album})';
      case MediaKind.audio:
        await _storage.saveAudio(file);
        return 'Audio tersimpan (${StorageService.album})';
      case null:
        throw StorageException('Format tidak didukung: .$ext');
    }
  }

  /// Ekstensi dari path file sebenarnya — konversi MP3 bisa berakhir .m4a.
  static String _extensionOf(String path) =>
      path.split('.').last.toLowerCase();

  static String _sanitize(String name) {
    final clean = name.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '').trim();
    return clean.isEmpty ? 'download' : clean;
  }

  String _friendly(Object e) {
    if (e is StorageException) return e.message;
    if (e is DioException) return 'Unduhan gagal (${e.type.name})';
    final msg = e.toString();
    if (msg.contains('FFmpeg') || msg.contains('merge')) {
      return 'Gagal menggabung video + audio. Coba kualitas tanpa label '
          '"PERLU GABUNG" (yang sudah ada audionya).';
    }
    return 'Unduhan gagal: $e';
  }
}
