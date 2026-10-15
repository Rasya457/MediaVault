import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mediavault/app.dart';
import 'package:path_provider/path_provider.dart';

/// E2E player preview di device: buka preview video TikTok (portrait),
/// tunggu player init, diam di layar agar bisa di-screenshot via adb.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('preview video portrait bisa diputar', (tester) async {
    await tester.pumpWidget(const App());
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField),
      'https://www.tiktok.com/@rashynibos/video/7687500579572124936',
    );
    await tester.pump();
    await tester.tap(find.text('ANALYZE'));

    var opened = false;
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(seconds: 2));
      if (find.text('PREVIEW').evaluate().isNotEmpty) {
        opened = true;
        break;
      }
    }
    expect(opened, isTrue, reason: 'halaman preview tidak terbuka');

    // Tunggu player init (buffering jaringan) — ikon pause = sedang main.
    // Batas longgar; screenshot diambil apa pun hasilnya.
    var playing = false;
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(seconds: 2));
      if (find.byIcon(Icons.pause).evaluate().isNotEmpty) {
        playing = true;
        break;
      }
    }

    // Bukti visual: screenshot layar preview ke storage aplikasi.
    await binding.convertFlutterSurfaceToImage();
    final bytes = await binding.takeScreenshot('preview');
    final dir = await getExternalStorageDirectory();
    final shot = File('${dir!.path}/mv_preview_e2e.png');
    await shot.writeAsBytes(bytes);
    // ignore: avoid_print
    print('SCREENSHOT_SAVED: ${shot.path} playing=$playing');

    expect(playing, isTrue, reason: 'player tidak mulai (cek screenshot)');

    // Diam sejenak agar frame stabil.
    await tester.pump(const Duration(seconds: 5));
  });
}
