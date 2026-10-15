import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mediavault/features/download/download_controller.dart';

/// E2E di device nyata: unduh file sample publik lalu simpan.
/// Izin galeri di-grant via adb SEBELUM run agar tanpa dialog:
///   adb shell pm grant com.example.mediavault android.permission.READ_MEDIA_IMAGES
///   adb shell pm grant com.example.mediavault android.permission.READ_MEDIA_VIDEO
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('E2E video mp4 -> galeri', (tester) async {
    final c = DownloadController();
    await c.downloadMedia(
      url:
          'https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/360/Big_Buck_Bunny_360_10s_1MB.mp4',
      filename: 'e2e_video.mp4',
    );
    expect(c.status, DownloadStatus.success, reason: c.errorMessage);
    expect(c.savedLabel, contains('galeri'));
  });

  testWidgets('E2E gambar jpg -> galeri', (tester) async {
    final c = DownloadController();
    await c.downloadMedia(
      url: 'https://picsum.photos/seed/mediavault/400/400.jpg',
      filename: 'e2e_gambar.jpg',
    );
    expect(c.status, DownloadStatus.success, reason: c.errorMessage);
  });

  testWidgets('E2E audio mp3 -> folder aplikasi', (tester) async {
    final c = DownloadController();
    await c.downloadMedia(
      url: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3',
      filename: 'e2e_audio.mp3',
    );
    expect(c.status, DownloadStatus.success, reason: c.errorMessage);
    expect(c.savedLabel, contains('aplikasi'));
  });
}
