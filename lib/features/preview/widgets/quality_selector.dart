import 'package:flutter/material.dart';
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

class _QualityTile extends StatelessWidget {
  const _QualityTile({
    required this.quality,
    required this.selected,
    required this.onTap,
  });

  final MediaQuality quality;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = selected ? MoriColors.ink : MoriColors.surface;
    final fg = selected ? MoriColors.surface : MoriColors.ink;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: MoriColors.ink, width: 2),
          borderRadius: BorderRadius.circular(MoriRadius.button),
          boxShadow: selected
              ? null
              : const [
                  BoxShadow(
                    color: MoriColors.ink,
                    offset: Offset(2, 2),
                    blurRadius: 0,
                  ),
                ],
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: fg,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                quality.label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: fg,
                ),
              ),
            ),
            Text(
              '.${quality.extension}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: fg.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
