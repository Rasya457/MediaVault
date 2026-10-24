import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediavault/core/network/api_client.dart' as client_lib;
import 'package:mediavault/services/providers/spotify_provider.dart';
import 'package:mediavault/services/providers/provider.dart';
import 'package:mediavault/services/providers/remote_config.dart';
import '../helpers/mock_remote_config.dart';

/// Adapter rute untuk alur multi-langkah (verify -> action -> track).
class _RouteAdapter implements HttpClientAdapter {
  _RouteAdapter(this.handler);

  final Map<String, dynamic> Function(RequestOptions options) handler;

  /// Respons dibungkus agar GET plain (homepage) maupun POST JSON
  /// sama-sama terparse: Dio memilih berdasarkan responseType request.
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final out = handler(options);
    if (out.containsKey('__plain')) {
      return ResponseBody.fromString(out['__plain'] as String, 200);
    }
    return ResponseBody.fromString(
      jsonEncode(out),
      200,
      headers: {'content-type': ['application/json']},
    );
  }

  @override
  void close({bool force = false}) {}
}

String _b64(Map<String, String> meta) =>
    base64.encode(utf8.encode(jsonEncode(meta)));

void main() {
  final realAdapter = client_lib.httpClient.httpClientAdapter;

  setUp(() {
    injectMockEndpoints({
      'spotify_primary': const EndpointEntry(
        url: 'https://spotimate.app',
        method: 'GET',
        enabled: true,
      ),
      'spotify_fallback': const EndpointEntry(
        url: 'https://spotidown.app',
        method: 'GET',
        enabled: true,
      ),
    });
  });

  tearDown(() {
    RemoteConfig.instance.resetCache();
    client_lib.httpClient.httpClientAdapter = realAdapter;
  });

  group('Spotify canHandle', () {
    final p = SpotifyPrimaryProvider();

    test('mengenali open.spotify.com/track/', () {
      expect(
        p.canHandle('https://open.spotify.com/track/4cOdK2wGLETKBW3PvgPWqT'),
        isTrue,
      );
    });

    test('mengenali open.spotify.com/album/', () {
      expect(
        p.canHandle('https://open.spotify.com/album/3T4tUhGYeRNVUGevb0wThu'),
        isTrue,
      );
    });

    test('menolak URL non-Spotify', () {
      expect(p.canHandle('https://soundcloud.com/track/abc'), isFalse);
    });

    test('mengenali spotify.link/', () {
      expect(
        p.canHandle('https://spotify.link/AbCdEf123'),
        isTrue,
      );
    });

    test('mengenali spotify intl URL', () {
      expect(
        p.canHandle('https://open.spotify.com/intl-id/track/4cOdK2wGLETKBW3PvgPWqT'),
        isTrue,
      );
    });

    test('mengenali URI spotify:track:abc', () {
      expect(
        p.canHandle('spotify:track:4cOdK2wGLETKBW3PvgPWqT'),
        isTrue,
      );
    });
  });

  group('SpotifyPrimaryProvider fetchInfo (soundloaders)', () {
    test('verify -> action -> track = MP3 langsung', () async {
      final payload = _b64({'name': 'Blinding Lights', 'artist': 'The Weeknd'});
      client_lib.httpClient.httpClientAdapter = _RouteAdapter((options) {
        final path = options.path;
        if (options.method.toUpperCase() == 'GET') {
          return {'__plain': '<html>home</html>'};
        }
        if (path.endsWith('/api/userverify')) {
          return {'success': true, 'token': 'TOK123'};
        }
        if (path.endsWith('/action/track')) {
          return {
            'data':
                '<a href="https://cdn.spotimate.app/audio.mp3">Download MP3</a>',
          };
        }
        return {
          'success': true,
          'html': '<h2>Blinding Lights</h2>'
              '<p><span>The Weeknd</span></p>'
              '<form><input name="data" value="$payload">'
              '<input name="token" value="tt">'
              '<input name="base" value="b"></form>',
        };
      });
      final info = await SpotifyPrimaryProvider().fetchInfo(
        'https://open.spotify.com/track/4cOdK2wGLETKBW3PvgPWqT',
      );
      expect(info.title, equals('The Weeknd - Blinding Lights'));
      expect(info.author, equals('The Weeknd'));
      // WAJIB third-party karena audio bukan dari CDN resmi Spotify
      expect(info.source, equals('third-party'));
      expect(info.providerName, equals('SoundLoaders'));
      expect(info.qualities.first.label, equals('MP3'));
      expect(info.qualities.first.extension, equals('mp3'));
    });

    test('tanpa track -> noResult', () async {
      client_lib.httpClient.httpClientAdapter = _RouteAdapter((options) {
        if (options.method.toUpperCase() == 'GET') {
          return {'__plain': '<html>home</html>'};
        }
        if (pathEnds(options.path, 'userverify')) {
          return {'success': true, 'token': 'T'};
        }
        return {
          'success': true,
          'html': '<html>kosong</html>',
        };
      });
      expect(
        () => SpotifyPrimaryProvider().fetchInfo(
          'https://open.spotify.com/track/abc123',
        ),
        throwsA(isA<ProviderException>()),
      );
    });
  });

  group('SpotifyFallbackProvider fetchInfo (spotidown)', () {
    test('homepage -> action -> track = MP3', () async {
      final payload = _b64({'name': 'Levitating', 'artist': 'Dua Lipa'});
      client_lib.httpClient.httpClientAdapter = _RouteAdapter((options) {
        final path = options.path;
        if (options.method.toUpperCase() == 'GET') {
          return {
            '__plain': '<form name="spotifyurl">'
                '<input name="csrf" value="abc"></form>',
          };
        }
        if (path.endsWith('/action/track')) {
          return {
            'data':
                '<a href="https://cdn.spotidown.app/audio.mp3">Download MP3</a>',
          };
        }
        return {
          'data': '<form name="submitspurl">'
              '<input name="data" value="$payload">'
              '<input name="id" value="1"></form>',
        };
      });
      final info = await SpotifyFallbackProvider().fetchInfo(
        'https://open.spotify.com/track/abc123',
      );
      expect(info.title, equals('Levitating'));
      expect(info.author, equals('Dua Lipa'));
      expect(info.source, equals('third-party'));
      expect(info.qualities.first.extension, equals('mp3'));
    });

    test('scraper gagal -> fallback ke Spotify embed resolver (pola Mori)', () async {
      client_lib.httpClient.httpClientAdapter = _RouteAdapter((options) {
        final path = options.path;
        if (path.contains('spotidown.app')) {
          // Simulasi SpotiDown gagal (CSRF / Bot Protection)
          return {'error': true, 'message': 'Please Refresh the Page & Try Again!'};
        }
        if (path.contains('open.spotify.com/embed/')) {
          // Simulasi respons Spotify Embed resmi
          final nextData = jsonEncode({
            'props': {
              'pageProps': {
                'state': {
                  'data': {
                    'entity': {
                      'name': 'Stay With Me',
                      'artists': [{'name': 'Miki Matsubara'}],
                      'duration': 300000,
                      'audioPreview': {
                        'url': 'https://p.scdn.co/mp3-preview/stay.mp3'
                      },
                      'visualIdentity': {
                        'image': [
                          {'url': 'https://i.scdn.co/image/stay.jpg'}
                        ]
                      }
                    }
                  }
                }
              }
            }
          });
          return {
            '__plain': '<html><head>'
                '<script id="__NEXT_DATA__" type="application/json">$nextData</script>'
                '</head><body></body></html>'
          };
        }
        if (path.contains('youtube.com')) {
          return {'contents': {}};
        }
        return {'__plain': ''};
      });

      final info = await SpotifyFallbackProvider().fetchInfo(
        'https://open.spotify.com/track/stay_with_me_id',
      );

      expect(info.title, equals('Miki Matsubara - Stay With Me'));
      expect(info.author, equals('Miki Matsubara'));
      expect(info.durationSec, equals(300));
      expect(info.thumbnail, equals('https://i.scdn.co/image/stay.jpg'));
      expect(info.qualities.any((q) => q.extension == 'mp3'), isTrue);
      // Cover tidak lagi ditawarkan sebagai unduhan — audio saja.
      expect(info.qualities.any((q) => q.label.contains('Cover')), isFalse);
    });
  });

  // Regresi playlist Spotify LIVE 24 Okt 2026 (bukti via PowerShell):
  // - /api/userverify WAJIB (token diteruskan ke cftoken action);
  // - action dengan data-kind="Playlist" berisi 50 form track;
  // - free plan hanya resolve 5 track pertama, sisanya error:true;
  // - batch paralel 5 berhenti setelah batch kosong pertama saat sudah
  //   ada hasil (playlist 50 track = ~10 panggilan, bukan 100+ detik);
  // - sisa track diisi preview resmi 30 detik dari embed Spotify.
  group('SpotifyPrimaryProvider playlist (soundloaders)', () {
    List<String> buildTrackForms(int n) {
      final forms = <String>[];
      for (var i = 1; i <= n; i++) {
        forms.add(
          '<div class="sm-track"><form name="submitapurl">'
          '<input name="data" value="${_b64({'name': 'Lagu$i', 'artist': 'Artis$i'})}">'
          '<input name="base" value="b"><input name="token" value="tt">'
          '</form></div>',
        );
      }
      return forms;
    }

    String embedHtml(int n) {
      final nextData = jsonEncode({
        'props': {
          'pageProps': {
            'state': {
              'data': {
                'entity': {
                  'title': 'Playlist Gua',
                  'trackList': [
                    for (var i = 1; i <= n; i++)
                      {
                        'title': 'Lagu$i',
                        'subtitle': 'Artis$i',
                        'audioPreview': {
                          'url': 'https://p.scdn.co/prev/$i.mp3',
                        },
                      },
                  ],
                },
              },
            },
          },
        },
      });
      return '<html><script id="__NEXT_DATA__">$nextData</script></html>';
    }

    test('5 track penuh + sisa preview 30s; parallel berhenti di limit',
        () async {
      var trackCalls = 0;
      client_lib.httpClient.httpClientAdapter = _RouteAdapter((options) {
        final path = options.path;
        if (options.method.toUpperCase() == 'GET') {
          // GET en1 maupun GET embed Spotify.
          if (path.contains('/embed/')) {
            return {'__plain': embedHtml(8)};
          }
          return {'__plain': '<html>home</html>'};
        }
        if (path.endsWith('/api/userverify')) {
          return {'success': true, 'token': 'TOK123'};
        }
        if (path.endsWith('/action/track')) {
          trackCalls++;
          if (trackCalls <= 5) {
            return {
              'data':
                  '<a href="https://dl.spotimate.app/mp3/full$trackCalls.mp3">'
                  'Download Mp3</a>',
            };
          }
          return {'error': true, 'message': 'free limit'};
        }
        return {
          'success': true,
          'html': '<section class="sm-collection" data-kind="Playlist">'
              '<img class="sm-cover" src="https://i.scdn.co/cover.jpg">'
              '<h3>Playlist Gua</h3>'
              '${buildTrackForms(8).join()}'
              '</section>',
        };
      });
      final info = await SpotifyPrimaryProvider().fetchInfo(
        'https://open.spotify.com/playlist/37i9dQZF1E8PHsvBMNwLWo',
      );

      expect(info.title, equals('Artis1 - Playlist Gua (Playlist)'));
      expect(info.thumbnail, equals('https://i.scdn.co/cover.jpg'));
      expect(info.qualities.length, equals(8));
      final full =
          info.qualities.where((q) => q.label.contains('[MP3]')).toList();
      expect(full.length, equals(5));
      final previews =
          info.qualities.where((q) => q.label.contains('[MP3 30s]')).toList();
      expect(previews.length, equals(3));
      for (final p in previews) {
        expect(p.itag, startsWith('https://p.scdn.co/'));
        expect(p.hasAudio, isTrue);
        expect(p.audioUrl, isNotEmpty);
      }
      expect(info.qualities.first.label, equals('1 Artis1 - Lagu1 [MP3]'));
      expect(
        info.qualities.last.label,
        equals('8 Artis8 - Lagu8 [MP3 30s]'),
      );
    });
  });
}

bool pathEnds(String path, String suffix) => path.endsWith('/$suffix');
