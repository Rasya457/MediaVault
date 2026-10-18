import 'package:flutter/material.dart';

import '../../../core/theme/design_tokens.dart';
import '../batch_download_controller.dart';

/// Baris satu lagu playlist: nomor/indikator putar, judul + artis,
/// tombol pratinjau putar audio, serta tombol unduh 1 lagu tersendiri.
class ProgressTile extends StatelessWidget {
  const ProgressTile({
    super.key,
    required this.index,
    required this.item,
    this.isSelected = false,
    this.isPlaying = false,
    this.onTap,
    this.onPlay,
    this.onDownload,
  });

  /// Nomor lagu (mulai 1) untuk label "01", "02", dst.
  final int index;
  final BatchItem item;

  /// True jika lagu ini sedang dipilih di pemutar audio pratinjau.
  final bool isSelected;

  /// True jika lagu ini sedang aktif berputar di pemutar pratinjau.
  final bool isPlaying;

  /// Ketuk baris untuk aksi utama (unduh lagu ini / aksi default).
  final VoidCallback? onTap;

  /// Ketuk tombol play untuk memutar pratinjau audio lagu ini.
  final VoidCallback? onPlay;

  /// Ketuk tombol unduh untuk mengunduh lagu ini saja.
  final VoidCallback? onDownload;

  @override
  Widget build(BuildContext context) {
    final scheme = MoriScheme.of(context);
    final status = _statusText();
    final subtitleParts = <String>[
      if (item.artist.isNotEmpty) item.artist,
      if (status.isNotEmpty) status,
    ];
    final subtitle = subtitleParts.join(' · ');

    final borderColor = isSelected ? scheme.accent : scheme.hairline;
    final bgColor = isSelected
        ? scheme.accent.withValues(alpha: 0.08)
        : scheme.surface;

    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(MoriRadius.tile),
      child: InkWell(
        borderRadius: BorderRadius.circular(MoriRadius.tile),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(MoriRadius.tile),
            border: Border.all(
              color: borderColor,
              width: isSelected ? 1.5 : MoriBorder.tile,
            ),
          ),
          child: Row(
            children: [
              // Kolom kiri: Tombol Play/Pause pratinjau audio atau nomor urut
              SizedBox(
                width: 34,
                child: Center(
                  child: isPlaying
                      ? InkWell(
                          onTap: onPlay,
                          borderRadius: BorderRadius.circular(999),
                          child: Icon(
                            Icons.graphic_eq_rounded,
                            color: scheme.accent,
                            size: 20,
                          ),
                        )
                      : (onPlay != null)
                          ? InkWell(
                              onTap: onPlay,
                              borderRadius: BorderRadius.circular(999),
                              child: Icon(
                                Icons.play_circle_outline_rounded,
                                color: isSelected ? scheme.accent : scheme.secondary,
                                size: 22,
                              ),
                            )
                          : Text(
                              index.toString().padLeft(2, '0'),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: isSelected ? scheme.accent : scheme.secondary,
                                fontFeatures: const [FontFeature.tabularFigures()],
                              ),
                            ),
                ),
              ),
              const SizedBox(width: 8),

              // Kolom tengah: Judul lagu, artis, dan progress download jika sedang mengunduh
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: MoriText.tileSize,
                        fontWeight: FontWeight.w700,
                        letterSpacing: MoriText.tileLetterSpacing,
                        color: isSelected ? scheme.accent : scheme.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: scheme.secondary,
                      ),
                    ),
                    if (item.status == BatchItemStatus.downloading &&
                        item.progress >= 0) ...[
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(MoriRadius.pill),
                        child: LinearProgressIndicator(
                          value: item.progress.clamp(0.0, 1.0),
                          minHeight: 3,
                          backgroundColor: scheme.surfaceVariant,
                          valueColor: AlwaysStoppedAnimation<Color>(scheme.accent),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // Kolom kanan: Aksi unduh 1 lagu / status unduhan
              _buildDownloadAction(scheme),
            ],
          ),
        ),
      ),
    );
  }

  String _statusText() {
    switch (item.status) {
      case BatchItemStatus.queued:
        return item.error ?? '';
      case BatchItemStatus.downloading:
        return 'Mengunduh…';
      case BatchItemStatus.done:
        return '';
      case BatchItemStatus.failed:
        return item.error ?? 'Gagal';
    }
  }

  Widget _buildDownloadAction(MoriScheme scheme) {
    final downloadCallback = onDownload ?? onTap;
    switch (item.status) {
      case BatchItemStatus.queued:
        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: downloadCallback,
            child: Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: scheme.surfaceVariant,
                shape: BoxShape.circle,
                border: Border.all(color: scheme.hairline),
              ),
              child: Icon(
                Icons.arrow_downward_rounded,
                size: 18,
                color: scheme.ink,
              ),
            ),
          ),
        );
      case BatchItemStatus.downloading:
        return SizedBox(
          width: 28,
          height: 28,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                value: item.progress > 0 ? item.progress.clamp(0.0, 1.0) : null,
                strokeWidth: 2.5,
                color: scheme.accent,
                backgroundColor: scheme.surfaceVariant,
              ),
              if (item.progress > 0)
                Text(
                  '${(item.progress * 100).toInt()}%',
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    color: scheme.accent,
                  ),
                ),
            ],
          ),
        );
      case BatchItemStatus.done:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: scheme.success.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_rounded, size: 16, color: scheme.success),
              const SizedBox(width: 4),
              Text(
                'Tersimpan',
                style: TextStyle(
                  fontFamily: 'Geist',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: scheme.success,
                ),
              ),
            ],
          ),
        );
      case BatchItemStatus.failed:
        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: downloadCallback,
            child: Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: scheme.error.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.refresh_rounded,
                size: 18,
                color: scheme.error,
              ),
            ),
          ),
        );
    }
  }
}
