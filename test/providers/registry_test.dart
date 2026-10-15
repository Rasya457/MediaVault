import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediavault/core/network/api_client.dart';
import 'package:mediavault/services/providers/provider.dart';
import 'package:mediavault/services/providers/registry.dart';
import 'package:mediavault/services/providers/remote_config.dart';

import '../helpers/mock_remote_config.dart';

/// Adapter yang menjawab beda per endpoint: primary selalu gagal,
/// fallback selalu sukses — membuktikan rantai fallback memakai
/// provider asli, bukan stub.
class _PathAwareAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final Map<String, dynamic> json;
    if (options.path.contains('tikdownloader')) {
      json = {'status': 'error', 'message': 'primary down'};
    } else {
      json = {
        'code': 0,
        'data': {
          'play': 'https://cdn.tiktok.com/hd.mp4',
          'title': 'Via Fallback',
          'author': {'nickname': 'akun'},
        },
      };
    }
    return ResponseBody.fromString(
      jsonEncode(json),
      200,
      headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  final realAdapter = httpClient.httpClientAdapter;

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
    httpClient.httpClientAdapter = _PathAwareAdapter();
  });

  tearDown(() {
    RemoteConfig.instance.resetCache();
    httpClient.httpClientAdapter = realAdapter;
  });

  test('rantai asli: primary gagal -> fallback dipakai', () async {
    final info = await ProviderRegistry.instance.fetchInfo(
      'https://www.tiktok.com/@u/video/1',
    );
    expect(info.providerName, 'TikWm');
    expect(info.title, 'Via Fallback');
    expect(
      await ProviderRegistry.instance.fetchDownloadUrl(
        'https://www.tiktok.com/@u/video/1',
      ),
      'https://cdn.tiktok.com/hd.mp4',
    );
  });

  test('URL tak dikenal -> invalidUrl tanpa sentuh jaringan', () async {
    expect(
      ProviderRegistry.instance.fetchInfo('https://example.com/x'),
      throwsA(
        isA<ProviderException>().having(
          (e) => e.kind,
          'kind',
          ProviderErrorKind.invalidUrl,
        ),
      ),
    );
  });
}
