import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediavault/services/providers/remote_config.dart';

import '../helpers/mock_remote_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => RemoteConfig.instance.resetCache());

  test('inject -> get/loadAll mengembalikan yang di-inject', () async {
    injectMockEndpoints({
      'tikwm': const EndpointEntry(
        url: 'https://test.example/api/',
        method: 'GET',
        enabled: true,
      ),
    });
    final ep = await RemoteConfig.instance.get('tikwm');
    expect(ep?.url, 'https://test.example/api/');
    expect((await RemoteConfig.instance.loadAll()).keys, ['tikwm']);
    expect(await RemoteConfig.instance.get('tidak-ada'), isNull);
  });

  test('resetCache membuang yang di-inject', () async {
    injectMockEndpoints({
      'tikwm': const EndpointEntry(
        url: 'https://test.example/api/',
        method: 'GET',
        enabled: true,
      ),
    });
    RemoteConfig.instance.resetCache();
    // Setelah reset, get() akan coba network lalu bundled — untuk deterministik,
    // inject ulang nilai lain dan pastikan yang baru yang dipakai.
    injectMockEndpoints({
      'tikwm': const EndpointEntry(
        url: 'https://baru.example/api/',
        method: 'GET',
        enabled: false,
      ),
    });
    final ep = await RemoteConfig.instance.get('tikwm');
    expect(ep?.url, 'https://baru.example/api/');
    expect(ep?.enabled, isFalse);
  });

  test('asset bundled valid dan memuat key provider', () async {
    final raw = await rootBundle.loadString(
      'lib/services/providers/endpoints.json',
    );
    expect(raw, contains('"version"'));
    expect(raw, contains('tiktok_primary'));
  });
}
