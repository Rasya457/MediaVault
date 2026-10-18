import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediavault/features/download/batch_download_controller.dart';
import 'package:mediavault/features/download/download_service.dart';
import 'package:mediavault/features/download/media_merger.dart';
import 'package:mediavault/features/download/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeDownloads extends DownloadService {
  Set<String> failUrls = {};
  File? fileToReturn;
  Duration delay = Duration.zero;
  int active = 0;
  int maxActive = 0;

  @override
  Future<File> downloadToTemp({
    required String url,
    required String filename,
    Map<String, String>? headers,
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    if (failUrls.contains(url)) {
      throw DioException(
        requestOptions: RequestOptions(path: ''),
        type: DioExceptionType.connectionError,
      );
    }
    active++;
    if (active > maxActive) maxActive = active;
    await Future<void>.delayed(delay);
    active--;
    return fileToReturn ?? File('/tmp/${filename}_raw');
  }

  @override
  Future<void> cleanup(Iterable<File> files) async {}
}

class _FakeMerger implements MediaMerger {
  @override
  Future<File> mergeVideoAudio({
    required File video,
    required File audio,
    required String outputPath,
  }) async =>
      File(outputPath);

  @override
  Future<File> convertToMp3({
    required File input,
    required String outputPath,
  }) async =>
      File(outputPath);
}

class _FakeStorage extends StorageService {
  final calls = <String>[];

  @override
  Future<void> saveImage(File file) async => calls.add('image');

  @override
  Future<void> saveVideo(File file) async => calls.add('video');

  @override
  Future<File> saveAudio(File file) async {
    calls.add('audio');
    return file;
  }
}

BatchItem _track(String id) => BatchItem(
      url: 'https://cdn.example/$id.mp3',
      filename: '$id.mp3',
      title: 'Lagu $id',
      artist: 'Artis $id',
    );

void main() {
  setUp(() {
    // Riwayat unduhan ditulis oleh controller — beri mock storage.
    SharedPreferences.setMockInitialValues({});
  });

  group('BatchDownloadController', () {
    test('semua lagu selesai → done + disimpan sebagai audio', () async {
      final dl = _FakeDownloads();
      final storage = _FakeStorage();
      final c = BatchDownloadController(
        downloadService: dl,
        storageService: storage,
        mediaMerger: _FakeMerger(),
        concurrency: 3,
      );
      c.prepare([_track('a'), _track('b'), _track('c')]);

      await c.start();

      expect(c.running, isFalse);
      expect(c.doneCount, 3);
      expect(c.failedCount, 0);
      expect(storage.calls, ['audio', 'audio', 'audio']);
      expect(
        c.items.every((i) => i.status == BatchItemStatus.done),
        isTrue,
      );
    });

    test('satu lagu gagal tidak menghentikan yang lain', () async {
      final dl = _FakeDownloads()..failUrls = {'https://cdn.example/b.mp3'};
      final c = BatchDownloadController(
        downloadService: dl,
        storageService: _FakeStorage(),
        mediaMerger: _FakeMerger(),
      );
      c.prepare([_track('a'), _track('b'), _track('c')]);

      await c.start();

      expect(c.doneCount, 2);
      expect(c.failedCount, 1);
      expect(c.items[1].status, BatchItemStatus.failed);
      expect(c.items[1].error, contains('Unduhan gagal'));
      expect(c.items[0].status, BatchItemStatus.done);
      expect(c.items[2].status, BatchItemStatus.done);
    });

    test('paralel dibatasi jumlah worker', () async {
      final dl = _FakeDownloads()..delay = const Duration(milliseconds: 30);
      final c = BatchDownloadController(
        downloadService: dl,
        storageService: _FakeStorage(),
        mediaMerger: _FakeMerger(),
        concurrency: 2,
      );
      c.prepare(List.generate(6, (i) => _track('t$i')));

      await c.start();

      expect(c.doneCount, 6);
      expect(dl.maxActive, 2);
    });

    test('cancelAll menghentikan antrian berikutnya', () async {
      final dl = _FakeDownloads()..delay = const Duration(milliseconds: 250);
      final c = BatchDownloadController(
        downloadService: dl,
        storageService: _FakeStorage(),
        mediaMerger: _FakeMerger(),
        concurrency: 2,
      );
      c.prepare(List.generate(10, (i) => _track('t$i')));

      final future = c.start();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      c.cancelAll();
      await future;

      expect(c.running, isFalse);
      expect(c.doneCount, 2); // 2 worker selesai 1 lagu masing-masing
      expect(
        c.items.where((i) => i.status == BatchItemStatus.queued).length,
        8,
      );
    });

    test('startOne mengunduh satu lagu tanpa menyentuh yang lain', () async {
      final dl = _FakeDownloads();
      final c = BatchDownloadController(
        downloadService: dl,
        storageService: _FakeStorage(),
        mediaMerger: _FakeMerger(),
      );
      c.prepare([_track('a'), _track('b')]);

      await c.startOne(c.items[1]);

      expect(c.items[1].status, BatchItemStatus.done);
      expect(c.items[0].status, BatchItemStatus.queued);
      expect(c.doneCount, 1);
    });
  });
}
