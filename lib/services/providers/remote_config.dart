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
/// BUNDLED-SEGERA: analisa tidak pernah menunggu fetch OTA. Config jarak
/// jauh di-refresh di background (timeout pendek, tanpa retry) sehingga
/// raw.githubusercontent yang lambat/diblokir jaringan seluler tidak
/// membuat tombol analisa berasa "loading terus".
class RemoteConfig {
  RemoteConfig._();
  static final RemoteConfig instance = RemoteConfig._();

  Map<String, EndpointConfig>? _cache;
  DateTime? _cachedAt;
  bool _refreshing = false;

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
    if (_cache != null) {
      _scheduleRefresh();
      return _cache!;
    }
    // Belum ada nilai sama sekali: pakai bundled segera, OTA menyusul.
    final bundled = await _loadBundled();
    _cache ??= bundled;
    _cachedAt = DateTime.now();
    _scheduleRefresh();
    return _cache!;
  }

  bool _isCacheValid() {
    if (_cache == null || _cachedAt == null) return false;
    return DateTime.now().difference(_cachedAt!) < AppConfig.remoteConfigCacheDuration;
  }

  /// Refresh OTA tanpa memblok pemuat. Gagal (mis. host tak terjangkau)
  /// tidak mengubah cache — hanya menepi ulang jangka waktu cache.
  void _scheduleRefresh() {
    if (_refreshing) return;
    _refreshing = true;
    () async {
      try {
        final remote = await _fetchRemote();
        if (remote.isNotEmpty) {
          _cache = remote;
          _cachedAt = DateTime.now();
        }
      } catch (_) {
        // Fetch gagal → tetap pakai cache terakhir / bundled.
        _cachedAt = DateTime.now();
      } finally {
        _refreshing = false;
      }
    }();
  }

  /// OTA hanya boleh menghabiskan beberapa detik: config bukan alasan
  /// analisa menunggu. Tanpa retry (mvNoRetry) agar tidak dua kali lipat.
  Future<Map<String, EndpointConfig>> _fetchRemote() async {
    final response = await httpClient.get<String>(
      AppConfig.remoteConfigUrl,
      options: Options(
        responseType: ResponseType.plain,
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 6),
        sendTimeout: const Duration(seconds: 6),
        extra: const {'mvNoRetry': true},
      ),
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
