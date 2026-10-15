import 'package:flutter/material.dart';
import '../../core/theme/design_tokens.dart';
import '../home/home_page.dart';
import '../history/history_page.dart';
import '../settings/settings_page.dart';
import '../home/widgets/liquid_glass_nav_bar.dart';

const _navItems = [
  NavItem(icon: Icons.home_rounded,     label: 'HOME'),
  NavItem(icon: Icons.history_rounded,  label: 'HISTORY'),
  NavItem(icon: Icons.settings_rounded, label: 'SETTINGS'),
];

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final navHeight = 64.0 + mq.padding.bottom + 12.0;
    final fabBottom = navHeight + 12.0;

    return Scaffold(
      backgroundColor: MoriColors.background,
      extendBody: true,
      body: Stack(
        children: [
          // IndexedStack mempertahankan scroll position & state tiap tab
          IndexedStack(
            index: _currentIndex,
            children: const [
              // HomePage mengelola navigate ke PreviewPage secara mandiri
              SafeArea(bottom: false, child: HomePage()),
              SafeArea(bottom: false, child: HistoryPage()),
              SafeArea(bottom: false, child: SettingsPage()),
            ],
          ),

          // Floating Download Button
          Positioned(
            left: 16,
            bottom: fabBottom,
            child: _DownloadFab(
              onTap: () => debugPrint('Download FAB tapped'),
            ),
          ),

          // Liquid Glass Floating Bottom Navigation Bar
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: LiquidGlassNavBar(
              items: _navItems,
              currentIndex: _currentIndex,
              onTap: (i) => setState(() => _currentIndex = i),
            ),
          ),
        ],
      ),
    );
  }
}

/// Floating Download FAB — neo-brutalist circle with hard shadow offset (3,3).
class _DownloadFab extends StatelessWidget {
  const _DownloadFab({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: MoriColors.fabFill,
          border: Border.all(color: MoriColors.fabBorder, width: MoriBorder.fab),
          boxShadow: const [
            BoxShadow(
              color: Colors.black,
              offset: Offset(3, 3),
              blurRadius: 0,
            ),
          ],
        ),
        child: const Icon(
          Icons.cloud_download_outlined,
          color: MoriColors.ink,
          size: 26,
        ),
      ),
    );
  }
}