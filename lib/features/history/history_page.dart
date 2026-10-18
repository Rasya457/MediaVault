import 'package:flutter/material.dart';
import '../../core/theme/design_tokens.dart';
import 'history_repository.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<DownloadHistoryEntry> _entries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entries = await HistoryRepository.instance.loadAll();
    if (mounted) setState(() { _entries = entries; _loading = false; });
  }

  Future<void> _delete(DownloadHistoryEntry e) async {
    await HistoryRepository.instance.remove(e.id);
    setState(() => _entries.remove(e));
  }

  /// Hapus semua dengan konfirmasi — aksi destruktif masif dijaga dialog,
  /// sejalan dengan tombol yang sama di halaman Pengaturan.
  Future<void> _clearAllWithConfirm() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Semua Riwayat?'),
        content: const Text(
          'Tindakan ini akan membersihkan semua riwayat unduhan di aplikasi. '
          'File yang sudah tersimpan di galeri tidak akan terhapus.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: MoriScheme.of(ctx).error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      // Ambil messenger sebelum await supaya context tidak dipakai di
      // seberang async gap.
      final messenger = ScaffoldMessenger.of(context);
      await HistoryRepository.instance.clearAll();
      if (!mounted) return;
      setState(() => _entries.clear());
      messenger.showSnackBar(
        const SnackBar(content: Text('Semua riwayat unduhan telah dibersihkan')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = MoriScheme.of(context);
    return Scaffold(
      backgroundColor: scheme.background,
      body: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              MoriSpacing.pagePad,
              MoriSpacing.titleTop,
              MoriSpacing.pagePad,
              160,
            ),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Spacer(),
                    Text(
                      'RIWAYAT',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Geist',
                        fontSize: MoriText.titleSize,
                        fontWeight: FontWeight.w800,
                        letterSpacing: MoriText.titleLetterSpacing,
                        color: scheme.ink,
                        height: 1.0,
                      ),
                    ),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: _entries.isNotEmpty
                            ? IconButton(
                                icon: Icon(
                                  Icons.delete_sweep_rounded,
                                  color: scheme.secondary,
                                  size: 22,
                                ),
                                tooltip: 'Hapus Semua',
                                onPressed: _clearAllWithConfirm,
                              )
                            : const SizedBox.shrink(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                if (_loading)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(40),
                      child: CircularProgressIndicator(
                        color: scheme.accent,
                        strokeWidth: 2.5,
                      ),
                    ),
                  )
                else if (_entries.isEmpty)
                  _buildEmpty(scheme)
                else
                  ..._entries
                      .map((e) => _HistoryTile(entry: e, onDelete: () => _delete(e))),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(MoriScheme scheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 64),
      child: Column(
        children: [
          Icon(
            Icons.download_done_rounded,
            size: 56,
            color: scheme.faint.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'Belum ada download',
            style: TextStyle(
              fontFamily: 'Geist',
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: scheme.secondary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Download pertamamu akan muncul di sini',
            style: TextStyle(
              fontFamily: 'Geist',
              fontSize: 13,
              color: scheme.secondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.entry, required this.onDelete});
  final DownloadHistoryEntry entry;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = MoriScheme.of(context);
    return Dismissible(
      key: ValueKey(entry.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDelete(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: scheme.error.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(MoriRadius.tile),
        ),
        child: Icon(Icons.delete_rounded, color: scheme.error, size: 22),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(MoriRadius.tile),
          border: Border.all(
            color: scheme.hairline,
            width: 1.0,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              // Thumbnail atau kind badge
              if (entry.thumbnail != null && entry.thumbnail!.startsWith('http'))
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    entry.thumbnail!,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => _kindBadge(scheme),
                  ),
                )
              else
                _kindBadge(scheme),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Geist',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: scheme.ink,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${entry.platform.toUpperCase()} · ${entry.quality}',
                      style: TextStyle(
                        fontFamily: 'Geist',
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: scheme.secondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _formatTime(entry.timestamp),
                      style: TextStyle(
                        fontFamily: 'Geist',
                        fontSize: 11,
                        color: scheme.faint,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Badge tipe: netral — metadata, bukan aksen.
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: scheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(MoriRadius.pill),
                ),
                child: Text(
                  entry.kindLabel,
                  style: TextStyle(
                    fontFamily: 'Geist',
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: scheme.secondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _kindBadge(MoriScheme scheme) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: scheme.surfaceVariant,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(
        _kindIcon(),
        color: scheme.secondary,
        size: 22,
      ),
    );
  }

  IconData _kindIcon() {
    switch (entry.extension.toLowerCase()) {
      case 'mp3':
      case 'm4a':
        return Icons.music_note_rounded;
      case 'mp4':
      case 'mov':
        return Icons.videocam_rounded;
      default:
        return Icons.image_rounded;
    }
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Baru saja';
    if (diff.inHours < 1) return '${diff.inMinutes} menit lalu';
    if (diff.inDays < 1) return '${diff.inHours} jam lalu';
    if (diff.inDays < 7) return '${diff.inDays} hari lalu';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}
