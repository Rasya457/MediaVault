import 'package:flutter_test/flutter_test.dart';
import 'package:mediavault/services/providers/spotify_provider.dart';
import 'package:mediavault/services/providers/remote_config.dart';
import '../helpers/mock_remote_config.dart';
import '../helpers/mock_dio.dart';

void main() {
  setUp(() {
    injectMockEndpoints({
      'spotify_primary': EndpointEntry(
        url: 'https://spotidown.app/api',
        method: 'GET',
        enabled: true,
      ),
      'spotify_fallback': EndpointEntry(
        url: 'https://spotifydown.com/api/download',
        method: 'GET',
        enabled: true,
      ),
    });
  });

  tearDown(() => RemoteConfig.instance.resetCache());

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
  });

  group('SpotifyPrimaryProvider fetchInfo', () {
    test('parse respons sukses — source harus third-party', () async {
      setupMockDio(
        getResponseData: {
          'success': true,
          'link': 'https://cdn.spotidown.app/audio.mp3',
          'metadata': {
            'title': 'Blinding Lights',
            'artist': 'The Weeknd',
            'cover': 'https://i.scdn.co/image/abc.jpg',
            'duration': 200000,
          },
        },
      );
      final info = await SpotifyPrimaryProvider().fetchInfo(
        'https://open.spotify.com/track/4cOdK2wGLETKBW3PvgPWqT',
      );
      expect(info.title, equals('Blinding Lights'));
      expect(info.author, equals('The Weeknd'));
      expect(info.durationSec, equals(200)); // 200000ms / 1000
      // WAJIB third-party karena audio bukan dari CDN resmi Spotify
      expect(info.source, equals('third-party'));
      expect(info.qualities.first.extension, equals('mp3'));
    });
  });

  group('SpotifyFallbackProvider fetchInfo', () {
    test('parse respons spotifydown.com', () async {
      setupMockDio(
        getResponseData: {
          'success': true,
          'link': 'https://cdn.spotifydown.com/audio.mp3',
          'metadata': {
            'name': 'Levitating',
            'artists': 'Dua Lipa',
            'cover_url': 'https://i.scdn.co/image/xyz.jpg',
            'duration_ms': 203000,
          },
        },
      );
      final info = await SpotifyFallbackProvider().fetchInfo(
        'https://open.spotify.com/track/abc123',
      );
      expect(info.source, equals('third-party'));
      expect(info.durationSec, equals(203));
    });
  });
}
