import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

class _FakeController extends DownloadController {
  _FakeController({this.behavior = _Behavior.success});

  _Behavior behavior;

  @override
  Future<void> downloadMedia({
    required String url,
    required String filename, MediaQuality? quality, Map<String, String>? headers,
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
    expect(find.text('DOWNLOAD'), findsOneWidget);
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
    await tester.tap(find.text('DOWNLOAD'));
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

    await tester.tap(find.text('DOWNLOAD'));
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
}
