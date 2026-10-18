import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../../core/theme/design_tokens.dart';

/// Widget pemutar audio (MP3/M4A) interaktif ala Apple Music / Mori:
/// - Menampilkan album cover/thumbnail dengan sudut membulat 18px & bayangan lembut
/// - Tombol Play / Pause / Replay dengan animasi halus
/// - Progress slider interaktif dengan durasi berjalan (0:15 / 3:30)
/// - Indikator status audio (MP3 320kbps / Audio Preview)
class AudioPreview extends StatefulWidget {
  const AudioPreview({
    super.key,
    required this.audioUrl,
    this.thumbnailUrl,
    this.title,
    this.artist,
    this.durationSec,
    this.headers,
  });

  final String audioUrl;
  final String? thumbnailUrl;
  final String? title;
  final String? artist;
  final int? durationSec;
  final Map<String, String>? headers;

  @override
  State<AudioPreview> createState() => _AudioPreviewState();
}

class _AudioPreviewState extends State<AudioPreview>
    with SingleTickerProviderStateMixin {
  VideoPlayerController? _controller;
  bool _initialized = false;
  bool _isPlaying = false;
  bool _hasError = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _initPlayer();
  }

  @override
  void didUpdateWidget(AudioPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.audioUrl != widget.audioUrl) {
      _initPlayer();
    }
  }

  Future<void> _initPlayer() async {
    final old = _controller;
    _controller = null;
    await old?.dispose();

    if (!mounted) return;
    setState(() {
      _initialized = false;
      _hasError = false;
      _position = Duration.zero;
      _duration = widget.durationSec != null
          ? Duration(seconds: widget.durationSec!)
          : Duration.zero;
    });

    final uri = Uri.tryParse(widget.audioUrl);
    if (uri == null || !uri.hasScheme) {
      if (mounted) setState(() => _hasError = true);
      return;
    }

    try {
      final ctrl = VideoPlayerController.networkUrl(
        uri,
        httpHeaders: widget.headers ?? const {},
      );
      _controller = ctrl;
      await ctrl.initialize();

      if (!mounted) {
        await ctrl.dispose();
        return;
      }

      ctrl.addListener(_onControllerUpdate);
      setState(() {
        _initialized = true;
        _duration = ctrl.value.duration;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _initialized = false;
        });
      }
    }
  }

  void _onControllerUpdate() {
    final ctrl = _controller;
    if (ctrl == null || !mounted) return;

    final playing = ctrl.value.isPlaying;
    final pos = ctrl.value.position;
    final dur = ctrl.value.duration;

    if (playing != _isPlaying) {
      if (playing) {
        _pulseController.repeat(reverse: true);
      } else {
        _pulseController.stop();
      }
    }

    if (playing != _isPlaying || pos != _position || dur != _duration) {
      setState(() {
        _isPlaying = playing;
        _position = pos;
        if (dur > Duration.zero) _duration = dur;
      });
    }
  }

  void _togglePlayPause() {
    final ctrl = _controller;
    if (ctrl == null || !_initialized) return;

    if (ctrl.value.position >= ctrl.value.duration && ctrl.value.duration > Duration.zero) {
      ctrl.seekTo(Duration.zero);
      ctrl.play();
    } else if (ctrl.value.isPlaying) {
      ctrl.pause();
    } else {
      ctrl.play();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _controller?.removeListener(_onControllerUpdate);
    _controller?.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final mins = d.inMinutes;
    final secs = d.inSeconds % 60;
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = MoriScheme.of(context);
    final thumb = widget.thumbnailUrl;
    final currentSec = _position.inMilliseconds.toDouble();
    final maxSec = _duration.inMilliseconds.toDouble();
    final sliderVal = (maxSec > 0) ? currentSec.clamp(0.0, maxSec) : 0.0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.hairline),
        boxShadow: MoriShadow.card,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Album Cover Artwork
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: MoriShadow.product,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: thumb != null && thumb.startsWith('http')
                      ? Image.network(
                          thumb,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              _buildFallbackArt(),
                        )
                      : _buildFallbackArt(),
                ),
              ),

              // Audio Format Badge (MP3)
              Positioned(
                top: 12,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.70),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.graphic_eq_rounded, color: Colors.white, size: 14),
                      SizedBox(width: 4),
                      Text(
                        'MP3',
                        style: TextStyle(
                          fontFamily: 'Geist',
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Animated Soundwave Indicator saat bermain
              if (_isPlaying)
                Positioned(
                  bottom: 12,
                  left: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: scheme.accentFill,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      'MEMUTAR PRATINJAU',
                      style: TextStyle(
                        fontFamily: 'Geist',
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 20),

          // Progress Slider
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              activeTrackColor: scheme.accent,
              inactiveTrackColor: scheme.surfaceVariant,
              thumbColor: scheme.accent,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayColor: scheme.accent.withValues(alpha: 0.15),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: Slider(
              value: sliderVal,
              min: 0.0,
              max: maxSec > 0 ? maxSec : 1.0,
              onChanged: _initialized && maxSec > 0
                  ? (val) {
                      _controller?.seekTo(Duration(milliseconds: val.toInt()));
                    }
                  : null,
            ),
          ),

          // Duration labels (0:15 / 3:30)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatDuration(_position),
                  style: TextStyle(
                    fontFamily: 'Geist',
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: scheme.secondary,
                  ),
                ),
                Text(
                  _formatDuration(_duration),
                  style: TextStyle(
                    fontFamily: 'Geist',
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: scheme.secondary,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Media Controls (Rewind 5s, Play/Pause, Forward 5s)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Rewind 5s
              IconButton(
                icon: const Icon(Icons.replay_5_rounded),
                iconSize: 28,
                color: scheme.ink,
                tooltip: 'Mundur 5 detik',
                onPressed: _initialized
                    ? () {
                        final newPos = _position - const Duration(seconds: 5);
                        _controller?.seekTo(newPos < Duration.zero ? Duration.zero : newPos);
                      }
                    : null,
              ),

              const SizedBox(width: 16),

              // Main Play/Pause Button
              GestureDetector(
                onTap: _togglePlayPause,
                child: Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: scheme.accentFill,
                    shape: BoxShape.circle,
                    // Tint ink — halo berwarna tidak diperkenankan.
                    boxShadow: MoriShadow.button,
                  ),
                  child: Center(
                    child: _hasError
                        ? const Icon(Icons.refresh_rounded, color: Colors.white, size: 28)
                        : !_initialized && _controller != null
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.white,
                                ),
                              )
                            : Icon(
                                _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                color: Colors.white,
                                size: 34,
                              ),
                  ),
                ),
              ),

              const SizedBox(width: 16),

              // Forward 5s
              IconButton(
                icon: const Icon(Icons.forward_5_rounded),
                iconSize: 28,
                color: scheme.ink,
                tooltip: 'Maju 5 detik',
                onPressed: _initialized
                    ? () {
                        final newPos = _position + const Duration(seconds: 5);
                        _controller?.seekTo(newPos > _duration ? _duration : newPos);
                      }
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFallbackArt() {
    final scheme = MoriScheme.of(context);
    return Container(
      color: scheme.surfaceVariant,
      child: Center(
        child: Icon(
          Icons.music_note_rounded,
          size: 72,
          color: scheme.secondary,
        ),
      ),
    );
  }
}
