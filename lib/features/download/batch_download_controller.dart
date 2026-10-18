import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../services/providers/spotify_provider.dart';
import '../history/history_repository.dart';
import 'download_service.dart';
import 'media_merger.dart';
import 'storage_service.dart';

enum BatchItemStatus { queued, downloading, done, failed }

/// Satu lagu dalam antrian unduh playlist/album.
class BatchItem {
  BatchItem({
    required this.url,
    required this.filename,
    required this.title,
    this.artist = '',
    this.headers,
    this.thumbnail,
    this.previewUrl,
  });

  final String url;
  final String filename;
  final String title;
  final String artist;
  final Map<String, String>? headers;

  /// Cover playlist/album untuk riwayat unduhan (tidak ditampilkan
  /// di daftar lagu).
  final String? thumbnail;

  /// URL pratinjau audio pendek (jika tersedia).
  final String? previewUrl;

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

      // Jika URL lagu berupa identifier spotify / spotify_track atau preview 30s:
      // resolve link audio full track agar file yang diunduh adalah lagu penuh utuh.
      if (dlUrl.startsWith('spotify') ||
          dlUrl.isEmpty ||
          dlUrl.contains('p.scdn.co')) {
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

      final raw = await _downloads.downloadToTemp(
        url: dlUrl,
        filename: 'raw_${item.filename}',
        headers: dlHeaders,
        onProgress: (received, total) {
          item.progress = total > 0 ? (received / total) * 0.8 : -1;
          notifyListeners();
        },
        cancelToken: token,
      );
      try {
        final outPath = '${raw.parent.path}/${item.filename}';
        File converted;
        try {
          converted = await _merger.convertToMp3(
            input: raw,
            outputPath: outPath,
          );
        } catch (_) {
          // Sumber sering sudah berupa MP3 jadi — simpan apa adanya.
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
      } finally {
        await _downloads.cleanup([raw]);
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
