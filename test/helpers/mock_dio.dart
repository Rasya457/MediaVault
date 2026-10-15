import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:mediavault/core/network/api_client.dart' as client_lib;

/// Buat Dio dengan HttpClientAdapter palsu yang mengembalikan respons mock.
/// Tidak hit endpoint nyata — aman untuk unit test.
Dio setupMockDio({
  Map<String, dynamic>? postResponseData,
  Map<String, dynamic>? getResponseData,
  String? plainResponse,
  String? getPlain,
  String? postPlain,
  int statusCode = 200,
  bool throwTimeout = false,
}) {
  final dio = client_lib.httpClient;
  dio.httpClientAdapter = _FakeAdapter(
    postData: postResponseData,
    getData: getResponseData,
    plain: plainResponse,
    getPlain: getPlain,
    postPlain: postPlain,
    statusCode: statusCode,
    throwTimeout: throwTimeout,
  );
  return dio;
}

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter({
    this.postData,
    this.getData,
    this.plain,
    this.getPlain,
    this.postPlain,
    required this.statusCode,
    required this.throwTimeout,
  });

  final Map<String, dynamic>? postData;
  final Map<String, dynamic>? getData;
  final String? plain;
  final String? getPlain;
  final String? postPlain;
  final int statusCode;
  final bool throwTimeout;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (throwTimeout) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionTimeout,
        message: 'Fake timeout',
      );
    }
    final isPost = options.method.toUpperCase() == 'POST';
    final data = isPost
        ? (postPlain ?? plain ?? jsonEncode(postData ?? {}))
        : (getPlain ?? plain ?? jsonEncode(getData ?? {}));

    return ResponseBody.fromString(data, statusCode, headers: {
      'content-type': ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}
