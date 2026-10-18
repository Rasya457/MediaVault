import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/design_tokens.dart';

class NavItem {
  const NavItem({required this.icon, required this.label});
  final IconData icon;
  final String label;
}

/// Floating capsule navigation bar frosted glass "Kaca Pagi":
/// - Kapsul mengambang dengan backdrop blur tajam & transparan
/// - Tab aktif punya capsule tersendiri dengan highlight tipis (specular rim)
/// - Aksen Harbor Blue untuk tab aktif, Harbor Slate untuk nonaktif
/// - Transisi warna, regangan elastis saat drag, scale ringan tanpa glow
/// - Responsif (HP kecil/besar/tablet) dengan target sentuh >=44x44 px
class LiquidGlassNavBar extends StatefulWidget {
  const LiquidGlassNavBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
    this.pageController,
    this.blur = 25.0,
  });

  final List<NavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;
  final PageController? pageController;

  /// Gaussian blur sigma untuk efek frosted glass.
  final double blur;

  /// Cadangan tinggi di bawah layar (tinggi bar 62 + margin bawah + clearance)
  static double reservedHeight(BuildContext context) {
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    final bottomMargin = bottomPadding > 0 ? bottomPadding + 6 : 14.0;
    return 62.0 + bottomMargin + 12.0;
  }

  @override
  State<LiquidGlassNavBar> createState() => _LiquidGlassNavBarState();
}

class _LiquidGlassNavBarState extends State<LiquidGlassNavBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;
  double _currentPos = 0.0;
  bool _isDragging = false;
  int _lastHapticIndex = 0;

  @override
  void initState() {
    super.initState();
    _currentPos = widget.currentIndex.toDouble();
    _lastHapticIndex = widget.currentIndex;

    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _anim = Tween<double>(begin: _currentPos, end: _currentPos).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic),
    );

    widget.pageController?.addListener(_onPageScroll);
  }

  @override
  void didUpdateWidget(LiquidGlassNavBar old) {
    super.didUpdateWidget(old);
    if (old.pageController != widget.pageController) {
      old.pageController?.removeListener(_onPageScroll);
      widget.pageController?.addListener(_onPageScroll);
    }
    if (old.currentIndex != widget.currentIndex && !_isDragging) {
      _animateTo(widget.currentIndex.toDouble());
    }
  }

  void _onPageScroll() {
    if (_isDragging) return;
    final page = widget.pageController?.page;
    if (page != null) {
      final nearest = page.round();
      if (nearest != _lastHapticIndex) {
        _lastHapticIndex = nearest;
        HapticFeedback.selectionClick();
      }
      setState(() {
        _currentPos = page;
        _anim = AlwaysStoppedAnimation<double>(page);
      });
    }
  }

  void _animateTo(double target) {
    final start = _anim.value;
    _anim = Tween<double>(begin: start, end: target).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic),
    );
    _currentPos = target;
    _lastHapticIndex = target.round();
    _ctrl
      ..reset()
      ..forward();
  }

  @override
  void dispose() {
    widget.pageController?.removeListener(_onPageScroll);
    _ctrl.dispose();
    super.dispose();
  }

  void _handleDragStart(DragStartDetails details) {
    if (widget.items.isEmpty) return;
    _ctrl.stop();
    setState(() => _isDragging = true);
    HapticFeedback.selectionClick();
  }

  void _handleDragUpdate(DragUpdateDetails details, double totalWidth) {
    if (widget.items.isEmpty || totalWidth <= 0) return;
    final itemW = totalWidth / widget.items.length;
    final delta = details.primaryDelta ?? 0.0;
    final maxIdx = (widget.items.length - 1).toDouble();
    final nextVal = (_currentPos + (delta / itemW)).clamp(0.0, maxIdx);

    final nearest = nextVal.round();
    if (nearest != _lastHapticIndex) {
      _lastHapticIndex = nearest;
      HapticFeedback.selectionClick();
    }

    setState(() {
      _currentPos = nextVal;
      _anim = AlwaysStoppedAnimation<double>(nextVal);
    });

    if (widget.pageController != null && widget.pageController!.hasClients) {
      widget.pageController!.jumpTo(
        nextVal * widget.pageController!.position.viewportDimension,
      );
    }
  }

  void _handleDragEnd(DragEndDetails details) {
    if (widget.items.isEmpty) return;
    _isDragging = false;
    final maxIdx = widget.items.length - 1;
    final nearest = _currentPos.round().clamp(0, maxIdx);

    _animateTo(nearest.toDouble());
    widget.onTap(nearest);
  }

  void _handleItemTap(int index) {
    HapticFeedback.selectionClick();
    _animateTo(index.toDouble());
    widget.onTap(index);
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final bottomPadding = mq.padding.bottom;
    final bottomMargin = bottomPadding > 0 ? bottomPadding + 6 : 14.0;
    // Warna kaca & tab mengikuti tema (light/dark), bukan hardcode.
    final scheme = MoriScheme.of(context);

    // Lebar fleksibel & adaptif: max 400px pada layar besar/tablet, margin 18px pada ponsel
    final screenWidth = mq.size.width;
    final barMaxWidth = math.min(screenWidth - 36.0, 400.0);

    return Padding(
      padding: EdgeInsets.only(
        left: 18.0,
        right: 18.0,
        bottom: bottomMargin,
      ),
      child: Center(
        heightFactor: 1.0,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: barMaxWidth),
          child: Container(
            height: 62.0,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(31.0),
              boxShadow: const [
                // Bayangan lembut bertingkat, tint ink (Tinted Shadow Rule)
                BoxShadow(
                  color: Color(0x1F202B36),
                  blurRadius: 28,
                  offset: Offset(0, 10),
                ),
                BoxShadow(
                  color: Color(0x0C202B36),
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(31.0),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(
                  sigmaX: widget.blur,
                  sigmaY: widget.blur,
                ),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(31.0),
                    // Gradasi kaca dari scheme (putih di light, slate di dark)
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        scheme.navGlassTop,
                        scheme.navGlassBottom,
                      ],
                    ),
                    border: Border.all(
                      color: scheme.navGlassBorder,
                      width: 1.0,
                    ),
                  ),
                  child: Stack(
                    children: [
                      // Highlight tipis di tepi atas (specular reflection kaca)
                      Positioned(
                        top: 0,
                        left: 20,
                        right: 20,
                        height: 1.0,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.white.withValues(alpha: 0.0),
                                Colors.white.withValues(alpha: 0.95),
                                Colors.white.withValues(alpha: 0.0),
                              ],
                            ),
                          ),
                        ),
                      ),

                      // Konten tab & moving capsule
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6.0,
                          vertical: 8.0,
                        ),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final contentWidth = constraints.maxWidth;
                            final n = widget.items.length;
                            final itemW = n > 0 ? contentWidth / n : 0.0;
                            const innerHeight = 46.0;

                            return GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onHorizontalDragStart: _handleDragStart,
                              onHorizontalDragUpdate: (d) =>
                                  _handleDragUpdate(d, contentWidth),
                              onHorizontalDragEnd: _handleDragEnd,
                              onTapUp: (details) {
                                if (itemW <= 0) return;
                                final tappedIdx =
                                    (details.localPosition.dx / itemW)
                                        .floor()
                                        .clamp(0, n - 1);
                                _handleItemTap(tappedIdx);
                              },
                              child: SizedBox(
                                height: innerHeight,
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    // 1. Moving capsule tab aktif
                                    if (n > 0)
                                      AnimatedBuilder(
                                        animation: _anim,
                                        builder: (context, _) {
                                          final pos = _anim.value;

                                          // Regangan dinamis halus saat bergerak antar-tab
                                          final frac = (pos - pos.floor()).abs();
                                          final stretchFactor =
                                              math.sin(frac * math.pi);

                                          final baseWidth = (itemW - 6.0)
                                              .clamp(36.0, itemW);
                                          final elongation =
                                              (itemW * 0.50) * stretchFactor;
                                          final pillWidth =
                                              baseWidth + elongation;

                                          final baseLeft = pos * itemW + 3.0;
                                          final pillLeft =
                                              baseLeft - (elongation / 2.0);

                                          return Positioned(
                                            left: pillLeft,
                                            top: 0.0,
                                            width: pillWidth,
                                            height: innerHeight,
                                            child: Container(
                                              decoration: BoxDecoration(
                                                borderRadius:
                                                    BorderRadius.circular(23.0),
                                                // Capsule transparan dari scheme
                                                gradient: LinearGradient(
                                                  begin: Alignment.topCenter,
                                                  end: Alignment.bottomCenter,
                                                  colors: [
                                                    scheme.navPillTop,
                                                    scheme.navPillBottom,
                                                  ],
                                                ),
                                                border: Border.all(
                                                  color:
                                                      scheme.navPillBorder,
                                                  width: 1.2,
                                                ),
                                                boxShadow: const [
                                                  // Tint ink, bukan halo berwarna
                                                  BoxShadow(
                                                    color: Color(0x18202B36),
                                                    blurRadius: 10,
                                                    offset: Offset(0, 2),
                                                  ),
                                                  BoxShadow(
                                                    color: Color(0x0F202B36),
                                                    blurRadius: 4,
                                                    offset: Offset(0, 1),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          );
                                        },
                                      ),

                                    // 2. Tab Items Row (Ikon + Label)
                                    SizedBox(
                                      height: innerHeight,
                                      child: Row(
                                        children: [
                                          for (int i = 0; i < n; i++)
                                            Expanded(
                                              child: AnimatedBuilder(
                                                animation: _anim,
                                                builder: (context, _) {
                                                  final pos = _anim.value;
                                                  final dist = (pos - i)
                                                      .abs()
                                                      .clamp(0.0, 1.0);
                                                  final isSelected =
                                                      dist < 0.45;

                                                  final activeProgress =
                                                      (1.0 - dist).clamp(0.0, 1.0);
                                                  final color = Color.lerp(
                                                    scheme.secondary,
                                                    scheme.accent,
                                                    activeProgress,
                                                  )!;

                                                  // Skala ringan saat tab aktif
                                                  final scale = 1.0 +
                                                      (0.04 * activeProgress);

                                                  return Transform.scale(
                                                    scale: scale,
                                                    child: _NavBarItemTile(
                                                      item: widget.items[i],
                                                      isSelected: isSelected,
                                                      color: color,
                                                      onTap: () =>
                                                          _handleItemTap(i),
                                                    ),
                                                  );
                                                },
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavBarItemTile extends StatelessWidget {
  const _NavBarItemTile({
    required this.item,
    required this.isSelected,
    required this.color,
    required this.onTap,
  });

  final NavItem item;
  final bool isSelected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              item.icon,
              size: 21.0,
              color: color,
            ),
            const SizedBox(height: 3.0),
            Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Geist',
                fontSize: 10.5,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                letterSpacing: MoriText.navLetterSpacing,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
