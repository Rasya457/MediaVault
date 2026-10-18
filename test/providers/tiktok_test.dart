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
}
