import 'package:flutter/material.dart';
import '../../core/theme/design_tokens.dart';
import '../history/history_repository.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _autoClipboard = true;
  bool _notifyOnFinish = true;
  String _preferredQuality = 'HD (Best)';

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
            padding: const EdgeInsets.fromLTRB(
              MoriSpacing.pagePad,
              MoriSpacing.titleTop,
              MoriSpacing.pagePad,
              160,
            ),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                Text(
                  'PENGATURAN',
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
                const SizedBox(height: 32),

                _buildSectionHeader(scheme, 'PREFERENSI'),
                const SizedBox(height: 10),
                _buildCard(scheme, [
                  _buildSwitchTile(
                    scheme: scheme,
                    title: 'Auto-detect Clipboard',
                    subtitle: 'Otomatis isi link yang disalin saat membuka aplikasi',
                    icon: Icons.content_paste_go_rounded,
                    value: _autoClipboard,
                    onChanged: (v) => setState(() => _autoClipboard = v),
                  ),
                  _buildDivider(scheme),
                  _buildSwitchTile(
                    scheme: scheme,
                    title: 'Notifikasi Unduhan',
                    subtitle: 'Beri tahu saat unduhan media atau audio selesai',
                    icon: Icons.notifications_active_outlined,
                    value: _notifyOnFinish,
                    onChanged: (v) => setState(() => _notifyOnFinish = v),
                  ),
                ]),

                const SizedBox(height: 24),
                _buildSectionHeader(scheme, 'KUALITAS & FORMAT'),
                const SizedBox(height: 10),
                _buildCard(scheme, [
                  _buildQualitySelectorTile(scheme),
                  _buildDivider(scheme),
                  _buildInfoTile(
                    scheme: scheme,
                    icon: Icons.audio_file_outlined,
                    title: 'Audio Extractor',
                    subtitle: 'FFmpeg on-device MP3 320kbps',
                  ),
                ]),

                const SizedBox(height: 24),
                _buildSectionHeader(scheme, 'PENYIMPANAN & CACHE'),
                const SizedBox(height: 10),
                _buildCard(scheme, [
                  _buildInfoTile(
                    scheme: scheme,
                    icon: Icons.folder_outlined,
                    title: 'Folder Penyimpanan',
                    subtitle: 'Galeri/MediaVault & Music/MediaVault',
                  ),
                  _buildDivider(scheme),
                  _buildActionTile(
                    scheme: scheme,
                    icon: Icons.delete_outline_rounded,
                    title: 'Hapus Semua Riwayat Unduhan',
                    subtitle: 'Bersihkan catatan riwayat lokal',
                    color: scheme.error,
                    onTap: _clearHistoryDialog,
                  ),
                ]),

                const SizedBox(height: 24),
                _buildSectionHeader(scheme, 'TENTANG'),
                const SizedBox(height: 10),
                _buildCard(scheme, [
                  _buildInfoTile(
                    scheme: scheme,
                    icon: Icons.info_outline_rounded,
                    title: 'MediaVault',
                    subtitle: 'v4.5.0 · Client-side Private Downloader',
                  ),
                  _buildDivider(scheme),
                  _buildInfoTile(
                    scheme: scheme,
                    icon: Icons.verified_user_outlined,
                    title: 'Engine & Scrapers',
                    subtitle: '16 Platform Support · No External Tracking',
                  ),
                ]),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(MoriScheme scheme, String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Geist',
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: scheme.secondary,
        ),
      ),
    );
  }

  Widget _buildCard(MoriScheme scheme, List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(MoriRadius.tile),
        border: Border.all(
          color: scheme.hairline,
          width: 1.0,
        ),
      ),
      child: Column(children: children),
    );
  }

  Widget _buildDivider(MoriScheme scheme) {
    return Divider(
      height: 1,
      thickness: 1,
      color: scheme.hairline,
    );
  }

  Widget _buildSwitchTile({
    required MoriScheme scheme,
    required String title,
    required String subtitle,
    required IconData icon,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(icon, color: scheme.secondary, size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: 'Geist',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: scheme.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontFamily: 'Geist',
                    fontSize: 12,
                    color: scheme.secondary,
                  ),
                ),
              ],
            ),
          ),
          // Warna switch datang dari SwitchTheme (AppTheme), dark-aware.
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildQualitySelectorTile(MoriScheme scheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(Icons.high_quality_outlined, color: scheme.secondary, size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              'Kualitas Utama',
              style: TextStyle(
                fontFamily: 'Geist',
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: scheme.ink,
              ),
            ),
          ),
          DropdownButton<String>(
            value: _preferredQuality,
            dropdownColor: scheme.surface,
            underline: const SizedBox.shrink(),
            icon: Icon(Icons.arrow_drop_down, color: scheme.secondary),
            style: TextStyle(
              fontFamily: 'Geist',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: scheme.ink,
            ),
            items: ['HD (Best)', 'Audio MP3 Only', 'Tanyakan Selalu']
                .map((q) => DropdownMenuItem(value: q, child: Text(q)))
                .toList(),
            onChanged: (v) {
              if (v != null) setState(() => _preferredQuality = v);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildInfoTile({
    required MoriScheme scheme,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Icon(icon, color: scheme.secondary, size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: 'Geist',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: scheme.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontFamily: 'Geist',
                    fontSize: 12,
                    color: scheme.secondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionTile({
    required MoriScheme scheme,
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(MoriRadius.tile),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: 'Geist',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontFamily: 'Geist',
                      fontSize: 12,
                      color: scheme.secondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: scheme.faint, size: 20),
          ],
        ),
      ),
    );
  }

  void _clearHistoryDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        // BG & teks dialog mengikuti dialogTheme (dark-aware).
        title: const Text(
          'Hapus Semua Riwayat?',
          style: TextStyle(
            fontFamily: 'Geist',
            fontWeight: FontWeight.w700,
          ),
        ),
        content: const Text(
          'Tindakan ini akan membersihkan semua riwayat unduhan di aplikasi. '
          'File yang sudah tersimpan di galeri tidak akan terhapus.',
          style: TextStyle(
            fontFamily: 'Geist',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: MoriScheme.of(ctx).error,
            ),
            onPressed: () async {
              Navigator.of(ctx).pop();
              await HistoryRepository.instance.clearAll();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Semua riwayat unduhan telah dibersihkan'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
  }
}
