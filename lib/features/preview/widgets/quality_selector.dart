import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../services/providers/models.dart';

/// Daftar kualitas dari [MediaInfo.qualities]. Pilihan berupa itag.
class QualitySelector extends StatelessWidget {
  const QualitySelector({
    super.key,
    required this.qualities,
    required this.selectedItag,
    required this.onSelect,
  });

  final List<MediaQuality> qualities;
  final String selectedItag;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final q in qualities)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _QualityTile(
              quality: q,
              selected: q.itag == selectedItag,
              onTap: () => onSelect(q.itag),
            ),
          ),
      ],
    );
  }
}

class _QualityTile extends StatefulWidget {
  const _QualityTile({
    required this.quality,
    required this.selected,
    required this.onTap,
  });

  final MediaQuality quality;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_QualityTile> createState() => _QualityTileState();
}

class _QualityTileState extends State<_QualityTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final scheme = MoriScheme.of(context);
    final selected = widget.selected;
    // Seleksi: tint aksen + border aksen penuh (bukan biru Tailwind).
    final bg = selected ? scheme.accentTint : scheme.surface;
    final borderColor = selected ? scheme.accent : scheme.hairline;
    final borderWidth = selected ? MoriBorder.selected : MoriBorder.tile;
    final fg = scheme.ink;

    return GestureDetector(
      onTapDown: (_) {
        HapticFeedback.selectionClick();
        setState(() => _pressed = true);
      },
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: bg,
            border: Border.all(color: borderColor, width: borderWidth),
            // 12px: konsisten dengan skala tile lain (bukan pill).
            borderRadius: BorderRadius.circular(MoriRadius.tile),
            boxShadow: MoriShadow.soft,
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: selected
                    ? scheme.accent
                    : scheme.faint,
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.quality.label,
                      style: TextStyle(
                        fontFamily: 'Geist',
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        letterSpacing: MoriText.tileLetterSpacing,
                        color: fg,
                      ),
                    ),
                    if (widget.quality.sizeLabel != null ||
                        widget.quality.needsMerge)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          [
                            if (widget.quality.sizeLabel != null)
                              widget.quality.sizeLabel!,
                            if (widget.quality.needsMerge) 'PERLU GABUNG AUDIO',
                          ].join(' • '),
                          style: TextStyle(
                            fontFamily: 'Geist',
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: scheme.secondary,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Text(
                '.${widget.quality.extension}',
                style: TextStyle(
                  fontFamily: 'Geist',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.0,
                  color: scheme.secondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
