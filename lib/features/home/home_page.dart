import 'dart:io';
import 'package:flutter/foundation.dart';
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

class _HomePageState extends State<HomePage> {
  final _controller = TextEditingController();
  final _focusNode  = FocusNode();
  bool _multiLine   = false;
  bool _loading     = false;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(
            color: MoriColors.surface,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: MoriColors.ink,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  String? get _fontFamily => (!kIsWeb && Platform.isIOS) ? null : 'Inter';

  @override
  Widget build(BuildContext context) {
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
                _buildTitle(),
                const SizedBox(height: MoriSpacing.afterTitle),
                _buildLinkField(),
                const SizedBox(height: MoriSpacing.afterField),
                _buildAnalyzeButton(),
                const SizedBox(height: MoriSpacing.afterBtn),
                _buildSectionLabel(),
                const SizedBox(height: MoriSpacing.afterLabel),
                _buildPlatformGrid(),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTitle() {
    return Text(
      'MORI',
      textAlign: TextAlign.center,
      style: TextStyle(
        fontFamily: _fontFamily,
        fontSize: MoriText.titleSize,
        fontWeight: FontWeight.w800,
        letterSpacing: MoriText.titleLetterSpacing,
        color: MoriColors.ink,
        height: 1.0,
      ),
    );
  }

  Widget _buildLinkField() {
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
          fontFamily: _fontFamily,
          fontSize: MoriText.fieldSize,
          color: MoriColors.ink,
        ),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Paste link here...',
          hintStyle: TextStyle(
            fontFamily: _fontFamily,
            fontSize: MoriText.fieldSize,
            color: MoriColors.hint,
          ),
          filled: true,
          fillColor: MoriColors.surface,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          prefixIcon: const Padding(
            padding: EdgeInsets.only(left: 14, right: 10),
            child: Icon(Icons.search, color: MoriColors.ink, size: 24),
          ),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 48, minHeight: 48),
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(
                  Icons.format_list_bulleted,
                  color: _multiLine ? MoriColors.surface : MoriColors.ink,
                  size: 24,
                ),
                tooltip: 'Toggle multi-link',
                style: _multiLine
                    ? IconButton.styleFrom(
                        backgroundColor: MoriColors.ink,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      )
                    : null,
                onPressed:
                    _loading ? null : () => setState(() => _multiLine = !_multiLine),
              ),
              IconButton(
                icon:
                    const Icon(Icons.content_paste, color: MoriColors.ink, size: 24),
                tooltip: 'Paste from clipboard',
                onPressed: _loading ? null : _paste,
              ),
              const SizedBox(width: 4),
            ],
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(MoriRadius.field),
            borderSide:
                const BorderSide(color: MoriColors.ink, width: MoriBorder.field),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(MoriRadius.field),
            borderSide:
                const BorderSide(color: MoriColors.ink, width: MoriBorder.field),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(MoriRadius.field),
            borderSide: const BorderSide(
                color: MoriColors.activeBorder, width: MoriBorder.field),
          ),
          disabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(MoriRadius.field),
            borderSide: BorderSide(
                color: MoriColors.ink.withAlpha(100), width: MoriBorder.field),
          ),
        ),
      ),
    );
  }

  Widget _buildAnalyzeButton() {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: FilledButton(
        onPressed: _loading ? null : _analyze,
        style: FilledButton.styleFrom(
          backgroundColor: MoriColors.ink,
          foregroundColor: Colors.white,
          disabledBackgroundColor: MoriColors.hint,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(MoriRadius.button),
          ),
          elevation: 0,
          shadowColor: Colors.transparent,
        ),
        child: _loading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
            : Text(
                'ANALYZE',
                style: TextStyle(
                  fontFamily: _fontFamily,
                  fontSize: MoriText.btnSize,
                  fontWeight: FontWeight.w600,
                  letterSpacing: MoriText.btnLetterSpacing,
                ),
              ),
      ),
    );
  }

  Widget _buildSectionLabel() {
    return Text(
      'SUPPORTED PLATFORMS',
      textAlign: TextAlign.center,
      style: TextStyle(
        fontFamily: _fontFamily,
        fontSize: MoriText.labelSize,
        fontWeight: FontWeight.w700,
        letterSpacing: MoriText.labelLetterSpacing,
        color: MoriColors.label,
      ),
    );
  }

  Widget _buildPlatformGrid() {
    final rows = <Widget>[];
    for (var i = 0; i < kPlatforms.length; i += 2) {
      final a = kPlatforms[i];
      final b = (i + 1 < kPlatforms.length) ? kPlatforms[i + 1] : null;
      rows.add(
        IntrinsicHeight(
          child: Row(
            children: [
              Expanded(child: _PlatformTile(platform: a, fontFamily: _fontFamily)),
              const SizedBox(width: MoriSpacing.gridGap),
              Expanded(
                child: b != null
                    ? _PlatformTile(platform: b, fontFamily: _fontFamily)
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
  const _PlatformTile({required this.platform, this.fontFamily});
  final PlatformItem platform;
  final String? fontFamily;

  @override
  State<_PlatformTile> createState() => _PlatformTileState();
}

class _PlatformTileState extends State<_PlatformTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final bgColor = _pressed ? MoriColors.ink : MoriColors.surface;
    final fgColor = _pressed ? MoriColors.surface : MoriColors.ink;

    return GestureDetector(
      onTapDown:   (_) => setState(() => _pressed = true),
      onTapUp:     (_) => setState(() => _pressed = false),
      onTapCancel: ()  => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        height: MoriSpacing.tileHeight,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: bgColor,
          border: Border.all(color: MoriColors.ink, width: MoriBorder.tile),
          borderRadius: BorderRadius.circular(MoriRadius.tile),
        ),
        child: Row(
          children: [
            const SizedBox(width: 16),
            widget.platform.iconBuilder(fgColor),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                widget.platform.label,
                style: TextStyle(
                  fontFamily: widget.fontFamily,
                  fontSize: MoriText.tileSize,
                  fontWeight: FontWeight.w700,
                  letterSpacing: MoriText.tileLetterSpacing,
                  color: fgColor,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}