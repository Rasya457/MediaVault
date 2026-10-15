import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediavault/features/download/download_service.dart';

/// Adapter yang mengembalikan byte tetap tanpa jaringan.
class _BytesAdapter implements HttpClientAdapter {
  final List<int> bytes;

  _BytesAdapter(this.bytes);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async =>
      ResponseBody.fromBytes(
        bytes,
        200,
        headers: {
          Headers.contentLengthHeader: [bytes.length.toString()],
        },
      );

  @override
  void close({bool force = false}) {}
}

void main() {
  test('downloadToTemp menulis file + lapor progress', () async {
    final dio = Dio()..httpClientAdapter = _BytesAdapter([1, 2, 3, 4]);
    final svc = DownloadService(dio: dio);

    var calls = 0;
    final file = await svc.downloadToTemp(
      url: 'https://cdn.example/v.mp4',
      filename: 'uji-в.mp4',
      onProgress: (received, total) {
        expect(received, greaterThan(0));
        calls++;
      },
    );

    expect(await file.readAsBytes(), [1, 2, 3, 4]);
    expect(calls, greaterThan(0));
    await file.delete();
  });

  test('token dibatalkan -> DownloadCancelled', () async {
    final dio = Dio()..httpClientAdapter = _BytesAdapter([1, 2, 3]);
    final svc = DownloadService(dio: dio);

    final token = CancelToken()..cancel();
    expect(
      svc.downloadToTemp(
        url: 'https://cdn.example/v.mp4',
        filename: 'batal.mp4',
        cancelToken: token,
      ),
      throwsA(isA<DownloadCancelled>()),
    );
  });
}
