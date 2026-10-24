import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediavault/services/providers/tiktok_provider.dart';
import 'package:mediavault/services/providers/provider.dart';
import 'package:mediavault/services/providers/remote_config.dart';
import '../helpers/mock_remote_config.dart';
import '../helpers/mock_dio.dart';

void main() {
  setUp(() {
    injectMockEndpoints({
      'tiktok_primary': const EndpointEntry(
        url: 'https://tikdownloader.io/api/ajaxSearch',
        method: 'POST',
        enabled: true,
      ),
      'tiktok_fallback': const EndpointEntry(
        url: 'https://www.tikwm.com/api/',
        method: 'GET',
        enabled: true,
      ),
    });
  });

  tearDown(() {
    RemoteConfig.instance.resetCache();
  });

  group('TikTok canHandle', () {
    final primary = TikTokPrimaryProvider();
    final fallback = TikWmProvider();

    test('mengenali URL tiktok.com standar', () {
      const url = 'https://www.tiktok.com/@user/video/1234567890';
      expect(primary.canHandle(url), isTrue);
      expect(fallback.canHandle(url), isTrue);
    });

    test('mengenali URL vt.tiktok.com (link pendek)', () {
      const url = 'https://vt.tiktok.com/ZSabc123/';
      expect(primary.canHandle(url), isTrue);
      expect(fallback.canHandle(url), isTrue);
    });

    test('menolak URL non-TikTok', () {
      expect(primary.canHandle('https://youtube.com/watch?v=abc'), isFalse);
      expect(primary.canHandle('https://instagram.com/p/abc'), isFalse);
    });
  });

  group('TikTokPrimaryProvider fetchInfo', () {
    test('parse response sukses dari primary', () async {
      setupMockDio(
        postResponseData: {
          'status': 'ok',
          'data':
              '<div><h3>Test Video</h3>'
              '<a href="https://cdn.tiktok.com/video.mp4">Download</a></div>',
        },
      );
      final provider = TikTokPrimaryProvider();
      final info = await provider.fetchInfo(
        'https://www.tiktok.com/@user/video/123',
      );
      expect(info.title, equals('Test Video'));
      expect(info.qualities, isNotEmpty);
      expect(info.source, equals('third-party'));
      expect(info.providerName, equals('TikDownloader'));
    });

    test('entity HTML di judul di-decode', () async {
      setupMockDio(
        postResponseData: {
          'status': 'ok',
          'data':
              '<div><h3>naik podium &#x1F639; &amp; menang</h3>'
              '<a href="https://cdn.tiktok.com/v.mp4">DL</a></div>',
        },
      );
      final provider = TikTokPrimaryProvider();
      final info = await provider.fetchInfo(
        'https://www.tiktok.com/@user/video/123',
      );
      expect(info.title, equals('naik podium \u{1F639} & menang'));
    });

    test('link snapcdn ikut terambil', () async {
      setupMockDio(
        postResponseData: {
          'status': 'ok',
          'data':
              '<div><h3>T</h3>'
              '<a href="https://dl.snapcdn.app/get?token=abc">HD</a>'
              '<a href="https://cdn.tiktok.com/v.mp4">SD</a></div>',
        },
      );
      final provider = TikTokPrimaryProvider();
      final info = await provider.fetchInfo(
        'https://www.tiktok.com/@user/video/123',
      );
      expect(info.qualities.first.itag, contains('snapcdn'));
      expect(info.qualities.length, equals(3));
      expect(info.qualities.any((q) => q.label == 'Audio MP3'), isTrue);
    });

    test('lempar ProviderException jika status bukan ok', () async {
      setupMockDio(postResponseData: {'status': 'error', 'message': 'failed'});
      final provider = TikTokPrimaryProvider();
      expect(
        () => provider.fetchInfo('https://www.tiktok.com/@user/video/123'),
        throwsA(isA<ProviderException>()),
      );
    });
  });

  group('TikWmProvider fetchInfo', () {
    test('parse respons sukses (bentuk terverifikasi E2E)', () async {
      setupMockDio(
        getResponseData: {
          'code': 0,
          'data': {
            'play': 'https://cdn.tiktok.com/hd.mp4',
            'wmplay': 'https://cdn.tiktok.com/wm.mp4',
            'title': 'Viral Dance',
            'cover': 'https://cdn.tiktok.com/thumb.jpg',
            'duration': 22,
            'author': {'nickname': 'UserXYZ'},
          },
        },
      );
      final provider = TikWmProvider();
      final info = await provider.fetchInfo(
        'https://www.tiktok.com/@user/video/123',
      );
      expect(info.title, equals('Viral Dance'));
      expect(info.author, equals('UserXYZ'));
      expect(info.durationSec, equals(22));
      expect(info.qualities.length, equals(3));
      expect(info.qualities.any((q) => q.label == 'Audio MP3'), isTrue);
      expect(info.providerName, equals('TikWm'));
    });
  });

  // Regresi post fotomode TikTok (dipanen LIVE 24 Okt 2026 dari
  // tikdownloader.io + tikwm.com dengan URL asli
  // @studiis.id/photo/7699114184557989138 — 7 slide foto).
  // Bug lama: seluruh anchor (termasuk Download Image/MP3) diamankan
  // sebagai kualitas "video" sehingga pratinjau post foto tampil video.
  group('TikTok post fotomode (URL foto)', () {
    const photoUrl =
        'https://www.tiktok.com/@studiis.id/photo/7699114184557989138';

    test('LIVE primary: 7 Foto HD jpg + Audio MP3, tanpa kualitas video',
        () async {
      final body =
          File('test/fixtures/tikdown_photo_post.json').readAsStringSync();
      setupMockDio(postPlain: body);
      final info =
          await TikTokPrimaryProvider().fetchInfo(photoUrl);

      expect(info.title, startsWith('Siapa nih'));
      final photos =
          info.qualities.where((q) => q.extension != 'mp3').toList();
      expect(photos.length, equals(7));
      for (var i = 0; i < photos.length; i++) {
        expect(photos[i].label, equals('Foto HD ${i + 1}'));
        expect(photos[i].extension, equals('jpg'));
        expect(photos[i].itag, startsWith('https://dl.snapcdn.app/get?token='));
      }
      final mp3 = info.qualities.last;
      expect(mp3.label, equals('Audio MP3'));
      expect(mp3.extension, equals('mp3'));
      expect(mp3.hasAudio, isTrue);
      expect(
        info.qualities.any((q) => q.label == 'HD (No Watermark)'),
        isFalse,
      );
    });

    test('LIVE tikwm: images[] jadi Foto HD, slideshow play diabaikan',
        () async {
      final body =
          File('test/fixtures/tikwm_photo_post.json').readAsStringSync();
      setupMockDio(getPlain: body);
      final info = await TikWmProvider().fetchInfo(photoUrl);

      final photos =
          info.qualities.where((q) => q.extension != 'mp3').toList();
      expect(photos.length, equals(7));
      for (var i = 0; i < photos.length; i++) {
        expect(photos[i].label, equals('Foto HD ${i + 1}'));
        expect(photos[i].extension, equals('jpg'));
        expect(photos[i].itag, startsWith('https://'));
      }
      expect(info.qualities.last.label, equals('Audio MP3'));
      expect(
        info.qualities.any((q) => q.label == 'HD (No Watermark)'),
        isFalse,
      );
      expect(info.author, equals('studiis.id'));
    });

    test('klasifikasi teks: tombol MP3 & "#" tidak bocor jadi video', () async {
      setupMockDio(
        postResponseData: {
          'status': 'ok',
          'data':
              '<div><h3>Fotonya</h3>'
              '<a href="#">Download Video</a>'
              '<a href="https://dl.snapcdn.app/get?token=t1">Download MP3</a>'
              '<a href="https://dl.snapcdn.app/get?token=img-jpeg-x">'
              'Download Image</a></div>',
        },
      );
      final info = await TikTokPrimaryProvider().fetchInfo(photoUrl);
      expect(info.qualities.length, equals(2));
      expect(info.qualities[0].label, equals('Foto HD'));
      expect(info.qualities[1].label, equals('Audio MP3'));
      expect(info.qualities.any((q) => q.label.contains('Video')), isFalse);
    });
  });
}
