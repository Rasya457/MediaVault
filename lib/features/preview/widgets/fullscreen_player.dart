import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Fullscreen untuk controller yang sama (tidak mengambil alih dispose).
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
              child: IconButton(
                icon: const Icon(
                  Icons.fullscreen_exit,
                  color: Colors.white,
                  size: 30,
                ),
                tooltip: 'Keluar fullscreen',
                onPressed: () => Navigator.of(context).pop(),
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
                  playedColor: Colors.white,
                  bufferedColor: Colors.white38,
                  backgroundColor: Colors.white24,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
