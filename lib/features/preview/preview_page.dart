import 'package:flutter/material.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../services/providers/models.dart';
import '../download/download_controller.dart';
import 'widgets/quality_selector.dart';
import 'widgets/preview_frame.dart';
import 'widgets/video_preview.dart';

/// Halaman pratinjau hasil ANALYZE: thumbnail, judul, pilih kualitas,
/// unduh dengan progress. [controller] opsional untuk test.
class PreviewPage extends StatefulWidget {
  const PreviewPage({
    super.key,
    required this.info,
    required this.sourceUrl,
    this.controller,
  });

  final MediaInfo info;
  final String sourceUrl;
  final DownloadController? controller;

  @override
  State<PreviewPage> createState() => _PreviewPageState();
}

class _PreviewPageState extends State<PreviewPage> {
  late final DownloadController _controller;
  late String _selectedItag;
  bool _ownsController = false;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? DownloadController();
    _ownsController = widget.controller == null;

    // Utamakan format video yang memiliki audio agar saat halaman dibuka,
    // video langsung bersuara secara default.
    MediaQuality? defaultQuality;
    for (final q in widget.info.qualities) {
      if (q.extension != 'mp3' && q.extension != 'm4a') {
        if (q.hasAudio ?? false) {
          defaultQuality = q;
          break;
        }
      }
    }
    defaultQuality ??= widget.info.qualities.isNotEmpty
        ? widget.info.qualities.first
        : null;
    _selectedItag = defaultQuality?.itag ?? '';
  }

  @override
  void dispose() {
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  MediaQuality? get _selected {
    for (final q in widget.info.qualities) {
      if (q.itag == _selectedItag) return q;
    }
    return widget.info.qualities.isEmpty ? null : widget.info.qualities.first;
  }

  void _download() {
    final q = _selected;
    if (q == null) return;
    final filename = '${_sanitize(widget.info.title)}.${q.extension}';
    _controller.downloadMedia(
      url: q.itag,
      filename: filename,
      quality: q,
      headers: widget.info.downloadHeaders,
    );
  }

  static String _resolvePreviewUrl(
    MediaQuality? selected,
    List<MediaQuality> allQualities,
  ) {
    if (selected == null) return '';
    if (selected.needsMerge) {
      for (final q in allQualities) {
        if (q.extension != 'mp3' &&
            q.extension != 'm4a' &&
            (q.hasAudio ?? false)) {
          return q.itag;
        }
      }
    }
    return selected.itag;
  }

  static String _sanitize(String name) {
    var clean = name.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '').trim();
    if (clean.isEmpty) clean = 'download';
    if (clean.length > 80) clean = clean.substring(0, 80).trim();
    return clean;
  }

  static String _formatDuration(int? seconds) {
    if (seconds == null) return '--:--';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    final thumb = info.thumbnail;
    final selected = _selected;
    return Scaffold(
      backgroundColor: MoriColors.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(MoriSpacing.pagePad),
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'PREVIEW',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2,
                      color: MoriColors.ink,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: MoriColors.ink),
                  tooltip: 'Tutup',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Player / image preview mengikuti kualitas terpilih tanpa background hitam
            if (selected == null)
              Center(
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 340),
                  decoration: BoxDecoration(
                    color: MoriColors.surface,
                    border: Border.all(color: MoriColors.ink, width: 2),
                    borderRadius: BorderRadius.circular(MoriRadius.button),
                    boxShadow: const [
                      BoxShadow(
                        color: MoriColors.ink,
                        offset: Offset(3, 3),
                        blurRadius: 0,
                      ),
                    ],
                  ),
                  child: const AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Center(
                      child: Icon(
                        Icons.movie_outlined,
                        color: MoriColors.ink,
                        size: 48,
                      ),
                    ),
                  ),
                ),
              )
            else if (selected.extension == 'mp3' || selected.extension == 'm4a')
              AdaptiveImage(
                key: ValueKey('audio:${thumb ?? ''}'),
                url: thumb,
                maxHeight: 260,
                overlay: Container(
                  color: MoriColors.ink.withValues(alpha: 0.65),
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.audiotrack,
                          color: MoriColors.surface,
                          size: 48,
                        ),
                        SizedBox(height: 8),
                        Text(
                          'AUDIO TRACK (MP3)',
                          style: TextStyle(
                            color: MoriColors.surface,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else if (selected.extension != 'mp4' && selected.extension != 'webm')
              AdaptiveImage(
                key: ValueKey('img:${selected.itag}'),
                url: selected.itag,
                fallbackUrl: thumb,
              )
            else
              VideoPreview(
                key: ValueKey(_resolvePreviewUrl(selected, info.qualities)),
                url: _resolvePreviewUrl(selected, info.qualities),
                fallbackThumbnail: thumb,
                httpHeaders: info.downloadHeaders,
              ),
            const SizedBox(height: 16),
            Text(
              info.title,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: MoriColors.ink,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _Badge(info.providerName.toUpperCase()),
                _Badge(info.source == 'direct' ? 'DIRECT CDN' : 'FALLBACK'),
                if (info.author.isNotEmpty)
                  Text(
                    info.author,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: MoriColors.ink,
                    ),
                  ),
                if (info.durationSec != null)
                  Text(_formatDuration(info.durationSec),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: MoriColors.ink,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            const Text(
              'PILIH KUALITAS',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
                color: MoriColors.ink,
              ),
            ),
            const SizedBox(height: 10),
            QualitySelector(
              qualities: info.qualities,
              selectedItag: _selectedItag,
              onSelect: (itag) => setState(() => _selectedItag = itag),
            ),
            const SizedBox(height: 20),
            AnimatedBuilder(
              animation: _controller,
              builder: (context, _) => _DownloadSection(
                controller: _controller,
                onDownload: _download,
                hasQualities: info.qualities.isNotEmpty,
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: MoriColors.surface,
        border: Border.all(color: MoriColors.ink, width: 1.5),
        borderRadius: BorderRadius.circular(MoriRadius.button),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
          color: MoriColors.ink,
        ),
      ),
    );
  }
}

class _DownloadSection extends StatelessWidget {
  const _DownloadSection({
    required this.controller,
    required this.onDownload,
    required this.hasQualities,
  });

  final DownloadController controller;
  final VoidCallback onDownload;
  final bool hasQualities;

  @override
  Widget build(BuildContext context) {
    if (controller.status == DownloadStatus.downloading) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LinearProgressIndicator(
            value: controller.progress >= 0 ? controller.progress : null,
            backgroundColor: MoriColors.surface,
            color: MoriColors.ink,
          ),
          const SizedBox(height: 8),
          Text(
            controller.progress >= 0
                ? '${(controller.progress * 100).toStringAsFixed(0)}%'
                : 'Mengunduh...',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: MoriColors.ink,
            ),
          ),
        ],
      );
    }

    if (controller.status == DownloadStatus.success) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: MoriColors.surface,
          border: Border.all(color: MoriColors.ink, width: 2),
          borderRadius: BorderRadius.circular(MoriRadius.button),
          boxShadow: const [
            BoxShadow(
              color: MoriColors.ink,
              offset: Offset(3, 3),
              blurRadius: 0,
            ),
          ],
        ),
        child: Text(
          controller.savedLabel ?? 'tersimpan di galeri',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: MoriColors.ink,
          ),
        ),
      );
    }

    if (controller.status == DownloadStatus.error) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            controller.errorMessage ?? 'Gagal mengunduh',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: MoriColors.ink,
            ),
          ),
          const SizedBox(height: 8),
          _downloadButton(),
        ],
      );
    }

    return _downloadButton();
  }

  Widget _downloadButton() {
    return ElevatedButton(
      onPressed: hasQualities ? onDownload : null,
      style: ElevatedButton.styleFrom(
        backgroundColor: MoriColors.ink,
        foregroundColor: MoriColors.surface,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MoriRadius.button),
        ),
        elevation: 0,
      ),
      child: const Text(
        'DOWNLOAD',
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w800,
          letterSpacing: 2,
        ),
      ),
    );
  }
}
