import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mediavault/app.dart';

/// E2E skenario bug laporan user: paste link TikTok -> ANALYZE ->
/// halaman preview -> DOWNLOAD -> tersimpan. Jaringan + endpoint asli.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('paste link -> preview -> download tersimpan', (tester) async {
    await tester.pumpWidget(const App());
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField),
      'https://www.tiktok.com/@rashynibos/video/7687500579572124936',
    );
    await tester.pump();
    await tester.tap(find.text('ANALYZE'));
    await tester.pump();

    // Tunggu halaman preview (maks ~60 dtk, resolve provider asli).
    var opened = false;
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(seconds: 2));
      if (find.text('PREVIEW').evaluate().isNotEmpty) {
        opened = true;
        break;
      }
    }
    expect(opened, isTrue, reason: 'halaman preview tidak terbuka');

    // Tunggu tombol DOWNLOAD (kualitas termuat) lalu unduh.
    var canDownload = false;
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(seconds: 2));
      final btn = find.text('DOWNLOAD');
      if (btn.evaluate().isNotEmpty) {
        canDownload = true;
        break;
      }
    }
    expect(canDownload, isTrue, reason: 'tombol DOWNLOAD tidak muncul');

    await tester.tap(find.text('DOWNLOAD'));

    var saved = false;
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(seconds: 2));
      if (find.textContaining('tersimpan').evaluate().isNotEmpty) {
        saved = true;
        break;
      }
    }
    expect(saved, isTrue, reason: 'unduhan tidak selesai tersimpan');
  });
}
