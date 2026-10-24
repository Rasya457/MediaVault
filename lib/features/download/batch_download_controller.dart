import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../services/providers/spotify_provider.dart';
import '../history/history_repository.dart';
import 'download_service.dart';
import 'media_merger.dart';
import 'storage_service.dart';

enum BatchItemStatus { queued, downloading, done, failed }

/// Satu item dalam antrian unduh playlist/album/carousel foto.
class BatchItem {
  BatchItem({
    required this.url,
    required this.filename,
    required this.title,
    this.artist = '',
    this.extension = 'mp3',
    this.headers,
    this.thumbnail,
    this.previewUrl,
  });

  final String url;
  final String filename;
  final String title;
  final String artist;

  /// Ekstensi file hasil akhir: 'mp3', 'mp4', 'jpg', 'png', dll.
  final String extension;

  final Map<String, String>? headers;

  /// Cover playlist/album untuk riwayat unduhan.
  final String? thumbnail;

  /// URL pratinjau audio pendek (jika tersedia).
  final String? previewUrl;

  bool get isImage {
    final ext = extension.toLowerCase();
    return ext == 'jpg' || ext == 'jpeg' || ext == 'png' ||
        ext == 'webp' || ext == 'heic' || ext == 'gif';
  }

  bool get isVideo {
    final ext = extension.toLowerCase();
    return ext == 'mp4' || ext == 'mov' || ext == 'webm' || ext == 'mkv';
  }

  BatchItemStatus status = BatchItemStatus.queued;

  /// 0..1 saat total diketahui, -1 bila tidak.
  double progress = 0;
  String? savedPath;
  String? error;
}

/// Unduh seluruh lagu playlist secara paralel (default 5 worker,
/// mengikuti arsitektur referensi) lalu simpan sebagai audio.
class BatchDownloadController extends ChangeNotifier {
  BatchDownloadController({
    DownloadService? downloadService,
    StorageService? storageService,
    MediaMerger? mediaMerger,
    this.concurrency = 5,
  })  : _downloads = downloadService ?? DownloadService(),
        _storage = storageService ?? StorageService(),
        _merger = mediaMerger ?? FFmpegMediaMerger();

  final DownloadService _downloads;
  final StorageService _storage;
  final MediaMerger _merger;

  /// Jumlah unduh paralel.
  final int concurrency;

  final List<BatchItem> items = [];
  bool running = false;
  bool _cancelled = false;

  int get doneCount =>
      items.where((i) => i.status == BatchItemStatus.done).length;
  int get failedCount =>
      items.where((i) => i.status == BatchItemStatus.failed).length;

  /// 0..1 proporsi item yang selesai (sukses + gagal).
  double get overallProgress =>
      items.isEmpty ? 0 : (doneCount + failedCount) / items.length;

  /// Isi ulang antrian dari daftar track (mereset state).
  void prepare(Iterable<BatchItem> tracks) {
    items
      ..clear()
      ..addAll(tracks);
    running = false;
    _cancelled = false;
    notifyListeners();
  }

  /// Jalankan seluruh antrian dengan [concurrency] worker paralel.
  Future<void> start() async {
    if (running || items.isEmpty) return;
    for (final i in items) {
      i
        ..status = BatchItemStatus.queued
        ..progress = 0
        ..error = null;
    }
    await _runPool(items);
  }

  /// Unduh satu lagu saja (ketuk baris) — antrian lain tidak tersentuh.
  Future<void> startOne(BatchItem item) async {
    if (running || !items.contains(item)) return;
    await _runPool([item]);
  }

  Future<void> _runPool(List<BatchItem> targets) async {
    running = true;
    _cancelled = false;
    notifyListeners();

    var next = 0;
    Future<void> worker() async {
      while (!_cancelled) {
        final i = next++;
        if (i >= targets.length) break;
        await _runItem(targets[i]);
      }
    }

    final workers = List.generate(concurrency, (_) => worker());
    await Future.wait(workers);
    running = false;
    notifyListeners();
  }

  /// Batalkan seluruh unduhan berjalan; item berikutnya tidak dimulai.
  void cancelAll() {
    _cancelled = true;
    for (final f in _activeTokens) {
      f.cancel();
    }
    notifyListeners();
  }

  final List<CancelToken> _activeTokens = [];

  Future<void> _runItem(BatchItem item) async {
    item
      ..status = BatchItemStatus.downloading
      ..progress = 0
      ..error = null;
    notifyListeners();

    final token = CancelToken();
    _activeTokens.add(token);
    try {
      String dlUrl = item.url;
      Map<String, String>? dlHeaders = item.headers;

      // Resolve Spotify track identifier → full YouTube audio stream.
      if (!item.isImage &&
          !item.isVideo &&
          (dlUrl.startsWith('spotify') ||
              dlUrl.isEmpty ||
              dlUrl.contains('p.scdn.co'))) {
        try {
          final resolved = await SpotifyProvider.resolveFullTrackAudio(
            item.artist,
            item.title,
          );
          if (resolved != null && resolved.isNotEmpty) {
            dlUrl = resolved;
            dlHeaders = const {
              'User-Agent':
                  'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Mobile Safari/537.36',
            };
          } else if (item.previewUrl != null && item.previewUrl!.isNotEmpty) {
            dlUrl = item.previewUrl!;
          }
        } catch (_) {}
      }

      final rawFilename = item.isImage
          ? item.filename
          : 'raw_${item.filename}';
      final raw = await _downloads.downloadToTemp(
        url: dlUrl,
        filename: rawFilename,
        headers: dlHeaders,
        onProgress: (received, total) {
          item.progress = total > 0
              ? (received / total) * (item.isImage ? 1.0 : 0.8)
              : -1;
          notifyListeners();
        },
        cancelToken: token,
      );

      try {
        if (item.isImage) {
          // ---- Foto: langsung simpan ke galeri tanpa konversi ----
          item.progress = 1.0;
          notifyListeners();
          await _storage.saveImage(raw);
          item
            ..savedPath = raw.path
            ..status = BatchItemStatus.done;
          try {
            await HistoryRepository.instance.add(
              DownloadHistoryEntry(
                id: '${DateTime.now().millisecondsSinceEpoch}_${item.filename}',
                url: item.url,
                title: item.title,
                platform: 'Instagram',
                quality: 'Photo HD',
                extension: BatchDownloadController.extOf(raw.path),
                timestamp: DateTime.now(),
                thumbnail: item.thumbnail ?? item.url,
                savedPath: raw.path,
              ),
            );
          } catch (e) {
            debugPrint('Gagal menyimpan riwayat foto: $e');
          }
        } else if (item.isVideo) {
          // ---- Video: simpan ke galeri (tanpa merge/konversi) ----
          item.progress = 1.0;
          notifyListeners();
          await _storage.saveVideo(raw);
          item
            ..savedPath = raw.path
            ..status = BatchItemStatus.done;
          try {
            await HistoryRepository.instance.add(
              DownloadHistoryEntry(
                id: '${DateTime.now().millisecondsSinceEpoch}_${item.filename}',
                url: item.url,
                title: item.title,
                platform: 'Instagram',
                quality: 'Video HD',
                extension: BatchDownloadController.extOf(raw.path),
                timestamp: DateTime.now(),
                thumbnail: item.thumbnail,
                savedPath: raw.path,
              ),
            );
          } catch (e) {
            debugPrint('Gagal menyimpan riwayat video: $e');
          }
        } else {
          // ---- Audio/MP3: konversi via FFmpeg lalu simpan ----
          final outPath = '${raw.parent.path}/${item.filename}';
          File converted;
          try {
            converted = await _merger.convertToMp3(
              input: raw,
              outputPath: outPath,
            );
          } catch (_) {
            if (await raw.exists() && await raw.length() > 0) {
              converted = await raw.copy(outPath);
            } else {
              rethrow;
            }
          }
          item.progress = 1.0;
          final stored = await _storage.saveAudio(converted);
          item
            ..savedPath = stored.path
            ..status = BatchItemStatus.done;
          try {
            await HistoryRepository.instance.add(
              DownloadHistoryEntry(
                id: '${DateTime.now().millisecondsSinceEpoch}_${item.filename}',
                url: item.url,
                title: item.title,
                platform: 'Spotify',
                quality: 'MP3',
                extension: BatchDownloadController.extOf(stored.path),
                timestamp: DateTime.now(),
                thumbnail: item.thumbnail,
                savedPath: stored.path,
              ),
            );
          } catch (e) {
            debugPrint('Gagal menyimpan ke riwayat: $e');
          }
        }
      } finally {
        if (!item.isImage) await _downloads.cleanup([raw]);
      }
    } on DownloadCancelled {
      item
        ..status = BatchItemStatus.failed
        ..error = 'Dibatalkan';
    } catch (e) {
      item
        ..status = BatchItemStatus.failed
        ..error = _friendly(e);
    } finally {
      _activeTokens.remove(token);
      notifyListeners();
    }
  }

  static String extOf(String path) => path.split('.').last.toLowerCase();

  String _friendly(Object e) {
    if (e is StorageException) return e.message;
    if (e is DioException) return 'Unduhan gagal (${e.type.name})';
    return 'Unduhan gagal: $e';
  }
}
