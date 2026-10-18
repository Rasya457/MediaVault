import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/design_tokens.dart';
import '../../services/providers/models.dart';
import '../../services/providers/provider.dart';
import '../../services/providers/registry.dart';
import '../preview/preview_page.dart';
import 'platform_item.dart';

/// Callback opsional untuk test / parent widget.
typedef OnAnalyze = void Function(String url, PlatformItem? platform);

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.onAnalyze, this.onDownloadTap});

  final OnAnalyze? onAnalyze;
  final VoidCallback? onDownloadTap;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _multiLine = false;
  bool _loading = false;
  String? _lastCheckedClipboard;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkClipboardAuto());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _checkClipboardAuto();
    }
  }

  /// Auto-check clipboard saat app dibuka atau resumed.
  Future<void> _checkClipboardAuto() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';

    // Skip jika kosong, sama dengan yang terakhir dicek, atau sudah ada di field
    if (text.isEmpty || text == _lastCheckedClipboard || text == _controller.text) {
      return;
    }

    _lastCheckedClipboard = text;

    // Cek apakah ini URL yang valid
    final uri = Uri.tryParse(text);
    final isValidUrl = uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;

    if (!isValidUrl) return;

    // Cek apakah platform supported
    final platform = detectPlatform(text);
    if (platform == null) return;

    // Tanya user apakah mau paste
    if (!mounted) return;

    final scheme = MoriScheme.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.link, color: Color(0xFFFFFFFF), size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Tautan dari clipboard terdeteksi',
                style: TextStyle(
                  fontFamily: 'Geist',
                  color: scheme.onInverseSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: scheme.inverseSurface,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 90),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'TEMPEL',
          textColor: scheme.onInverseSurface,
          onPressed: () {
            _controller.text = text;
            _controller.selection = TextSelection.collapsed(offset: text.length);
          },
        ),
      ),
    );
  }

  /// Membaca clipboard dan menaruh cursor di akhir teks.
  void _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text ?? '';
    if (text.isNotEmpty) {
      _controller.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
  }

  /// Validasi → detect platform → langsung fetchInfo → buka PreviewPage.
  void _analyze() async {
    if (_loading) return;

    final raw = _controller.text.trim();
    if (raw.isEmpty) return;

    // Validasi format URL dasar
    final uri = Uri.tryParse(raw);
    final valid = uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;

    if (!valid) {
      _showErrorSnackBar('URL tidak valid. Pastikan diawali https://');
      return;
    }

    // Dismiss keyboard
    FocusScope.of(context).unfocus();

    final platform = detectPlatform(raw);

    // Kalau ada onAnalyze (untuk test/debug), panggil duluan
    widget.onAnalyze?.call(raw, platform);

    setState(() => _loading = true);

    try {
      final MediaInfo info = await ProviderRegistry.instance.fetchInfo(raw);

      if (!mounted) return;

      // Langsung buka PreviewPage tanpa user perlu pilih apapun
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PreviewPage(info: info, sourceUrl: raw),
          fullscreenDialog: true,
        ),
      );
    } on ProviderException catch (e) {
      if (!mounted) return;
      _showErrorSnackBar(e.message);
    } catch (e) {
      if (!mounted) return;
      _showErrorSnackBar('Terjadi kesalahan. Periksa koneksi dan coba lagi.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showErrorSnackBar(String message) {
    final scheme = MoriScheme.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(
            fontFamily: 'Geist',
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        // Error pakai Brick Signal (warna semantik gagal), bukan pill netral.
        backgroundColor: scheme.error,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MoriRadius.button),
        ),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 90),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = MoriScheme.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusScope.of(context).unfocus(),
      child: CustomScrollView(
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
                _buildTitle(scheme),
                const SizedBox(height: MoriSpacing.afterTitle),
                _buildLinkField(scheme),
                const SizedBox(height: MoriSpacing.afterField),
                _buildAnalyzeButton(scheme),
                const SizedBox(height: MoriSpacing.afterBtn),
                _buildSectionLabel(scheme),
                const SizedBox(height: MoriSpacing.afterLabel),
                _buildPlatformGrid(scheme),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTitle(MoriScheme scheme) {
    return Column(
      children: [
        Text(
          'MORI',
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
        const SizedBox(height: 6),
        Text(
          'Unduh media dari semua platform',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Geist',
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: scheme.secondary,
            letterSpacing: 0.1,
          ),
        ),
      ],
    );
  }

  Widget _buildLinkField(MoriScheme scheme) {
    return SizedBox(
      height: _multiLine ? null : 50,
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        maxLines: _multiLine ? 5 : 1,
        minLines: 1,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _analyze(),
        enabled: !_loading,
        style: TextStyle(
          fontFamily: 'Geist',
          fontSize: MoriText.fieldSize,
          color: scheme.ink,
        ),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Tempel link di sini...',
          hintStyle: TextStyle(
            fontFamily: 'Geist',
            fontSize: MoriText.fieldSize,
            color: scheme.secondary,
          ),
          filled: true,
          fillColor: scheme.surface,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 14, right: 10),
            child: Icon(Icons.search, color: scheme.secondary, size: 24),
          ),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 48, minHeight: 48),
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(
                  Icons.format_list_bulleted,
                  color: _multiLine ? scheme.onAccent : scheme.secondary,
                  size: 24,
                ),
                tooltip: 'Mode banyak link',
                style: _multiLine
                    ? IconButton.styleFrom(
                        backgroundColor: scheme.accentFill,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      )
                    : null,
                onPressed:
                    _loading ? null : () => setState(() => _multiLine = !_multiLine),
              ),
              IconButton(
                icon: Icon(Icons.content_paste, color: scheme.secondary, size: 24),
                tooltip: 'Tempel dari clipboard',
                onPressed: _loading ? null : _paste,
              ),
              const SizedBox(width: 4),
            ],
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(MoriRadius.field),
            borderSide: BorderSide(
              color: scheme.hairline,
              width: MoriBorder.field,
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(MoriRadius.field),
            borderSide: BorderSide(
              color: scheme.hairline,
              width: MoriBorder.field,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(MoriRadius.field),
            borderSide: BorderSide(
              color: scheme.accent,
              width: MoriBorder.selected,
            ),
          ),
          disabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(MoriRadius.field),
            borderSide: BorderSide(
              color: scheme.hairline.withValues(alpha: 0.6),
              width: MoriBorder.field,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAnalyzeButton(MoriScheme scheme) {
    return Container(
      width: double.infinity,
      height: 50,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(MoriRadius.button),
        boxShadow: _loading ? null : MoriShadow.button,
      ),
      child: FilledButton(
        onPressed: _loading ? null : _analyze,
        child: _loading
            ? SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: scheme.onAccent,
                ),
              )
            : Text(
                'ANALISIS',
                style: TextStyle(
                  fontFamily: 'Geist',
                  fontSize: MoriText.btnSize,
                  fontWeight: FontWeight.w700,
                  letterSpacing: MoriText.btnLetterSpacing,
                ),
              ),
      ),
    );
  }

  Widget _buildSectionLabel(MoriScheme scheme) {
    return Text(
      'PLATFORM DIDUKUNG',
      textAlign: TextAlign.center,
      style: TextStyle(
        fontFamily: 'Geist',
        fontSize: MoriText.labelSize,
        fontWeight: FontWeight.w700,
        letterSpacing: MoriText.labelLetterSpacing,
        color: scheme.secondary,
      ),
    );
  }

  Widget _buildPlatformGrid(MoriScheme scheme) {
    final rows = <Widget>[];
    for (var i = 0; i < kPlatforms.length; i += 2) {
      final a = kPlatforms[i];
      final b = (i + 1 < kPlatforms.length) ? kPlatforms[i + 1] : null;
      rows.add(
        IntrinsicHeight(
          child: Row(
            children: [
              Expanded(
                child: _PlatformTile(
                  platform: a,
                  scheme: scheme,
                ),
              ),
              const SizedBox(width: MoriSpacing.gridGap),
              Expanded(
                child: b != null
                    ? _PlatformTile(platform: b, scheme: scheme)
                    : const SizedBox(),
              ),
            ],
          ),
        ),
      );
      if (i + 2 < kPlatforms.length) {
        rows.add(const SizedBox(height: MoriSpacing.gridGap));
      }
    }
    return Column(children: rows);
  }
}

class _PlatformTile extends StatefulWidget {
  const _PlatformTile({required this.platform, required this.scheme});
  final PlatformItem platform;
  final MoriScheme scheme;

  @override
  State<_PlatformTile> createState() => _PlatformTileState();
}

class _PlatformTileState extends State<_PlatformTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final scheme = widget.scheme;
    final bgColor =
        _pressed ? scheme.accentTint : scheme.surface;
    final borderColor = _pressed ? scheme.accent : scheme.hairline;

    return GestureDetector(
      onTapDown: (_) {
        HapticFeedback.lightImpact();
        setState(() => _pressed = true);
      },
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          height: MoriSpacing.tileHeight,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: bgColor,
            border: Border.all(color: borderColor, width: MoriBorder.tile),
            borderRadius: BorderRadius.circular(MoriRadius.tile),
            boxShadow: MoriShadow.soft,
          ),
          child: Row(
            children: [
              const SizedBox(width: 16),
              // Ikon brand: warna asli platform (identifier, bukan dekorasi).
              widget.platform.iconBuilder(
                widget.platform.brand(scheme.brightness),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.platform.label,
                  style: TextStyle(
                    fontFamily: 'Geist',
                    fontSize: MoriText.tileSize,
                    fontWeight: FontWeight.w600,
                    letterSpacing: MoriText.tileLetterSpacing,
                    color: scheme.ink,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
