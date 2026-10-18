import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../core/theme/design_tokens.dart';
import 'fullscreen_player.dart';
import 'preview_frame.dart';

/// Pratinjau video streaming dengan rasio adaptif: portrait maupun
/// landscape mengikuti rasio asli video tanpa background hitam.
///
/// Otomatis diputar begitu siap, dan diulang dari awal (loop) saat selesai.
/// Thumbnail ditampilkan sebagai poster sampai frame video pertama jalan,
/// jadi tidak ada layar hitam di antara loading dan pemutaran.
///
/// Kontrol memakai konstanta [MoriVideoScene] — dunia menonton selalu gelap
/// dengan bar frosted putih, tidak mengikuti tema aplikasi.
class VideoPreview extends StatefulWidget {
  const VideoPreview({
    super.key,
    required this.url,
    this.fallbackThumbnail,
    this.httpHeaders = const {},
  });

  final String url;
  final String? fallbackThumbnail;

  /// Header untuk request streaming (mis. User-Agent client Innertube).
  /// Tanpa ini, URL googlevideo sering ditolak dengan 403.
  final Map<String, String> httpHeaders;

  @override
  State<VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends State<VideoPreview> {
  VideoPlayerController? _controller;
  bool _failed = false;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final uri = Uri.tryParse(widget.url);
    if (uri == null || widget.url.isEmpty) {
      setState(() => _failed = true);
      return;
    }

    final controller = VideoPlayerController.networkUrl(
      uri,
      httpHeaders: widget.httpHeaders,
    );
    try {
      await controller.initialize();
      // Suara menyala dan video diulang otomatis dari awal.
      await controller.setVolume(1.0);
      await controller.setLooping(true);
    } catch (_) {
      controller.dispose();
      if (!mounted) return;
      setState(() => _failed = true);
      return;
    }
    if (!mounted) {
      controller.dispose();
      return;
    }
    controller.addListener(_onValue);
    setState(() => _controller = controller);
    // Autoplay begitu siap.
    await controller.play();
  }

  void _onValue() {
    final c = _controller;
    if (c == null || !mounted) return;
    final v = c.value;

    if (v.hasError) {
      _controller = null;
      setState(() => _failed = true);
      // Dispose setelah frame ini selesai, supaya VideoPlayer yang masih
      // terpasang tidak memakai controller yang sudah di-dispose.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        c.removeListener(_onValue);
        c.dispose();
      });
      return;
    }

    if (!_started && v.isPlaying && v.position > Duration.zero) {
      setState(() => _started = true);
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_onValue);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      // Loading atau gagal: thumbnail dengan rasio aslinya + penanda status.
      return AdaptiveImage(
        key: ValueKey('poster:${widget.fallbackThumbnail ?? ''}'),
        url: widget.fallbackThumbnail,
        maxHeight: 340,
        overlay: Center(
          child: _failed
              ? const Icon(
                  Icons.broken_image_outlined,
                  color: Color(0xFFFFFFFF),
                  size: 48,
                )
              : const SizedBox(
                  width: 30,
                  height: 30,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Color(0xFFFFFFFF),
                  ),
                ),
        ),
      );
    }

    return _PlayerBody(
      controller: controller,
      poster: _started ? null : widget.fallbackThumbnail,
      onFullscreen: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => FullscreenPlayer(controller: controller),
        ),
      ),
    );
  }
}

class _PlayerBody extends StatelessWidget {
  const _PlayerBody({
    required this.controller,
    required this.onFullscreen,
    this.poster,
  });

  final VideoPlayerController controller;
  final VoidCallback onFullscreen;

  /// Thumbnail yang menutupi video sampai frame pertama jalan. Null = tidak ada.
  final String? poster;

  void _togglePlay() {
    if (controller.value.isPlaying) {
      controller.pause();
    } else {
      controller.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    final rawRatio = controller.value.aspectRatio;
    final ratio = rawRatio > 0 ? rawRatio : (16 / 9);
    final isPortrait = ratio < 1.0;
    final posterUrl = poster;

    return PreviewFrame(
      aspectRatio: ratio,
      maxHeight: isPortrait ? 460 : 340,
      child: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            onTap: _togglePlay,
            child: VideoPlayer(controller),
          ),
          if (posterUrl != null && posterUrl.isNotEmpty)
            Positioned.fill(
              child: IgnorePointer(
                child: Image.network(
                  posterUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                      const SizedBox.shrink(),
                ),
              ),
            ),
          Positioned(
            left: 8,
            right: 8,
            bottom: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                // Bar frosted putih di atas video (adegan menonton, bukan tema).
                color: MoriVideoScene.barFill,
                border: Border.all(
                  color: MoriVideoScene.barBorder,
                  width: 1,
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x14000000),
                    offset: Offset(0, 2),
                    blurRadius: 8,
                  ),
                ],
              ),
              // Ikon mengikuti state player (play/pause/mute) secara langsung,
              // termasuk saat video loop dari awal.
              child: ValueListenableBuilder<VideoPlayerValue>(
                valueListenable: controller,
                builder: (context, value, _) {
                  return Row(
                    children: [
                      GestureDetector(
                        onTap: _togglePlay,
                        child: Icon(
                          value.isPlaying ? Icons.pause : Icons.play_arrow,
                          color: MoriVideoScene.played,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () =>
                            controller.setVolume(value.volume > 0 ? 0.0 : 1.0),
                        child: Icon(
                          value.volume > 0
                              ? Icons.volume_up
                              : Icons.volume_off,
                          color: MoriVideoScene.played,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: VideoProgressIndicator(
                          controller,
                          allowScrubbing: true,
                          colors: const VideoProgressColors(
                            playedColor: MoriVideoScene.played,
                            bufferedColor: MoriVideoScene.buffered,
                            backgroundColor: MoriVideoScene.track,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: onFullscreen,
                        child: const Icon(
                          Icons.fullscreen,
                          color: MoriVideoScene.played,
                          size: 26,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
