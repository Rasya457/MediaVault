import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediavault/core/network/api_client.dart' as client_lib;
import 'package:mediavault/services/providers/instagram_provider.dart';
import 'package:mediavault/services/providers/provider.dart';
import 'package:mediavault/services/providers/remote_config.dart';
import '../helpers/mock_remote_config.dart';
import '../helpers/mock_dio.dart';

const _tokenPage =
    '<html><form><input type="hidden" name="_token" value="TOK123"></form></html>';
const _resultPage =
    '<html><a href="https://d4.indown.io/fetch?url=abc">Download</a>'
    '<a href="https://cdninstagram.com/v.mp4">Direct</a></html>';

/// Adapter penangkap: layani token untuk GET, hasil untuk POST,
/// sekaligus catat body POST via [onRequest].
class _CaptureAdapter implements HttpClientAdapter {
  _CaptureAdapter(this.onRequest);

  final void Function(RequestOptions options) onRequest;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    onRequest(options);
    final body =
        options.method.toUpperCase() == 'POST' ? _resultPage : _tokenPage;
    return ResponseBody.fromString(body, 200, headers: {
      'content-type': ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  setUp(() {
    injectMockEndpoints({
      'instagram_primary': const EndpointEntry(
        url: 'https://indown.io/en5',
        method: 'GET',
        enabled: true,
      ),
      'instagram_fallback': const EndpointEntry(
        url: 'https://snapsave.app/action.php',
        method: 'POST',
        enabled: true,
      ),
    });
  });

  tearDown(() => RemoteConfig.instance.resetCache());

  group('Instagram canHandle', () {
    final p = InstagramPrimaryProvider();

    test('mengenali URL instagram.com/p/', () {
      expect(p.canHandle('https://www.instagram.com/p/CXxyz123/'), isTrue);
    });

    test('mengenali URL instagram.com/reel/', () {
      expect(p.canHandle('https://www.instagram.com/reel/CXxyz123/'), isTrue);
    });

    test('menolak URL non-Instagram', () {
      expect(p.canHandle('https://tiktok.com/@user/video/123'), isFalse);
      expect(p.canHandle('https://open.spotify.com/track/abc'), isFalse);
    });
  });

  group('InstagramPrimaryProvider fetchInfo (flow 2 langkah terverifikasi E2E)',
      () {
    test('token + POST -> link fetch didahulukan', () async {
      setupMockDio(getPlain: _tokenPage, postPlain: _resultPage);
      final info = await InstagramPrimaryProvider().fetchInfo(
        'https://www.instagram.com/p/ABC123/',
      );
      expect(info.qualities.length, equals(2));
      expect(info.qualities.first.itag, contains('indown.io/fetch'));
      expect(info.qualities.first.label, equals('Video HD'));
      expect(info.source, equals('third-party'));
    });

    test('tanpa token -> providerDown', () async {
      setupMockDio(
        getPlain: '<html>tanpa token</html>',
        postPlain: _resultPage,
      );
      expect(
        () => InstagramPrimaryProvider().fetchInfo(
          'https://www.instagram.com/p/ABC123/',
        ),
        throwsA(
          isA<ProviderException>().having(
            (e) => e.kind,
            'kind',
            ProviderErrorKind.providerDown,
          ),
        ),
      );
    });

    test('tanpa link hasil -> noResult', () async {
      setupMockDio(
        getPlain: _tokenPage,
        postPlain: '<html>kosong</html>',
      );
      expect(
        () => InstagramPrimaryProvider().fetchInfo(
          'https://www.instagram.com/p/ABC123/',
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

    test('href kutip-satu ikut terambil', () async {
      setupMockDio(
        getPlain: _tokenPage,
        postPlain:
            "<html><a href='https://d4.indown.io/fetch?url=abc'>DL</a></html>",
      );
      final info = await InstagramPrimaryProvider().fetchInfo(
        'https://www.instagram.com/p/ABC123/',
      );
      expect(info.qualities.length, equals(1));
      expect(info.qualities.first.itag, contains('indown.io/fetch'));
    });

    test('atribut data-url ikut terambil', () async {
      setupMockDio(
        getPlain: _tokenPage,
        postPlain:
            '<html><button data-url="https://d7.indown.io/fetch?url=xyz">DL</button></html>',
      );
      final info = await InstagramPrimaryProvider().fetchInfo(
        'https://www.instagram.com/p/ABC123/',
      );
      expect(info.qualities.length, equals(1));
      expect(info.qualities.first.itag, contains('indown.io/fetch'));
    });

    test('contentUrl JSON-LD ikut terambil', () async {
      setupMockDio(
        getPlain: _tokenPage,
        postPlain:
            '<html><script type="application/ld+json">{"contentUrl":"https://cdninstagram.com/x.mp4"}</script></html>',
      );
      final info = await InstagramPrimaryProvider().fetchInfo(
        'https://www.instagram.com/p/ABC123/',
      );
      expect(info.qualities.length, equals(1));
      expect(info.qualities.first.itag, contains('.mp4'));
    });

    test('pesan error memuat judul halaman', () async {
      setupMockDio(
        getPlain: _tokenPage,
        postPlain:
            '<html><head><title>InDown - Error</title></head><body>oops</body></html>',
      );
      expect(
        () => InstagramPrimaryProvider().fetchInfo(
          'https://www.instagram.com/p/ABC123/',
        ),
        throwsA(
          isA<ProviderException>().having(
            (e) => e.message,
            'message',
            contains('InDown - Error'),
          ),
        ),
      );
    });

    test('POST memakai URL kanonis tanpa tracking param', () async {
      String? postedLink;
      client_lib.httpClient.httpClientAdapter = _CaptureAdapter((options) {
        final data = options.data;
        if (options.method.toUpperCase() == 'POST' && data is Map) {
          postedLink = data['link']?.toString();
        }
      });
      await InstagramPrimaryProvider().fetchInfo(
        'https://www.instagram.com/reel/DeJaIPygloL/?utm_source=ig_web_copy_link&exln=NTc4MTIwNjQ2YQ==',
      );
      expect(postedLink,
          equals('https://www.instagram.com/reel/DeJaIPygloL/'));
    });
  });

  group('InstagramFallbackProvider fetchInfo', () {
    test('parse HTML response snapsave', () async {
      setupMockDio(
        plainResponse:
            '<html><a href="https://cdn.ig.com/video.mp4">Download HD</a></html>',
      );
      final info = await InstagramFallbackProvider().fetchInfo(
        'https://www.instagram.com/p/ABC123/',
      );
      expect(info.qualities, isNotEmpty);
    });

    test('parse obfuscated hunter script response snapsave', () async {
      const hunterScript =
          'eval(function(h,u,n,t,e,r){r="";for(var i=0,len=h.length;i<len;i++){var s="";while(h[i]!==n[e]){s+=h[i];i++}for(var j=0;j<n.length;j++)s=s.replace(new RegExp(n[j],"g"),j);r+=String.fromCharCode(_0xe88c(s,e,10)-t)}return decodeURIComponent(escape(r))}("baaabbacbbabbbacbbbaabbcbaaaaaaacbababacbbabbabcbbbabbacbbababbcbbbbbabcbbbbbabcbaaabbbcbbaabbacbabbaacbbabbbacbbbbaabcbaaaaaabcbbbbaaacbbbabbacbbbbaabcbbababbcbbabbbacbbabbbcbbbaabbcbbbbbbacbbabbbbcbbbabbbcbbbbbabcbbaabbacbabbaacbaabaaacbaaabbacbbabbbacbbbaabbcbaaaaaaacbababacbbabbabcbbbabbacbbababbcbbbbbabcbbbbbabcbaaabbbcbbaabbacbabbaacbbabbbacbbbbaabcbaaaaaabcbbbbaaacbbbabbacbbbbaabcbbababbcbbabbbacbbabbbcbbbaabbcbbbbbbacbbabbbbcbbbabbbcbbbbbabcbbabaabcbbabaabcbbbbbbacbbbaabacbbbbbbbcbbbabbbcbbabbaacbbaabbacbabbaacbaabaaacbaaabbacbbbaabbcbbbabbbcbbbaaabcbababacbbbbbabcbbbbbaacbbabbabcbaaabbbcbbaabbacbabbaacbbbaabacbbbbbbacbbbbbbacbbbbabacbbbbbabcbaaabaacbbbaabcbbbaabcbbabbbacbbbaaacbbbbbaacbbababbcbbbbabacbbbaabbcbbabbbacbbabbabcbbabbbacbbbbaaacbbbaaacbbababbcbbbbabacbbbbabacbbbaabcbbbbbbacbbbaabacbbbbbbbcbbbabbbcbbabbaacbaabaabcbbbbbbacbbbbaabcbbbababcbbabbbbcbbbbaaacbaaabbbcbbbbbbacbbbabbcbbaabbacbabbaacbaabaaacbaaabbacbbbaabcbbabbbacbbbaabbcbaaaaaaacbaabaaacbaaabbacbbabbbacbbbaabbcbaaaaaaacbababacbbabbabcbbbabbacbbababbcbbbbbabcbbbbbabcbaaabbbcbbaabbacbabbaacbbabbbacbbbbaabcbaaaaaabcbbbbaaacbbbabbacbbbbaabcbbababbcbbabbbacbbabbbcbbbaabbcbbbbbbacbbabbbbcbbbabbbcbbbbbabcbbabaabcbbabaabcbbabbaacbbbbbbacbbbbaaacbbaabbacbabbaacbaabaaacbaaabbacbbababbcbababacbbbaabacbbbbbaacbbabbbbcbbbaaaacbaaabbbcbbaabbacbabbaacbbbaabacbbbbbbacbbbbbbacbbbbabacbbbbbabcbaaabaacbbbaabcbbbaabcbbabbbacbbbaaacbbbbbaacbbababbcbbbbabacbbbaabbcbbabbbacbbabbabcbbabbbacbbbbaaacbbbaaacbbababbcbbbbabacbbbbabacbbbaabcbaaaaaaacbbbbaacbaabaabcbbbbbbacbbbbaabcbbbababcbbabbbbcbbbbaaacbaaabbbcbbbbbbacbbbbaacbbaabbacbabbaacbababacbbabbabcbbbabbacbbababbcbbbbbabcbbbbbabcbaaabbbcbbaabbacbabbaacbbabbaacbbbbbbacbbbbaaacbababacbbabbaacbbbbbbacbbbbaaacbbabbbcbbbbabacbbbbbaacbbbaabbcbbbabbbcbbababbcbbbbbaacbaaaaabbcbbaabbacbabbaacbaabaaacbaabbbacbbbbaabcbaaaaaabcbbbbaaacbbbabbacbbbbaabcbbababbcbbabbbacbaaabbacbbbaabcbbababbcbaabaaacbaaabbacbbbaabcbbabbbacbbbaabbcbaaaaaaacbaabaaacbaaabbacbbbaabcbbabbbacbbbaabbcbaaaaaaacbaabaaa",10,"abcdefghij",10,2,1))';

      setupMockDio(plainResponse: hunterScript);
      final info = await InstagramFallbackProvider().fetchInfo(
        'https://www.instagram.com/p/DebLR1ux4x-/',
      );

      expect(info.qualities, isNotEmpty);
      expect(info.qualities.first.itag, contains('rapidcdn.app/v2'));
      expect(info.qualities.first.extension, equals('jpg'));
      expect(info.thumbnail, contains('rapidcdn.app/thumb'));
    });
  });
}
