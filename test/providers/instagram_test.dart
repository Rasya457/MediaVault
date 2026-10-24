import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediavault/core/network/api_client.dart' as client_lib;
import 'package:mediavault/services/providers/instagram_provider.dart';
import 'package:mediavault/services/providers/provider.dart';
import 'package:mediavault/services/providers/remote_config.dart';
import '../helpers/mock_remote_config.dart';
import '../helpers/mock_dio.dart';

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
        options.method.toUpperCase() == 'POST' ? _resultPage : '<html></html>';
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

  group('InstagramPrimaryProvider fetchInfo (indown.net ajaxSearch)', () {
    const html = '<div class="download-items">'
        '<div class="download-items__thumb">'
        '<img src="https://cdninstagram.com/thumb.jpg"></div>'
        '<a class="abutton" href="https://rapidcdn.app/v2?token=abc">Download</a>'
        '</div>'
        '<div class="download-items">'
        '<img src="https://cdninstagram.com/p2.jpg">'
        '<a class="abutton" href="https://cdninstagram.com/p2.jpg">HD</a>'
        '</div>';

    test('POST ajaxSearch -> item video + foto', () async {
      setupMockDio(postResponseData: {
        'data': html,
      });
      final info = await InstagramPrimaryProvider().fetchInfo(
        'https://www.instagram.com/reel/ABC123/',
      );
      expect(info.qualities.length, equals(3));
      expect(info.title, contains('Reel'));
      expect(info.title, contains('ABC123'));
      expect(info.thumbnail, contains('thumb.jpg'));
      expect(info.qualities.first.extension, equals('mp4'));
      // Satu video tak dinomori ("Video HD"), banyak video = "Video HD 1..n".
      expect(info.qualities.first.label, equals('Video HD'));
      // Penomoran foto sekarang per-tipe (1 foto pun tanpa nomor).
      expect(info.qualities[1].label, equals('Foto HD'));
      expect(info.qualities.any((q) => q.label == 'Audio MP3'), isTrue);
      expect(info.source, equals('third-party'));
    });

    test('carousel campur: video dulu, lalu foto, Audio MP3 terakhir',
        () async {
      final token = base64Url
          .encode(utf8.encode('video.mp4'))
          .replaceAll('=', '');
      final html = '<html>'
          '<div class="download-items">'
          '<a href="https://cdninstagram.com/v/t51.2885-15/a_n.jpg">'
          'Download Photo</a></div>'
          '<div class="download-items">'
          '<a href="https://rapidcdn.app/v2?token=h.$token.s">Download</a></div>'
          '<div class="download-items">'
          '<a href="https://cdninstagram.com/v/t51.2885-15/b_n.jpg">'
          'Download</a></div>'
          '</html>';
      setupMockDio(postResponseData: {'data': html});
      final info = await InstagramPrimaryProvider().fetchInfo(
        'https://www.instagram.com/p/AB1/',
      );

      // Video dipindah ke depan agar mode "url isinya video" tetap video.
      expect(info.qualities.length, equals(4));
      expect(info.qualities.first.label, equals('Video HD'));
      expect(info.qualities.first.extension, equals('mp4'));
      expect(info.qualities[1].label, equals('Foto HD 1'));
      expect(info.qualities[1].extension, equals('jpg'));
      expect(info.qualities[2].label, equals('Foto HD 2'));
      expect(info.qualities.last.label, equals('Audio MP3'));
      expect(info.qualities.last.itag, equals(info.qualities.first.itag));
    });

    test('carousel foto murni: tanpa Audio MP3', () async {
      final token = base64Url
          .encode(utf8.encode('photo1.jpg'))
          .replaceAll('=', '');
      final html = '<html>'
          '<div class="download-items">'
          '<a href="https://rapidcdn.app/v2?token=h.$token.s">Download</a></div>'
          '<div class="download-items">'
          '<a href="https://cdninstagram.com/v/t51.2885-15/c_n.jpg">'
          'Download Photo</a></div>'
          '</html>';
      setupMockDio(postResponseData: {'data': html});
      final info = await InstagramPrimaryProvider().fetchInfo(
        'https://www.instagram.com/p/AB2/',
      );

      expect(info.qualities.length, equals(2));
      for (final q in info.qualities) {
        expect(q.extension, equals('jpg'));
      }
      expect(info.qualities.any((q) => q.extension == 'mp3'), isFalse);
      expect(info.qualities.any((q) => q.extension == 'mp4'), isFalse);
    });

    test('respons tanpa data -> noResult', () async {
      setupMockDio(postResponseData: {'message': 'not found'});
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

    test('tanpa link hasil -> noResult', () async {
      setupMockDio(
        postResponseData: {
          'data': '<html>kosong</html>',
        },
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

    test('POST memakai URL kanonis tanpa tracking param', () async {
      String? postedQ;
      client_lib.httpClient.httpClientAdapter = _CaptureAdapter((options) {
        final data = options.data;
        if (options.method.toUpperCase() == 'POST' && data is Map) {
          postedQ = data['q']?.toString();
        }
      });
      // _CaptureAdapter menjawab token-page lama untuk GET dan _resultPage
      // untuk POST; primary baru mem-POST JSON ajaxSearch sehingga respons
      // tidak berbentuk {data: html} -> lempar noResult (diabaikan).
      try {
        await InstagramPrimaryProvider().fetchInfo(
          'https://www.instagram.com/reel/DeJaIPygloL/?utm_source=ig_web_copy_link&exln=NTc4MTIwNjQ2YQ==',
        );
      } catch (_) {}
      expect(postedQ,
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

    test('carousel foto murni (tanpa marker): token link = Foto HD', () async {
      setupMockDio(
        plainResponse: '<div class="download-items">'
            '<div class="download-items__thumb">'
            '<img src="https://d.rapidcdn.app/thumb?token=ta"></div>'
            '<div class="download-items__btn">'
            '<a href="https://d.rapidcdn.app/v2?token=tb" class="btn">Download</a>'
            '</div></div>'
            '<div class="download-items">'
            '<div class="download-items__thumb">'
            '<img src="https://d.rapidcdn.app/thumb?token=tc"></div>'
            '<div class="download-items__btn">'
            '<a href="https://d.rapidcdn.app/v2?token=td" class="btn">Download</a>'
            '</div></div>',
      );
      final info = await InstagramFallbackProvider().fetchInfo(
        'https://www.instagram.com/p/DebLR1ux4x-/',
      );
      // Mode album murni-foto: 2 foto, tanpa video / tanpa MP3 palsu.
      expect(info.qualities.length, equals(2));
      expect(info.qualities[0].label, equals('Foto HD 1'));
      expect(info.qualities[0].extension, equals('jpg'));
      expect(info.qualities[1].label, equals('Foto HD 2'));
      expect(info.qualities[1].extension, equals('jpg'));
      expect(info.qualities.any((q) => q.extension == 'mp3'), isFalse);
    });

    test('jejak .mp4 di halaman: link token kembali jadi video', () async {
      setupMockDio(
        plainResponse: '<div class="download-items__btn">'
            '<a href="https://d.rapidcdn.app/v2?token=te" class="btn">Download</a>'
            '</div>'
            '<a href="https://cdn.ig.com/clip.mp4">Download Video</a>',
      );
      final info = await InstagramFallbackProvider().fetchInfo(
        'https://www.instagram.com/p/DebLR1ux4x-/',
      );
      expect(info.qualities.first.extension, equals('mp4'));
      expect(info.qualities.first.itag, contains('rapidcdn.app/v2'));
      expect(info.qualities.any((q) => q.extension == 'mp3'), isTrue);
    });

    test('bentuk JS innerHTML dibuka walau href ter-escape', () async {
      setupMockDio(
        plainResponse: "var s=document.getElementById('d')"
            ".innerHTML = \"<a href=\\\"https://d.rapidcdn.app/v2?token=tf\\\">"
            "Download</a>\";",
      );
      final info = await InstagramFallbackProvider().fetchInfo(
        'https://www.instagram.com/p/DebLR1ux4x-/',
      );
      // Halaman tanpa marker video → token link adalah foto.
      expect(info.qualities, isNotEmpty);
      expect(info.qualities.first.itag, contains('rapidcdn.app/v2'));
      expect(info.qualities.first.extension, equals('jpg'));
    });
  });
}
