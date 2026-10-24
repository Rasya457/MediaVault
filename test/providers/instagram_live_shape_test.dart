// Regresi pola respons LIVE Instagram (dipanen langsung dari indown.net dan
// snapsave.app, 24 Okt 2026, post foto carousel publik p/DalfZ3Jn8yi).
// Nilai penting yang dikunci:
// - SnapSave: raw eval-script berisi CSS yang SELALU menyebut icon-dlvideo
//   (walau post foto) — klasifikasi TIDAK BOLEH pakai flag halaman-global.
// - Indown: data HTML dengan tombol "Download Image" + token JWT snapcdn
//   yang payload-nya memuat URL cdninstagram ...jpg.
// Kedua jawaban harus menghasilkan Foto HD (jpg), tanpa video/MP3 palsu.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediavault/services/providers/instagram_provider.dart';
import 'package:mediavault/services/providers/remote_config.dart';
import '../helpers/mock_remote_config.dart';
import '../helpers/mock_dio.dart';

void main() {
  setUp(() {
    injectMockEndpoints({
      'instagram_primary': const EndpointEntry(
        url: 'https://indown.net/api/ajaxSearch',
        method: 'POST',
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

  test('LIVE indown: carousel foto -> Foto HD 1..n tanpa MP3', () async {
    final body = File('test/fixtures/indown_photo_carousel.json')
        .readAsStringSync();
    setupMockDio(plainResponse: body);
    final info = await InstagramPrimaryProvider()
        .fetchInfo('https://www.instagram.com/p/DalfZ3Jn8yi/');
    expect(info.qualities.length, equals(2));
    for (final q in info.qualities) {
      expect(q.extension, equals('jpg'));
      expect(q.label, startsWith('Foto HD'));
      expect(q.itag, startsWith('https://dl.snapcdn.app/get?token='));
    }
    expect(info.qualities.any((q) => q.hasAudio == true), isFalse);
    expect(info.qualities.any((q) => q.extension == 'mp3'), isFalse);
  });

  test('LIVE snapsave: raw obfuscated carousel foto -> Foto HD tanpa MP3',
      () async {
    final raw =
        File('test/fixtures/snap_photo_carousel.txt').readAsStringSync();
    setupMockDio(plainResponse: raw);
    final info = await InstagramFallbackProvider()
        .fetchInfo('https://www.instagram.com/p/DalfZ3Jn8yi/');
    expect(info.qualities.length, equals(2));
    for (final q in info.qualities) {
      expect(q.extension, equals('jpg'));
      expect(q.label, startsWith('Foto HD'));
      expect(q.itag, startsWith('https://d.rapidcdn.app/v2?token='));
    }
    expect(info.qualities.any((q) => q.extension == 'mp3'), isFalse);
    // CSS halaman asli memuat icon-dlvideo walau post foto — yang
    // membuktikan flag halaman-global terbukti salah; hasil decoder tetap
    // mengklasifikasi foto:
    final decoded = decodeSnapSave(raw) ?? '';
    expect(decoded.contains('icon-dlvideo'), isTrue);
  });
}
