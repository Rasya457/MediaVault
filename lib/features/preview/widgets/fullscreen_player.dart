import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import '../../../core/theme/design_tokens.dart';

/// Fullscreen untuk controller yang sama (tidak mengambil alih dispose).
/// Dunia menonton murni hitam: kontrol memakai konstanta [MoriVideoScene],
/// bukan warna tema aplikasi.
class FullscreenPlayer extends StatelessWidget {
  const FullscreenPlayer({super.key, required this.controller});

  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: AspectRatio(
                aspectRatio: controller.value.aspectRatio,
                child: VideoPlayer(controller),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  // Lingkaran frosted putih gaya Apple di atas video
                  color: MoriVideoScene.fullscreenFill,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: MoriVideoScene.fullscreenBorder,
                    width: 1,
                  ),
                ),
                child: IconButton(
                  icon: const Icon(
                    Icons.fullscreen_exit,
                    // Ikon putih: kontras penuh di dunia hitam
                    color: MoriVideoScene.fullscreenIcon,
                    size: 26,
                  ),
                  tooltip: 'Keluar fullscreen',
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    Navigator.of(context).pop();
                  },
                  padding: EdgeInsets.zero,
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: VideoProgressIndicator(
                controller,
                allowScrubbing: true,
                colors: const VideoProgressColors(
                  // Progress terang di atas hitam (aksen dark, bukan tema)
                  playedColor: MoriVideoScene.fullscreenPlayed,
                  bufferedColor: MoriVideoScene.fullscreenBuffered,
                  backgroundColor: MoriVideoScene.fullscreenTrack,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
