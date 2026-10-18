import 'package:flutter/material.dart';
import '../../core/theme/design_tokens.dart';
import '../home/home_page.dart';
import '../history/history_page.dart';
import '../settings/settings_page.dart';
import '../home/widgets/liquid_glass_nav_bar.dart';

const _navItems = [
  NavItem(icon: Icons.home_rounded, label: 'Beranda'),
  NavItem(icon: Icons.history_rounded, label: 'Riwayat'),
  NavItem(icon: Icons.settings_rounded, label: 'Pengaturan'),
];

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _currentIndex = 0;
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onTabChanged(int index) {
    if (_currentIndex == index) return;
    setState(() => _currentIndex = index);
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = MoriScheme.of(context);
    return Scaffold(
      backgroundColor: scheme.background,
      extendBody: true,
      // Bar glass ditaruh DI ATAS body (Stack), bukan di bawahnya, karena
      // liquid glass hanya merefraksi konten yang ada di belakangnya.
      body: Stack(
        children: [
          // PageView dengan swipe horizontal yang terhubung langsung ke navbar
          PageView(
            controller: _pageController,
            onPageChanged: (index) {
              setState(() => _currentIndex = index);
            },
            physics: const BouncingScrollPhysics(),
            children: const [
              SafeArea(bottom: false, child: _NavInset(child: HomePage())),
              SafeArea(bottom: false, child: _NavInset(child: HistoryPage())),
              SafeArea(bottom: false, child: _NavInset(child: SettingsPage())),
            ],
          ),

          // Floating Liquid Glass Bottom Navigation Bar
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: LiquidGlassNavBar(
              items: _navItems,
              currentIndex: _currentIndex,
              pageController: _pageController,
              onTap: _onTabChanged,
            ),
          ),
        ],
      ),
    );
  }
}

/// Memberi tahu halaman bahwa bagian bawah layar dipakai bar glass, lewat
/// `MediaQuery.padding.bottom`. ListView, GridView, dan SafeArea di dalam
/// halaman otomatis menambah ruang bawah, jadi konten bisa di-scroll sampai
/// lewat bar (dan terlihat membias di bawah kaca) tanpa item terakhir
/// tertutup.
///
/// Kalau sebuah halaman memakai `padding:` sendiri pada scrollable-nya,
/// tambahkan `MediaQuery.paddingOf(context).bottom` ke padding bawahnya.
class _NavInset extends StatelessWidget {
  const _NavInset({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return MediaQuery(
      data: mq.copyWith(
        padding: mq.padding.copyWith(
          bottom: LiquidGlassNavBar.reservedHeight(context),
        ),
      ),
      child: child,
    );
  }
}