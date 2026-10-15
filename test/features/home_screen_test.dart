import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediavault/features/home/home_page.dart';
import 'package:mediavault/features/home/platform_item.dart';
import 'package:mediavault/features/home/widgets/liquid_glass_nav_bar.dart';
import 'package:mediavault/features/shell/app_shell.dart';

void main() {
  testWidgets('AppShell renders Home, Download FAB, and LiquidGlassNavBar', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: AppShell()),
    );
    await tester.pumpAndSettle();

    expect(find.text('MORI'), findsOneWidget);
    expect(find.text('Paste link here...'), findsOneWidget);
    expect(find.byIcon(Icons.search), findsOneWidget);
    expect(find.byIcon(Icons.format_list_bulleted), findsOneWidget);
    expect(find.byIcon(Icons.content_paste), findsOneWidget);
    expect(find.text('ANALYZE'), findsOneWidget);
    expect(find.text('SUPPORTED PLATFORMS'), findsOneWidget);
    expect(find.text('TIKTOK'), findsOneWidget);
    expect(find.text('INSTAGRAM'), findsOneWidget);
    expect(find.text('YOUTUBE'), findsOneWidget);
    expect(find.text('SPOTIFY'), findsOneWidget);
    expect(find.byIcon(Icons.cloud_download_outlined), findsOneWidget);
    expect(find.text('HOME'), findsOneWidget);
    expect(find.text('HISTORY'), findsOneWidget);
    expect(find.text('SETTINGS'), findsOneWidget);
  });

  testWidgets('ANALYZE dengan URL tidak valid tampilkan SnackBar', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: HomePage())),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'bukan-url-valid');
    await tester.tap(find.text('ANALYZE'));
    await tester.pump();

    expect(
      find.text('URL tidak valid. Pastikan diawali https://'),
      findsOneWidget,
    );
  });

  testWidgets('ANALYZE dengan URL kosong tidak melakukan apa-apa', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: HomePage())),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('ANALYZE'));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('LiquidGlassNavBar tab switching', (tester) async {
    int selected = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: LiquidGlassNavBar(
            items: const [
              NavItem(icon: Icons.home, label: 'HOME'),
              NavItem(icon: Icons.history, label: 'HISTORY'),
              NavItem(icon: Icons.settings, label: 'SETTINGS'),
            ],
            currentIndex: selected,
            onTap: (i) => selected = i,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('HISTORY'));
    expect(selected, 1);
  });

  testWidgets('Toggle multi-link mengubah state ikon', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: HomePage())),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.format_list_bulleted), findsOneWidget);
    await tester.tap(find.byIcon(Icons.format_list_bulleted));
    await tester.pump();

    expect(find.byIcon(Icons.format_list_bulleted), findsOneWidget);
  });

  // ── Unit tests: deteksi platform tanpa Dio / network ──────────────────────
  group('detectPlatform', () {
    test('TikTok standar dikenali', () {
      final p = detectPlatform('https://www.tiktok.com/@user/video/123');
      expect(p?.id, 'tiktok');
    });

    test('vt.tiktok.com (short link) dikenali sebagai TikTok', () {
      final p = detectPlatform('https://vt.tiktok.com/abc123');
      expect(p?.id, 'tiktok');
    });

    test('Instagram /p/ dikenali', () {
      final p = detectPlatform('https://www.instagram.com/p/ABC123/');
      expect(p?.id, 'instagram');
    });

    test('Instagram /reel/ dikenali', () {
      final p = detectPlatform('https://www.instagram.com/reel/XYZ/');
      expect(p?.id, 'instagram');
    });

    test('YouTube watch dikenali', () {
      final p = detectPlatform('https://www.youtube.com/watch?v=dQw4w9WgXcQ');
      expect(p?.id, 'youtube');
    });

    test('youtu.be short link dikenali', () {
      final p = detectPlatform('https://youtu.be/dQw4w9WgXcQ');
      expect(p?.id, 'youtube');
    });

    test('Spotify track dikenali', () {
      final p = detectPlatform('https://open.spotify.com/track/abc');
      expect(p?.id, 'spotify');
    });

    test('URL tidak dikenal kembalikan null', () {
      final p = detectPlatform('https://example.com/video/123');
      expect(p, isNull);
    });

    test('Pinterest wildcard dikenali', () {
      final p = detectPlatform('https://pinterest.co.uk/pin/123');
      expect(p?.id, 'pinterest');
    });

    test('Douyin dikenali', () {
      final p = detectPlatform('https://www.douyin.com/video/123');
      expect(p?.id, 'douyin');
    });
  });
}