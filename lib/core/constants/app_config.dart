abstract class AppConfig {
  /// URL GitHub raw untuk remote config OTA.
  /// Nilai ini boleh di-override saat test dengan env variable.
  static const String remoteConfigUrl =
      'https://raw.githubusercontent.com/your-org/mediavault-config/main/endpoints.json';

  /// Durasi cache remote config di memori.
  static const Duration remoteConfigCacheDuration = Duration(hours: 1);

  /// Timeout koneksi HTTP global.
  static const Duration connectTimeout = Duration(seconds: 15);

  /// Timeout receive HTTP global.
  static const Duration receiveTimeout = Duration(seconds: 60);
}
