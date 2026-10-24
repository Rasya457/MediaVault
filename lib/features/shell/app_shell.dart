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

  double _dragStartX = 0;
  static const double _swipeThreshold = 60.0;

  void _onTabChanged(int index) {
    if (_currentIndex == index) return;
    setState(() => _currentIndex = index);
  }

  void _onDragStart(DragStartDetails d) {
    _dragStartX = d.globalPosition.dx;
  }

  void _onDragEnd(DragEndDetails d) {
    final dx = d.globalPosition.dx - _dragStartX;
    final velocity = d.velocity.pixelsPerSecond.dx;

    final swipeLeft = dx < -_swipeThreshold || velocity < -300;
    final swipeRight = dx > _swipeThreshold || velocity > 300;

    if (swipeLeft && _currentIndex < _navItems.length - 1) {
      _onTabChanged(_currentIndex + 1);
    } else if (swipeRight && _currentIndex > 0) {
      _onTabChanged(_currentIndex - 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = MoriScheme.of(context);
    return Scaffold(
      backgroundColor: scheme.background,
      extendBody: true,
      body: GestureDetector(
        onHorizontalDragStart: _onDragStart,
        onHorizontalDragEnd: _onDragEnd,
        behavior: HitTestBehavior.translucent,
        child: Stack(
          children: [
            IndexedStack(
              index: _currentIndex,
              children: const [
                SafeArea(bottom: false, child: _NavInset(child: HomePage())),
                SafeArea(bottom: false, child: _NavInset(child: HistoryPage())),
                SafeArea(bottom: false, child: _NavInset(child: SettingsPage())),
              ],
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: LiquidGlassNavBar(
                items: _navItems,
                currentIndex: _currentIndex,
                onTap: _onTabChanged,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Memberi tahu halaman bahwa bagian bawah layar dipakai bar glass, lewat
/// [MediaQuery.padding.bottom]. ListView, GridView, dan SafeArea di dalam
/// halaman otomatis menambah ruang bawah, jadi konten bisa di-scroll sampai
/// lewat bar tanpa item terakhir tertutup.
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
