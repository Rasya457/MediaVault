import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:dio/dio.dart';
import '../../core/constants/app_config.dart';
import '../../core/network/api_client.dart';

/// Model untuk satu endpoint dalam remote config.
class EndpointConfig {
  const EndpointConfig({
    required this.url,
    required this.method,
    required this.enabled,
  });

  final String url;
  final String method;
  final bool enabled;

  factory EndpointConfig.fromJson(Map<String, dynamic> json) {
    return EndpointConfig(
      url: json['url'] as String,
      method: (json['method'] as String? ?? 'GET').toUpperCase(),
      enabled: json['enabled'] as bool? ?? true,
    );
  }
}

/// Loader remote config OTA dengan cache memori 1 jam.
/// Fallback otomatis ke bundled endpoints.json bila fetch gagal.
class RemoteConfig {
  RemoteConfig._();
  static final RemoteConfig instance = RemoteConfig._();

  Map<String, EndpointConfig>? _cache;
  DateTime? _cachedAt;

  /// Kembalikan config endpoint untuk [providerId].
  /// Null jika id tidak ditemukan.
  Future<EndpointConfig?> get(String providerId) async {
    final all = await _load();
    return all[providerId];
  }

  /// Kembalikan semua endpoint config.
  Future<Map<String, EndpointConfig>> loadAll() => _load();

  Future<Map<String, EndpointConfig>> _load() async {
    if (_isCacheValid()) return _cache!;
    try {
      _cache = await _fetchRemote();
      _cachedAt = DateTime.now();
    } catch (_) {
      // Fetch gagal → pakai bundled
      _cache = await _loadBundled();
      _cachedAt = DateTime.now();
    }
    return _cache!;
  }

  bool _isCacheValid() {
    if (_cache == null || _cachedAt == null) return false;
    return DateTime.now().difference(_cachedAt!) < AppConfig.remoteConfigCacheDuration;
  }

  Future<Map<String, EndpointConfig>> _fetchRemote() async {
    final response = await httpClient.get<String>(
      AppConfig.remoteConfigUrl,
      options: Options(responseType: ResponseType.plain),
    );
    return _parse(response.data ?? '{}');
  }

  Future<Map<String, EndpointConfig>> _loadBundled() async {
    final raw = await rootBundle.loadString(
      'lib/services/providers/endpoints.json',
    );
    return _parse(raw);
  }

  Map<String, EndpointConfig> _parse(String raw) {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final providers = json['providers'] as Map<String, dynamic>? ?? {};
    return providers.map(
      (key, value) =>
          MapEntry(key, EndpointConfig.fromJson(value as Map<String, dynamic>)),
    );
  }

  /// Untuk test: reset cache sehingga config di-reload.
  void resetCache() {
    _cache = null;
    _cachedAt = null;
  }

  /// Untuk test: inject config tanpa akses network/assets.
  void injectForTest(Map<String, EndpointConfig> config) {
    _cache = config;
    _cachedAt = DateTime.now();
  }
}
