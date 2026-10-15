import 'package:flutter/material.dart';

import '../../../core/theme/design_tokens.dart';

/// Bingkai bergaya neo-brutalist yang ukurannya mengikuti [aspectRatio]
/// (lebar / tinggi). Landscape melebar penuh, portrait menyempit supaya tinggi
/// tidak melebihi [maxHeight]. Karena kotaknya pas dengan isi, tidak ada
/// area kosong atau background hitam di sekeliling konten.
class PreviewFrame extends StatelessWidget {
  const PreviewFrame({
    super.key,
    required this.aspectRatio,
    required this.child,
    this.maxHeight = 440,
  });

  final double aspectRatio;
  final double maxHeight;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        var w = constraints.maxWidth;
        var h = w / aspectRatio;
        if (h > maxHeight) {
          h = maxHeight;
          w = h * aspectRatio;
        }
        return Center(
          child: Container(
            width: w,
            height: h,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: MoriColors.surface,
              border: Border.all(color: MoriColors.ink, width: 2),
              borderRadius: BorderRadius.circular(MoriRadius.button),
              boxShadow: const [
                BoxShadow(
                  color: MoriColors.ink,
                  offset: Offset(3, 3),
                  blurRadius: 0,
                ),
              ],
            ),
            child: child,
          ),
        );
      },
    );
  }
}

/// Gambar jaringan yang rasio aslinya dibaca dulu, lalu dibingkai pas
/// ([PreviewFrame]). [fallbackUrl] dipakai kalau [url] gagal dimuat.
/// [overlay] digambar di atas gambar (mis. penanda audio atau spinner),
/// dan juga ditampilkan sendirian kalau tidak ada gambar yang bisa dimuat.
///
/// Pasang `key: ValueKey(url)` supaya state ter-reset saat URL berganti.
class AdaptiveImage extends StatefulWidget {
  const AdaptiveImage({
    super.key,
    required this.url,
    this.fallbackUrl,
    this.overlay,
    this.maxHeight = 440,
  });

  final String? url;
  final String? fallbackUrl;
  final Widget? overlay;
  final double maxHeight;

  @override
  State<AdaptiveImage> createState() => _AdaptiveImageState();
}

class _AdaptiveImageState extends State<AdaptiveImage> {
  ImageStream? _stream;
  ImageStreamListener? _listener;
  String? _current;
  double? _ratio;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    final first = _nonEmpty(widget.url) ?? _nonEmpty(widget.fallbackUrl);
    if (first != null) {
      _load(first);
    } else {
      _failed = true;
    }
  }

  static String? _nonEmpty(String? s) => (s == null || s.isEmpty) ? null : s;

  void _load(String url) {
    _unlisten();
    _current = url;
    final stream = NetworkImage(url).resolve(ImageConfiguration.empty);
    final listener = ImageStreamListener(
      (info, _) {
        final w = info.image.width;
        final h = info.image.height;
        if (!mounted || w <= 0 || h <= 0) return;
        setState(() {
          _ratio = w / h;
          _failed = false;
        });
      },
      onError: (error, stackTrace) {
        if (!mounted) return;
        final fb = _nonEmpty(widget.fallbackUrl);
        if (fb != null && fb != _current) {
          // Hindari memodifikasi listener di tengah callback.
          Future.microtask(() {
            if (mounted) _load(fb);
          });
        } else {
          setState(() => _failed = true);
        }
      },
    );
    stream.addListener(listener);
    _stream = stream;
    _listener = listener;
  }

  void _unlisten() {
    final s = _stream;
    final l = _listener;
    if (s != null && l != null) s.removeListener(l);
    _stream = null;
    _listener = null;
  }

  @override
  void dispose() {
    _unlisten();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ratio = _ratio;

    if (_failed || ratio == null) {
      return PreviewFrame(
        aspectRatio: 16 / 9,
        maxHeight: widget.maxHeight,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_failed)
              widget.overlay ??
                  const Center(
                    child: Icon(
                      Icons.image_outlined,
                      color: MoriColors.ink,
                      size: 48,
                    ),
                  )
            else
              const Center(
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: MoriColors.ink,
                  ),
                ),
              ),
          ],
        ),
      );
    }

    return PreviewFrame(
      aspectRatio: ratio,
      maxHeight: widget.maxHeight,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image(
            image: NetworkImage(_current!),
            // Bingkai sudah pas dengan rasio gambar, jadi cover tidak
            // memotong apa pun dan tidak menyisakan ruang kosong.
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) =>
                const SizedBox.shrink(),
          ),
          if (widget.overlay != null) widget.overlay!,
        ],
      ),
    );
  }
}
