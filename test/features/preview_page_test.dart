import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediavault/features/download/batch_download_controller.dart';
import 'package:mediavault/features/download/download_controller.dart';
import 'package:mediavault/features/preview/preview_page.dart';
import 'package:mediavault/services/providers/models.dart';

const _info = MediaInfo(
  title: 'Video Uji Coba Panjang Sekali Biar Wrap Dua Baris',
  author: 'Akun Uji',
  thumbnail: null,
  durationSec: 65,
  qualities: [
    MediaQuality(label: 'HD (No Watermark)', itag: 'https://cdn/v.mp4'),
    MediaQuality(
      label: 'Audio MP3',
      itag: 'https://cdn/a.mp3',
      extension: 'mp3',
    ),
  ],
  source: 'third-party',
  providerName: 'TikWm',
);

const _playlistInfo = MediaInfo(
  title: 'Playlist Uji (Playlist)',
  author: 'Kurasi Uji',
  thumbnail: 'https://i.scdn.co/cover.jpg',
  durationSec: null,
  qualities: [
    MediaQuality(
      label: '01 Artis A - Lagu Satu [MP3]',
      itag: 'https://cdn/1.mp3',
      extension: 'mp3',
    ),
    MediaQuality(
      label: '02 Artis B - Lagu Dua [MP3]',
      itag: 'https://cdn/2.mp3',
      extension: 'mp3',
    ),
    MediaQuality(
      label: '03 Artis C - Lagu Tiga [MP3]',
      itag: 'https://cdn/3.mp3',
      extension: 'mp3',
    ),
  ],
  source: 'third-party',
  providerName: 'SoundLoaders',
);

class _FakeController extends DownloadController {
  _FakeController({this.behavior = _Behavior.success});

  _Behavior behavior;

  @override
  Future<void> downloadMedia({
    required String url,
    required String filename,
    MediaQuality? quality,
    Map<String, String>? headers,
    String? title,
    String? author,
    String? platform,
    String? thumbnail,
  }) async {
    status = DownloadStatus.downloading;
    progress = 0.5;
    notifyListeners();
    await Future<void>.delayed(Duration.zero);
    if (behavior == _Behavior.success) {
      status = DownloadStatus.success;
      savedLabel = 'Video tersimpan di galeri (MediaVault)';
    } else {
      status = DownloadStatus.error;
      errorMessage = 'Unduhan gagal (simulasi)';
    }
    notifyListeners();
  }
}

class _FakeBatch extends BatchDownloadController {
  void _finish(List<BatchItem> targets) {
    for (final i in targets) {
      i
        ..status = BatchItemStatus.done
        ..progress = 1.0
        ..savedPath = '/tmp/${i.filename}';
    }
  }

  @override
  Future<void> start() async {
    running = true;
    notifyListeners();
    await Future<void>.delayed(Duration.zero);
    _finish(items);
    running = false;
    notifyListeners();
  }

  @override
  Future<void> startOne(BatchItem item) async {
    running = true;
    notifyListeners();
    await Future<void>.delayed(Duration.zero);
    _finish([item]);
    running = false;
    notifyListeners();
  }
}

enum _Behavior { success, error }

void main() {
  void tallSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
  }

  testWidgets('preview tampil judul + kualitas + tombol', (tester) async {
    tallSurface(tester);
    await tester.pumpWidget(
      const MaterialApp(
        home: PreviewPage(info: _info, sourceUrl: 'https://x'),
      ),
    );

    expect(find.textContaining('Video Uji Coba'), findsOneWidget);
    expect(find.text('HD (No Watermark)'), findsOneWidget);
    expect(find.text('Audio MP3'), findsOneWidget);
    expect(find.text('UNDUH'), findsOneWidget);
    expect(find.text('1:05'), findsOneWidget);
  });

  testWidgets('pilih kualitas lalu unduh -> sukses', (tester) async {
    tallSurface(tester);
    final controller = _FakeController();
    await tester.pumpWidget(
      MaterialApp(
        home: PreviewPage(
          info: _info,
          sourceUrl: 'https://x',
          controller: controller,
        ),
      ),
    );

    await tester.tap(find.text('Audio MP3'));
    await tester.pump();
    await tester.tap(find.text('UNDUH'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(controller.status, DownloadStatus.success);
    expect(find.textContaining('tersimpan di galeri'), findsOneWidget);
  });

  testWidgets('unduh gagal -> pesan error tampil', (tester) async {
    tallSurface(tester);
    final controller = _FakeController(behavior: _Behavior.error);
    await tester.pumpWidget(
      MaterialApp(
        home: PreviewPage(
          info: _info,
          sourceUrl: 'https://x',
          controller: controller,
        ),
      ),
    );

    await tester.tap(find.text('UNDUH'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Unduhan gagal (simulasi)'), findsOneWidget);
  });

  testWidgets('player tanpa plugin -> fallback icon', (tester) async {
    tallSurface(tester);
    await tester.pumpWidget(
      const MaterialApp(
        home: PreviewPage(info: _info, sourceUrl: 'https://x'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
  });

  group('playlist (audio saja)', () {
    testWidgets('cover playlist + daftar lagu + tombol UNDUH SEMUA',
        (tester) async {
      tallSurface(tester);
      await tester.pumpWidget(
        const MaterialApp(
          home: PreviewPage(info: _playlistInfo, sourceUrl: 'https://x'),
        ),
      );
      await tester.pumpAndSettle();

      // Tidak ada pilihan kualitas di mode playlist — audio saja.
      expect(find.text('PILIH KUALITAS'), findsNothing);
      expect(find.text('DAFTAR LAGU (3)'), findsOneWidget);
      expect(find.text('UNDUH SEMUA (3)'), findsOneWidget);
      expect(find.text('3 LAGU'), findsOneWidget);

      // Judul lagu tampil tanpa cover art per baris.
      expect(find.text('Lagu Satu'), findsOneWidget);
      expect(find.text('Lagu Dua'), findsOneWidget);
      expect(find.text('Lagu Tiga'), findsOneWidget);
      // Thumbnail jaringan selalu gagal di test env — frame fallback tampil.
      expect(find.byIcon(Icons.image_outlined), findsOneWidget);
    });

    testWidgets('UNDUH SEMUA mengunduh semua lagu', (tester) async {
      tallSurface(tester);
      final batch = _FakeBatch();
      await tester.pumpWidget(
        MaterialApp(
          home: PreviewPage(
            info: _playlistInfo,
            sourceUrl: 'https://x',
            batchController: batch,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('UNDUH SEMUA (3)'));
      await tester.pumpAndSettle();

      expect(batch.doneCount, 3);
      // 'Tersimpan' berada di subtitle baris: "Artis X · Tersimpan".
      expect(find.textContaining('Tersimpan'), findsNWidgets(3));
      expect(find.text('3 lagu tersimpan'), findsOneWidget);
    });

    testWidgets('ketuk satu baris mengunduh lagu itu saja', (tester) async {
      tallSurface(tester);
      final batch = _FakeBatch();
      await tester.pumpWidget(
        MaterialApp(
          home: PreviewPage(
            info: _playlistInfo,
            sourceUrl: 'https://x',
            batchController: batch,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Lagu Dua'));
      await tester.pumpAndSettle();

      expect(batch.doneCount, 1);
      expect(batch.items[1].status, BatchItemStatus.done);
      expect(batch.items[0].status, BatchItemStatus.queued);
      expect(batch.items[2].status, BatchItemStatus.queued);
    });
  });

  group('carousel foto (album murni)', () {
    const albumInfo = MediaInfo(
      title: 'Carousel Foto',
      author: 'Akun Uji',
      thumbnail: null,
      durationSec: null,
      qualities: [
        MediaQuality(label: 'Foto HD 1', itag: 'https://cdn/p1.jpg', extension: 'jpg'),
        MediaQuality(label: 'Foto HD 2', itag: 'https://cdn/p2.jpg', extension: 'jpg'),
      ],
      source: 'third-party',
      providerName: 'InDown',
    );

    testWidgets('slider foto bisa di-swipe + UNDUH SEMUA FOTO',
        (tester) async {
      tallSurface(tester);
      await tester.pumpWidget(
        const MaterialApp(
          home: PreviewPage(info: albumInfo, sourceUrl: 'https://x'),
        ),
      );
      await tester.pumpAndSettle();

      // Mode slider: tanpa pilihan kualitas, ada counter foto + unduh semua.
      expect(find.text('PILIH KUALITAS'), findsNothing);
      expect(find.byType(PageView), findsOneWidget);
      expect(find.text('1/2'), findsOneWidget);
      expect(find.text('FOTO (2)'), findsOneWidget);
      expect(find.textContaining('UNDUH SEMUA FOTO'), findsOneWidget);

      // Swipe kiri → pindah ke foto ke-2 (drag harus lewat setengah layar).
      await tester.fling(find.byType(PageView), const Offset(-700, 0), 1000);
      await tester.pumpAndSettle();
      expect(find.text('2/2'), findsOneWidget);
    });

    testWidgets('post berisi video: mode kualitas biasa, tanpa unduh semua',
        (tester) async {
      const mixedInfo = MediaInfo(
        title: 'Carousel Campur Video',
        author: 'Akun Uji',
        thumbnail: null,
        durationSec: null,
        qualities: [
          MediaQuality(label: 'Video HD', itag: 'https://cdn/v.mp4'),
          MediaQuality(label: 'Foto HD 1', itag: 'https://cdn/p1.jpg', extension: 'jpg'),
          MediaQuality(label: 'Foto HD 2', itag: 'https://cdn/p2.jpg', extension: 'jpg'),
          MediaQuality(
            label: 'Audio MP3',
            itag: 'https://cdn/v.mp4',
            extension: 'mp3',
            hasAudio: true,
          ),
        ],
        source: 'third-party',
        providerName: 'InDown',
      );
      tallSurface(tester);
      await tester.pumpWidget(
        const MaterialApp(
          home: PreviewPage(info: mixedInfo, sourceUrl: 'https://x'),
        ),
      );
      await tester.pumpAndSettle();

      // Video → bukan mode album: pilihan kualitas + MP3 + tombol UNDUH.
      expect(find.text('PILIH KUALITAS'), findsOneWidget);
      expect(find.text('Video HD'), findsOneWidget);
      expect(find.text('Foto HD 1'), findsOneWidget);
      expect(find.text('Audio MP3'), findsOneWidget);
      expect(find.text('UNDUH'), findsOneWidget);
      expect(find.textContaining('UNDUH SEMUA'), findsNothing);
      expect(find.byType(PageView), findsNothing);
    });

    testWidgets('album fotomode TikTok ber-musik: slider + unduh semua foto + tile audio',
        (tester) async {
      const tiktokPhoto = MediaInfo(
        title: 'TikTok Foto',
        author: 'studiis.id',
        thumbnail: 'https://cdn/cover.jpeg',
        durationSec: null,
        qualities: [
          MediaQuality(label: 'Foto HD 1', itag: 'https://cdn/p1.jpeg', extension: 'jpg'),
          MediaQuality(label: 'Foto HD 2', itag: 'https://cdn/p2.jpeg', extension: 'jpg'),
          MediaQuality(label: 'Foto HD 3', itag: 'https://cdn/p3.jpeg', extension: 'jpg'),
          MediaQuality(
            label: 'Audio MP3',
            itag: 'https://cdn/music.mp3',
            extension: 'mp3',
            hasAudio: true,
          ),
        ],
        source: 'third-party',
        providerName: 'TikDownloader',
      );
      tallSurface(tester);
      await tester.pumpWidget(
        const MaterialApp(
          home: PreviewPage(info: tiktokPhoto, sourceUrl: 'https://x'),
        ),
      );
      await tester.pumpAndSettle();

      // Album tetap aktif walau ada MP3 (fotomode selalu ada musik).
      expect(find.text('PILIH KUALITAS'), findsNothing);
      expect(find.byType(PageView), findsOneWidget);
      expect(find.text('FOTO (3)'), findsOneWidget);
      expect(find.textContaining('UNDUH SEMUA FOTO'), findsOneWidget);
      // Seksi audio terpisah; unduh semua tetap hanya foto.
      expect(find.text('AUDIO (1)'), findsOneWidget);
      expect(find.text('Musik dari post ini'), findsOneWidget);
      expect(find.text('Audio MP3'), findsOneWidget);
    });
  });
}
