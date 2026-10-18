import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediavault/features/download/download_controller.dart';
import 'package:mediavault/features/download/download_service.dart';
import 'package:mediavault/features/download/media_merger.dart';
import 'package:mediavault/features/download/storage_service.dart';
import 'package:mediavault/services/providers/models.dart';

class _FakeDownloads extends DownloadService {
  File? fileToReturn;
  Object? error;

  @override
  Future<File> downloadToTemp({
    required String url,
    required String filename,
    Map<String, String>? headers,
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    if (error != null) throw error!;
    onProgress?.call(50, 100);
    return fileToReturn!;
  }

  @override
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
    if (error != null) throw error!;
    onProgress?.call(100, 100);
    return (
      video: File('/tmp/$baseName.video.mp4'),
      audio: File('/tmp/$baseName.audio.m4a'),
    );
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

void main() {
  group('mediaKindForExtension', () {
    test('peta ekstensi', () {
      expect(mediaKindForExtension('mp4'), MediaKind.video);
      expect(mediaKindForExtension('JPG'), MediaKind.image);
      expect(mediaKindForExtension('mp3'), MediaKind.audio);
      expect(mediaKindForExtension('m4a'), MediaKind.audio);
      expect(mediaKindForExtension('xyz'), isNull);
    });
  });

  group('DownloadController', () {
    test('sukses video -> success + label galeri', () async {
      final dl = _FakeDownloads()..fileToReturn = File('/tmp/x.mp4');
      final storage = _FakeStorage();
      final c = DownloadController(
        downloadService: dl,
        storageService: storage,
      );

      await c.downloadMedia(url: 'https://cdn.example/x', filename: 'x.mp4');

      expect(c.status, DownloadStatus.success);
      expect(c.savedLabel, contains('galeri'));
      expect(storage.calls, ['video']);
      expect(c.progress, 0.5);
    });

    test('unduh needsMerge -> panggil downloadPairToTemp + merge + simpan', () async {
      final dl = _FakeDownloads();
      final storage = _FakeStorage();
      final merger = _FakeMerger();
      final c = DownloadController(
        downloadService: dl,
        storageService: storage,
        mediaMerger: merger,
      );

      const quality = MediaQuality(
        label: '1080p',
        itag: 'https://v.mp4',
        hasAudio: false,
        audioUrl: 'https://a.m4a',
      );

      await c.downloadMedia(
        url: quality.itag,
        filename: 'vid.mp4',
        quality: quality,
      );

      expect(c.status, DownloadStatus.success);
      expect(storage.calls, ['video']);
    });

    test('unduh mp3 -> panggil convertToMp3 + simpan ke audio', () async {
      final dl = _FakeDownloads()..fileToReturn = File('/tmp/raw_song.mp4');
      final storage = _FakeStorage();
      final merger = _FakeMerger();
      final c = DownloadController(
        downloadService: dl,
        storageService: storage,
        mediaMerger: merger,
      );

      const quality = MediaQuality(
        label: 'Audio MP3',
        itag: 'https://cdn.example/song.mp4',
        extension: 'mp3',
        hasAudio: true,
      );

      await c.downloadMedia(
        url: quality.itag,
        filename: 'song.mp3',
        quality: quality,
      );

      expect(c.status, DownloadStatus.success);
      expect(c.savedLabel, contains('Audio tersimpan'));
      expect(storage.calls, ['audio']);
    });

    test('gagal unduh -> error + pesan ramah', () async {
      final dl = _FakeDownloads()
        ..error = DioException(
          requestOptions: RequestOptions(path: ''),
          type: DioExceptionType.connectionError,
        );
      final c = DownloadController(
        downloadService: dl,
        storageService: _FakeStorage(),
      );

      await c.downloadMedia(url: 'https://cdn.example/x', filename: 'x.mp4');

      expect(c.status, DownloadStatus.error);
      expect(c.errorMessage, contains('Unduhan gagal'));
    });

    test('ekstensi asing -> error format', () async {
      final dl = _FakeDownloads()..fileToReturn = File('/tmp/x.xyz');
      final c = DownloadController(
        downloadService: dl,
        storageService: _FakeStorage(),
      );

      await c.downloadMedia(url: 'https://cdn.example/x', filename: 'x.xyz');

      expect(c.status, DownloadStatus.error);
      expect(c.errorMessage, contains('Format tidak didukung'));
    });
  });
}
