import 'package:flutter_test/flutter_test.dart';
import 'package:mediavault/services/providers/youtube_provider.dart';
import 'package:mediavault/services/providers/provider.dart';
import 'package:mediavault/services/providers/remote_config.dart';
import '../helpers/mock_remote_config.dart';
import '../helpers/mock_dio.dart';

void main() {
  setUp(() {
    injectMockEndpoints({
      'youtube_primary': EndpointEntry(
        url: 'https://ytmp3.gg/api/json',
        method: 'GET',
        enabled: true,
      ),
      'youtube_fallback': EndpointEntry(
        url: 'https://yt1s.com/api/ajaxConvert',
        method: 'POST',
        enabled: true,
      ),
      'youtube_innertube': EndpointEntry(
        url: 'https://www.youtube.com/youtubei/v1/player',
        method: 'POST',
        enabled: true,
      ),
    });
  });

  tearDown(() => RemoteConfig.instance.resetCache());

  group('YouTube canHandle', () {
    final p = YouTubePrimaryProvider();

    test('mengenali youtube.com/watch', () {
      expect(p.canHandle('https://www.youtube.com/watch?v=dQw4w9WgXcQ'), isTrue);
    });

    test('mengenali youtu.be short link', () {
      expect(p.canHandle('https://youtu.be/dQw4w9WgXcQ'), isTrue);
    });

    test('mengenali m.youtube.com', () {
      expect(p.canHandle('https://m.youtube.com/watch?v=dQw4w9WgXcQ'), isTrue);
    });

    test('mengenali youtube.com/shorts link', () {
      expect(p.canHandle('https://youtube.com/shorts/OBOZ0rrlfJc?feature=share'), isTrue);
      expect(p.canHandle('https://www.youtube.com/shorts/OBOZ0rrlfJc'), isTrue);
    });

    test('menolak URL non-YouTube', () {
      expect(p.canHandle('https://vimeo.com/123456'), isFalse);
    });
  });

  group('YouTubePrimaryProvider fetchInfo', () {
    test('parse respons sukses dari ytmp3.gg', () async {
      setupMockDio(
        getResponseData: {
          'status': 'ok',
          'result': {
            'url': 'https://cdn.ytmp3.gg/video.mp4',
            'title': 'Rick Astley - Never Gonna Give You Up',
            'thumbnail': 'https://i.ytimg.com/vi/dQw4/hq720.jpg',
            'duration': 213,
          },
        },
      );
      final info = await YouTubePrimaryProvider().fetchInfo(
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
      );
      expect(info.title, contains('Rick Astley'));
      expect(info.durationSec, equals(213));
      expect(info.qualities, isNotEmpty);
    });
  });

  group('YouTubeFallbackProvider fetchInfo', () {
    test('parse respons sukses dari yt1s', () async {
      setupMockDio(
        postResponseData: {
          'status': 'ok',
          'd_url': 'https://cdn.yt1s.com/video.mp4',
          'title': 'Never Gonna Give You Up',
          'fquality': '720',
        },
      );
      final info = await YouTubeFallbackProvider().fetchInfo(
        'https://youtu.be/dQw4w9WgXcQ',
      );
      expect(info.qualities.first.label, contains('720'));
    });

    test('lempar ProviderException untuk URL tanpa video ID', () {
      expect(
        () => YouTubeFallbackProvider().fetchInfo('https://youtube.com/'),
        throwsA(isA<ProviderException>()),
      );
    });
  });

  group('YouTubeInnertubeProvider fetchInfo (bentuk terverifikasi E2E)', () {
    test('parse player response', () async {
      setupMockDio(
        postResponseData: {
          'playabilityStatus': {'status': 'OK'},
          'videoDetails': {
            'title': 'Judul Asli',
            'author': 'Kanal',
            'lengthSeconds': '703',
            'thumbnail': {
              'thumbnails': [
                {'url': 'https://i.ytimg.com/t1.jpg'},
                {'url': 'https://i.ytimg.com/t2.jpg'},
              ],
            },
          },
          'streamingData': {
            'formats': [
              {
                'itag': 18,
                'url': 'https://r1/videoplayback',
                'mimeType': 'video/mp4; codecs="avc1.42001E, mp4a.40.2"',
                'qualityLabel': '360p',
              },
            ],
            'adaptiveFormats': [
              {
                'itag': 140,
                'url': 'https://r2/videoplayback',
                'mimeType': 'audio/mp4; codecs="mp4a.40.2"',
                'bitrate': 131073,
              },
              {
                'itag': 248,
                'mimeType': 'video/webm; codecs="vp9"',
                'signatureCipher': 's=xxx',
              },
            ],
          },
        },
      );
      final info = await YouTubeInnertubeProvider().fetchInfo(
        'https://youtu.be/OBOZ0rrlfJc',
      );
      expect(info.title, equals('Judul Asli'));
      expect(info.author, equals('Kanal'));
      expect(info.durationSec, equals(703));
      expect(info.thumbnail, equals('https://i.ytimg.com/t2.jpg'));
      expect(info.source, equals('direct'));
      expect(info.providerName, equals('Innertube'));
      expect(info.qualities.length, equals(2));
      expect(info.qualities.first.label, equals('360p'));
      expect(info.qualities[1].label, equals('Audio MP3'));
      expect(info.qualities[1].extension, equals('mp3'));
    });

    test('filter kualitas hanya yang memiliki audio (tidak ada video-only) + Audio MP3', () async {
      setupMockDio(
        postResponseData: {
          'playabilityStatus': {'status': 'OK'},
          'videoDetails': {
            'title': 'Test Shorts Filter',
            'author': 'Creator',
            'lengthSeconds': '45',
          },
          'streamingData': {
            'formats': [
              {
                'itag': 22,
                'url': 'https://r/720p.mp4',
                'mimeType': 'video/mp4; codecs="avc1.64001F, mp4a.40.2"',
                'qualityLabel': '720p',
                'audioQuality': 'AUDIO_QUALITY_MEDIUM',
              },
              {
                'itag': 18,
                'url': 'https://r/360p.mp4',
                'mimeType': 'video/mp4; codecs="avc1.42001E, mp4a.40.2"',
                'qualityLabel': '360p',
                'audioQuality': 'AUDIO_QUALITY_LOW',
              },
            ],
            'adaptiveFormats': [
              {
                'itag': 137,
                'url': 'https://r/1080p.mp4',
                'mimeType': 'video/mp4; codecs="avc1.640028"',
                'qualityLabel': '1080p',
              },
              {
                'itag': 135,
                'url': 'https://r/480p.mp4',
                'mimeType': 'video/mp4; codecs="avc1.4d401e"',
                'qualityLabel': '480p',
              },
              {
                'itag': 140,
                'url': 'https://r/audio.m4a',
                'mimeType': 'audio/mp4; codecs="mp4a.40.2"',
                'bitrate': 131073,
              },
            ],
          },
        },
      );
      final info = await YouTubeInnertubeProvider().fetchInfo(
        'https://www.youtube.com/shorts/OBOZ0rrlfJc',
      );
      // Semua format video tersedia dan memiliki audio (muxed atau needsMerge via audioUrl)
      expect(info.qualities.map((q) => q.label).toList(), [
        '1080p',
        '720p',
        '480p',
        '360p',
        'Audio MP3',
      ]);
      expect(info.qualities[0].needsMerge, isTrue);
      expect(info.qualities[0].audioUrl, isNotEmpty);
      expect(info.qualities[1].hasAudio, isTrue);
      expect(info.qualities[2].needsMerge, isTrue);
      expect(info.qualities[3].hasAudio, isTrue);
      expect(info.qualities.last.extension, 'mp3');
      expect(info.downloadHeaders, isNotEmpty);
    });

    test('status bukan OK -> noResult', () async {
      setupMockDio(
        postResponseData: {
          'playabilityStatus': {
            'status': 'LOGIN_REQUIRED',
            'reason': 'Private video',
          },
        },
      );
      expect(
        () => YouTubeInnertubeProvider().fetchInfo(
          'https://youtu.be/OBOZ0rrlfJc',
        ),
        throwsA(
          isA<ProviderException>().having(
            (e) => e.kind,
            'kind',
            ProviderErrorKind.noResult,
          ),
        ),
      );
    });

    test('semua cipher -> noResult', () async {
      setupMockDio(
        postResponseData: {
          'playabilityStatus': {'status': 'OK'},
          'videoDetails': {'title': 'X', 'author': 'Y'},
          'streamingData': {
            'formats': [],
            'adaptiveFormats': [
              {'itag': 248, 'mimeType': 'video/webm', 'signatureCipher': 'x'},
            ],
          },
        },
      );
      expect(
        () => YouTubeInnertubeProvider().fetchInfo(
          'https://youtu.be/OBOZ0rrlfJc',
        ),
        throwsA(isA<ProviderException>()),
      );
    });
  });
}
