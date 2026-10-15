import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/design_tokens.dart';

class NavItem {
  const NavItem({required this.icon, required this.label});
  final IconData icon;
  final String label;
}

/// Bottom navigation bar bergaya Liquid Glass — floating pill iOS 26 style.
///
/// Spesifikasi efek:
/// - Floating pill melayang (margin horizontal 20dp, margin bawah safe area + 12dp).
/// - Fallback manual glass: ClipRRect + BackdropFilter(ImageFilter.blur) +
///   fill putih semi-transparan (alpha 0.35-0.45) dengan gradient diagonal.
/// - Specular edge: border 1dp gradient putih alpha 0.8 di kiri-atas memudar ke 0.1 di kanan-bawah.
/// - Bayangan lembut ultra-halus di bawah pill untuk kedalaman visual.
/// - Lens indicator di belakang item aktif dengan animasi spring (350ms) + squash & stretch.
/// - Gesture drag horizontal interaktif dengan snap ke tab terdekat.
///
/// Trade-off performa:
/// BackdropFilter memerlukan rendering multi-pass pada GPU. Pada perangkat low-end (terutama
/// engine raster Skia non-Impeller), turunkan [blurSigma] (mis. 10–12) atau atur [enableBlur: false].
class LiquidGlassNavBar extends StatefulWidget {
  const LiquidGlassNavBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
    this.blurSigma = 24.0,
    this.enableBlur = true,
  });

  final List<NavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;
  final double blurSigma;
  final bool enableBlur;

  @override
  State<LiquidGlassNavBar> createState() => _LiquidGlassNavBarState();
}

class _LiquidGlassNavBarState extends State<LiquidGlassNavBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _indicatorPos;
  double _currentValue = 0.0;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _currentValue = widget.currentIndex.toDouble();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _indicatorPos = Tween<double>(
      begin: _currentValue,
      end: _currentValue,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut));
  }

  @override
  void didUpdateWidget(LiquidGlassNavBar old) {
    super.didUpdateWidget(old);
    if (old.currentIndex != widget.currentIndex && !_isDragging) {
      _animateTo(widget.currentIndex.toDouble());
    }
  }

  void _animateTo(double target) {
    final start = _indicatorPos.value;
    _indicatorPos = Tween<double>(
      begin: start,
      end: target,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut));
    _currentValue = target;
    _ctrl
      ..reset()
      ..forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _handleHorizontalDragUpdate(DragUpdateDetails details, double totalWidth) {
    if (widget.items.isEmpty) return;
    final itemW = totalWidth / widget.items.length;
    final delta = details.primaryDelta ?? 0;
    final maxIdx = (widget.items.length - 1).toDouble();
    final nextVal = (_indicatorPos.value + (delta / itemW)).clamp(0.0, maxIdx);

    setState(() {
      _isDragging = true;
      _indicatorPos = AlwaysStoppedAnimation<double>(nextVal);
      _currentValue = nextVal;
    });
  }

  void _handleHorizontalDragEnd(DragEndDetails details) {
    if (widget.items.isEmpty) return;
    _isDragging = false;
    final maxIdx = widget.items.length - 1;
    final nearest = _indicatorPos.value.round().clamp(0, maxIdx);

    _animateTo(nearest.toDouble());
    if (nearest != widget.currentIndex) {
      HapticFeedback.selectionClick();
      widget.onTap(nearest);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final bottomPad = mq.padding.bottom + 12.0;
    const pillHeight = 64.0;
    const hMargin = 20.0;

    return Padding(
      padding: EdgeInsets.fromLTRB(hMargin, 0, hMargin, bottomPad),
      child: RepaintBoundary(
        child: SizedBox(
          height: pillHeight,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final pillWidth = constraints.maxWidth;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragStart: (_) => _isDragging = true,
                onHorizontalDragUpdate: (d) =>
                    _handleHorizontalDragUpdate(d, pillWidth),
                onHorizontalDragEnd: _handleHorizontalDragEnd,
                child: _GlassPill(
                  blurSigma: widget.blurSigma,
                  enableBlur: widget.enableBlur,
                  child: Stack(
                    children: [
                      // Liquid lens indicator dengan squash & stretch saat gerak
                      AnimatedBuilder(
                        animation: _ctrl,
                        builder: (context, child) {
                          final n = widget.items.length;
                          final itemW = pillWidth / n;
                          final pos = _indicatorPos.value;
                          final left = pos * itemW;

                          // Squash-stretch elastis saat berpindah
                          final stretch = _ctrl.isAnimating
                              ? 1.0 + (math.sin(_ctrl.value * math.pi) * 0.15)
                              : 1.0;
                          final baseW = itemW - 8.0;
                          final stretchedW = baseW * stretch;
                          final offsetFix = (stretchedW - baseW) / 2.0;

                          return Positioned(
                            left: left + 4.0 - offsetFix,
                            top: 6.0,
                            width: stretchedW,
                            height: pillHeight - 12.0,
                            child: const _LensIndicator(),
                          );
                        },
                      ),
                      // Navigation Item Tiles
                      Row(
                        children: List.generate(widget.items.length, (i) {
                          final item = widget.items[i];
                          final isActive = widget.currentIndex == i;
                          return Expanded(
                            child: _NavItemTile(
                              item: item,
                              active: isActive,
                              onTap: () {
                                HapticFeedback.selectionClick();
                                widget.onTap(i);
                              },
                            ),
                          );
                        }),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Kontainer floating glass pill dengan efek blur & specular reflection edge.
class _GlassPill extends StatelessWidget {
  const _GlassPill({
    required this.child,
    required this.blurSigma,
    required this.enableBlur,
  });

  final Widget child;
  final double blurSigma;
  final bool enableBlur;

  @override
  Widget build(BuildContext context) {
    const pillRadius = 32.0;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(pillRadius),
        // Soft diffusion shadow di bawah pill untuk efek floating
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000), // ~8% opacity shadow
            blurRadius: 28,
            spreadRadius: 0,
            offset: Offset(0, 8),
          ),
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 8,
            spreadRadius: 0,
            offset: Offset(0, 2),
          ),
        ],
        // Specular edge: gradient putih alpha 0.8 (kiri-atas) memudar ke 0.1 (kanan-bawah)
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xCCFFFFFF), // alpha 0.8 specular highlight
            Color(0x1AFFFFFF), // alpha 0.1 specular edge
          ],
        ),
      ),
      padding: const EdgeInsets.all(MoriBorder.nav), // 1dp specular border
      child: ClipRRect(
        borderRadius: BorderRadius.circular(pillRadius - 1),
        child: enableBlur
            ? BackdropFilter(
                filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
                child: _buildTintedSurface(),
              )
            : _buildTintedSurface(),
      ),
    );
  }

  Widget _buildTintedSurface() {
    return Container(
      decoration: const BoxDecoration(
        // Fill putih alpha ~0.35-0.45 dengan highlight pantulan diagonal tipis
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0x73FFFFFF), // 45% white
            Color(0x59FFFFFF), // 35% white
          ],
        ),
      ),
      child: child,
    );
  }
}

/// Lensa glass pill yang lebih terang di belakang tab aktif.
class _LensIndicator extends StatelessWidget {
  const _LensIndicator();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        // Lensa glass lebih cerah dengan highlight refleksi
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0x8CFFFFFF), // ~55% white highlight
            Color(0x38FFFFFF), // ~22% white
          ],
        ),
        border: Border.all(
          color: const Color(0x66FFFFFF),
          width: 0.8,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x10000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
    );
  }
}

/// Satuan tile nav item dengan ikon & teks label uppercase.
class _NavItemTile extends StatelessWidget {
  const _NavItemTile({
    required this.item,
    required this.active,
    required this.onTap,
  });

  final NavItem item;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? MoriColors.ink : MoriColors.label;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(item.icon, color: color, size: 26),
          const SizedBox(height: 4),
          Text(
            item.label,
            style: TextStyle(
              color: color,
              fontSize: MoriText.navLabelSize,
              fontWeight: FontWeight.w700,
              letterSpacing: MoriText.navLetterSpacing,
            ),
          ),
        ],
      ),
    );
  }
}