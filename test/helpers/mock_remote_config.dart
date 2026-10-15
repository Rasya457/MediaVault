import 'package:mediavault/services/providers/remote_config.dart';

class EndpointEntry {
  const EndpointEntry({
    required this.url,
    required this.method,
    required this.enabled,
  });
  final String url;
  final String method;
  final bool enabled;
}

/// Inject endpoint config palsu ke RemoteConfig tanpa hit network/assets.
void injectMockEndpoints(Map<String, EndpointEntry> entries) {
  RemoteConfig.instance.injectForTest(
    entries.map(
      (k, v) => MapEntry(
        k,
        EndpointConfig(url: v.url, method: v.method, enabled: v.enabled),
      ),
    ),
  );
}
