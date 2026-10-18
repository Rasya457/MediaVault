import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediavault/core/network/api_client.dart' as client_lib;
import 'package:mediavault/services/providers/youtube_provider.dart';
import 'package:mediavault/services/providers/provider.dart';
import 'package:mediavault/services/providers/remote_config.dart';
import '../helpers/mock_remote_config.dart';
import '../helpers/mock_dio.dart';

/// Adapter rute: jawab berdasarkan method + path + isi body.
/// Dipakai untuk alur multi-langkah (convert -> polling status).
class _RouteAdapter implements HttpClientAdapter {
  _RouteAdapter(this.handler);

  final Map<String, dynamic> Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      jsonEncode(handler(options)),
      200,
      headers: {'content-type': ['application/json']},
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  final realAdapter = client_lib.httpClient.httpClientAdapter;

  setUp(() {
    ytmp3PollDelay = Duration.zero;
    injectMockEndpoints({
      'youtube_primary': EndpointEntry(
        url: 'https://hub.convert1s.com/api/download',
        method: 'POST',
        enabled: true,
      ),
      'youtube_fallback': EndpointEntry(
        url: 'https://a.ymcdn.org/api/v1/init',
        method: 'GET',
        enabled: true,
      ),
      'youtube_innertube': EndpointEntry(
        url: 'https://www.youtube.com/youtubei/v1/player',
        method: 'POST',
        enabled: true,
      ),
    });
  });

  tearDown(() {
    RemoteConfig.instance.resetCache();
    client_lib.httpClient.httpClientAdapter = realAdapter;
    ytmp3PollDelay = const Duration(milliseconds: 1500);
  });

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

  group('YouTubePrimaryProvider fetchInfo (convert1s hub)', () {
    Map<String, dynamic> ggHandler(RequestOptions options) {
      final path = options.path;
      if (options.method.toUpperCase() == 'GET' &&
          path.contains('oembed')) {
        return {
          'title': 'Rick Astley - Never Gonna Give You Up',
          'thumbnail_url': 'https://i.ytimg.com/vi/dQw4/hq720.jpg',
        };
      }
      if (options.method.toUpperCase() == 'POST') {
        final data = (options.data as Map?)?.cast<String, dynamic>() ?? {};
        final output =
            (data['output'] as Map?)?.cast<String, dynamic>() ?? {};
        final quality = '${output['quality'] ?? ''}';
        final tag = quality.isEmpty ? 'mp3' : quality;
        return {'statusUrl': 'https://hub.convert1s.com/status/$tag'};
      }
      // Polling status -> completed langsung.
      final tag = path.split('/').last;
      return {
        'status': 'completed',
        'downloadUrl': 'https://cdn.gg/$tag.mp4',
        'selectedQuality': tag == 'mp3' ? '' : tag,
      };
    }

    test('convert 720p + 360p + mp3 -> 3 kualitas', () async {
      client_lib.httpClient.httpClientAdapter = _RouteAdapter(ggHandler);
      final info = await YouTubePrimaryProvider().fetchInfo(
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
      );
      expect(info.title, contains('Rick Astley'));
      expect(info.thumbnail, contains('ytimg'));
      expect(info.qualities.map((q) => q.label).toList(), [
        'MP4 720p',
        'MP4 360p',
        'MP3',
      ]);
      expect(info.qualities.last.extension, 'mp3');
      expect(info.providerName, 'Ytmp3');
    });

    test('semua convert ditolak -> noResult', () async {
      client_lib.httpClient.httpClientAdapter = _RouteAdapter((options) {
        if (options.method.toUpperCase() == 'GET' &&
            options.path.contains('oembed')) {
          return {'title': 'X'};
        }
        return {'error': true};
      });
      expect(
        () => YouTubePrimaryProvider().fetchInfo(
          'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        ),
        throwsA(isA<ProviderException>()),
      );
    });
  });

  group('YouTubeFallbackProvider fetchInfo (ycdn mobi)', () {
    test('init -> convert -> MP4 + MP3', () async {
      client_lib.httpClient.httpClientAdapter = _RouteAdapter((options) {
        final path = options.path;
        if (options.method.toUpperCase() == 'GET' &&
            path.contains('oembed')) {
          return {'title': 'Never Gonna Give You Up'};
        }
        if (path.contains('/api/v1/init')) {
          return {'convertURL': 'https://ycdn.example/convert'};
        }
        final fmt = options.queryParameters['f']?.toString() ??
            RegExp(r'[?&]f=([a-z0-9]+)').firstMatch(path)?.group(1) ??
            'mp4';
        return {
          'downloadURL': 'https://cdn.mobi/video.$fmt',
          'progressURL': 'https://ycdn.example/progress',
          'progress': 3,
        };
      });
      final info = await YouTubeFallbackProvider().fetchInfo(
        'https://youtu.be/dQw4w9WgXcQ',
      );
      expect(info.qualities.map((q) => q.label).toList(), ['MP4', 'MP3']);
      expect(info.providerName, 'Ytmp3Mobi');
    });

    test('init error -> noResult', () async {
      client_lib.httpClient.httpClientAdapter = _RouteAdapter((options) {
        if (options.path.contains('oembed')) return {'title': 'X'};
        return {'error': true};
      });
      expect(
        () => YouTubeFallbackProvider().fetchInfo(
          'https://youtu.be/dQw4w9WgXcQ',
        ),
        throwsA(isA<ProviderException>()),
      );
    });

    test('lempar ProviderException untuk URL tanpa video ID', () {
      expect(
        () => YouTubeFallbackProvider().fetchInfo('https://youtube.com/'),
        throwsA(isA<ProviderException>()),
      );
    });
  });

  group('YouTubeThirdPartyProvider (gg -> mobi)', () {
    test('gg gagal total -> mobi dipakai', () async {
      client_lib.httpClient.httpClientAdapter = _RouteAdapter((options) {
        final path = options.path;
        if (path.contains('oembed')) return {'title': 'Chain Video'};
        if (path.contains('convert1s')) return {'error': true};
        if (path.contains('/api/v1/init')) {
          return {'convertURL': 'https://ycdn.example/convert'};
        }
        return {
          'downloadURL': 'https://cdn.mobi/video.mp4',
          'progressURL': 'https://ycdn.example/progress',
          'progress': 3,
        };
      });
      final info = await YouTubeThirdPartyProvider().fetchInfo(
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
      );
      expect(info.providerName, 'Ytmp3Mobi');
      expect(info.qualities, isNotEmpty);
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
