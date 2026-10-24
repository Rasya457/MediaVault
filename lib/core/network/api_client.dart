import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:cookie_jar/cookie_jar.dart';
import '../constants/app_config.dart';

/// Singleton Dio yang dipakai semua provider.
/// Tidak ada base URL backend — setiap provider atur URL sendiri.
final Dio httpClient = _buildClient();

Dio _buildClient() {
  final dio = Dio(
    BaseOptions(
      connectTimeout: AppConfig.connectTimeout,
      receiveTimeout: AppConfig.receiveTimeout,
      headers: {
        // User-Agent mirip Android Chrome 125 agar tidak diblokir oleh
        // third-party scraper endpoint yang memvalidasi UA.
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 14; Pixel 8) '
            'AppleWebKit/537.36 (KHTML, like Gecko) '
            'Chrome/125.0.0.0 Mobile Safari/537.36',
        'Accept-Language': 'en-US,en;q=0.9',
      },
    ),
  );
  dio.interceptors.add(_RetryInterceptor(dio));
  // Cookie jar memori — wajib untuk flow CSRF (mis. indown.io).
  dio.interceptors.add(CookieManager(CookieJar()));
  return dio;
}

/// Interceptor retry 1x untuk GET idempoten.
/// Tidak retry POST agar tidak menyebabkan side-effect ganda.
class _RetryInterceptor extends Interceptor {
  _RetryInterceptor(this._dio);
  final Dio _dio;

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final req = err.requestOptions;
    final isGet = req.method.toUpperCase() == 'GET';
    final alreadyRetried = req.extra['_retried'] == true;
    // Permintaan yang bertanda extra 'mvNoRetry' dikecualikan
    // (mis. fetch OTA config — jangan menggandakan waktu tunggu).
    final noRetry = req.extra['mvNoRetry'] == true;

    if (isGet && !alreadyRetried && !noRetry && _shouldRetry(err.type)) {
      req.extra['_retried'] = true;
      try {
        final response = await _dio.fetch<dynamic>(req);
        handler.resolve(response);
        return;
      } on DioException catch (e) {
        handler.next(e);
        return;
      }
    }
    handler.next(err);
  }

  bool _shouldRetry(DioExceptionType type) {
    return type == DioExceptionType.connectionTimeout ||
        type == DioExceptionType.receiveTimeout ||
        type == DioExceptionType.connectionError;
  }
}
