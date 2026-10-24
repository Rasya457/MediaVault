import 'package:flutter/material.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../services/providers/models.dart';
import '../download/batch_download_controller.dart';
import '../download/download_controller.dart';
import '../download/widgets/progress_tile.dart';
import 'widgets/audio_preview.dart';
import 'widgets/quality_selector.dart';
import 'widgets/video_preview.dart';

/// Halaman pratinjau hasil ANALYZE: thumbnail, judul, pilih kualitas,
/// unduh dengan progress. [controller] opsional untuk test.
/// Untuk playlist/album Spotify tampil mode khusus: gambar cover playlist,
/// daftar lagu tanpa cover art, dan tombol UNDUH SEMUA.
/// Untuk carousel foto tampil slider foto yang bisa di-swipe + UNDUH SEMUA
/// FOTO. Post berisi video (galat campuran foto+video) selalu tampil mode
/// video biasa: pilihan kualitas termasuk foto, tanpa tombol unduh semua.
class PreviewPage extends StatefulWidget {
  const PreviewPage({
    super.key,
    required this.info,
    required this.sourceUrl,
    this.controller,
    this.batchController,
  });

  final MediaInfo info;
  final String sourceUrl;
  final DownloadController? controller;
  final BatchDownloadController? batchController;

  @override
  State<PreviewPage> createState() => _PreviewPageState();
}

class _PreviewPageState extends State<PreviewPage> {
  late final DownloadController _controller;
  late final BatchDownloadController _batch;
  late String _selectedItag;
  bool _ownsController = false;
  bool _ownsBatch = false;
  int? _activePreviewTrackIndex;
  // Index foto yang aktif di slider preview album
  int _albumPreviewIndex = 0;

  /// Mode playlist/album Spotify: semua pilihan berupa MP3 dan lebih dari satu lagu.
  bool get _isPlaylist =>
      widget.info.qualities.length > 1 &&
      widget.info.qualities.every((q) => q.extension == 'mp3');

  /// Mode album foto (Instagram carousel murni): ada ≥2 item foto dan
  /// TANPA video. Post yang berisi video (termasuk campuran foto+video)
  /// dan video dengan beberapa pilihan kualitas tampil sebagai mode biasa:
  /// pilih kualitas + MP3, tanpa tombol unduh semua.
  bool get _isMediaAlbum {
    final qs = widget.info.qualities;
    var photos = 0;
    var videos = 0;
    for (final q in qs) {
      if (_isPhotoExtension(q.extension)) {
        photos++;
      } else if (q.extension == 'mp4' ||
          q.extension == 'webm' ||
          q.extension == 'mov') {
        videos++;
      }
    }
    return photos >= 2 && videos == 0;
  }

  static bool _isPhotoExtension(String ext) =>
      ext == 'jpg' ||
      ext == 'jpeg' ||
      ext == 'png' ||
      ext == 'webp' ||
      ext == 'heic';

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? DownloadController();
    _ownsController = widget.controller == null;
    _batch = widget.batchController ?? BatchDownloadController();
    _ownsBatch = widget.batchController == null;
    _batch.prepare(
      _isMediaAlbum ? _mediaAlbumItems(widget.info) : _trackItems(widget.info),
    );

    // Utamakan format video yang memiliki audio agar saat halaman dibuka,
    // video langsung bersuara secara default.
    MediaQuality? defaultQuality;
    for (final q in widget.info.qualities) {
      if (q.extension != 'mp3' && q.extension != 'm4a') {
        if (q.hasAudio ?? false) {
          defaultQuality = q;
          break;
        }
      }
    }
    defaultQuality ??= widget.info.qualities.isNotEmpty
        ? widget.info.qualities.first
        : null;
    _selectedItag = defaultQuality?.itag ?? '';
  }

  @override
  void dispose() {
    if (_ownsController) _controller.dispose();
    if (_ownsBatch) _batch.dispose();
    super.dispose();
  }

  MediaQuality? get _selected {
    for (final q in widget.info.qualities) {
      if (q.itag == _selectedItag) return q;
    }
    return widget.info.qualities.isEmpty ? null : widget.info.qualities.first;
  }

  void _download() {
    final q = _selected;
    if (q == null) return;
    final filename = '${_sanitize(widget.info.title)}.${q.extension}';
    _controller.downloadMedia(
      url: q.itag,
      filename: filename,
      quality: q,
      headers: widget.info.downloadHeaders,
      title: widget.info.title,
      author: widget.info.author,
      platform: widget.info.providerName,
      thumbnail: widget.info.thumbnail,
    );
  }

  // ---------- Mode playlist (Spotify): daftar lagu + UNDUH SEMUA ----------

  /// Label track dari provider: "01 Artist - Title [MP3]".
  static final RegExp _trackLabelRe =
      RegExp(r'^(\d+)\s+(.+?)\s+\[(MP3[^\]]*)\]$');

  /// Ubah kualitas MP3 per track menjadi antrian unduhan.
  List<BatchItem> _trackItems(MediaInfo info) {
    final items = <BatchItem>[];
    for (final q in info.qualities) {
      if (q.extension != 'mp3') continue;
      var numPart = '';
      var rest = q.label;
      final m = _trackLabelRe.firstMatch(q.label);
      if (m != null) {
        numPart = m.group(1)!;
        rest = m.group(2)!;
      }
      String artist = '';
      String title = rest;
      final sep = rest.indexOf(' - ');
      if (sep > 0) {
        artist = rest.substring(0, sep);
        title = rest.substring(sep + 3);
      }
      final name = _sanitize(
        '${numPart.isEmpty ? '' : '$numPart '}'
        '${artist.isEmpty ? '' : '$artist - '}$title',
      );
      items.add(BatchItem(
        url: q.itag,
        filename: '$name.mp3',
        title: title,
        artist: artist,
        extension: 'mp3',
        headers: info.downloadHeaders,
        thumbnail: info.thumbnail,
        previewUrl: q.audioUrl ?? (q.itag.startsWith('http') ? q.itag : null),
      ));
    }
    return items;
  }

  /// Ubah kualitas foto/video album menjadi antrian unduhan.
  List<BatchItem> _mediaAlbumItems(MediaInfo info) {
    final items = <BatchItem>[];
    final albumQualities = info.qualities
        .where((q) =>
            q.extension == 'jpg' ||
            q.extension == 'jpeg' ||
            q.extension == 'png' ||
            q.extension == 'webp' ||
            q.extension == 'heic' ||
            q.extension == 'mp4' ||
            q.extension == 'mov')
        .toList();
    for (var i = 0; i < albumQualities.length; i++) {
      final q = albumQualities[i];
      final isPhoto = q.extension != 'mp4' && q.extension != 'mov';
      final index = (i + 1).toString().padLeft(2, '0');
      final title = isPhoto ? 'Foto $index' : 'Video $index';
      final filename = '${_sanitize(info.title)}_$index.${q.extension}';
      items.add(BatchItem(
        url: q.itag,
        filename: filename,
        title: title,
        artist: info.author,
        extension: q.extension,
        headers: info.downloadHeaders,
        thumbnail: q.itag.contains('.jpg') || q.itag.contains('cdn')
            ? q.itag
            : info.thumbnail,
      ));
    }
    return items;
  }

  void _downloadAll() => _batch.start();

  void _downloadOne(BatchItem item) => _batch.startOne(item);

  static String _resolvePreviewUrl(
    MediaQuality? selected,
    List<MediaQuality> allQualities,
  ) {
    if (selected == null) return '';
    if (selected.needsMerge) {
      for (final q in allQualities) {
        if (q.extension != 'mp3' &&
            q.extension != 'm4a' &&
            (q.hasAudio ?? false)) {
          return q.itag;
        }
      }
    }
    return selected.itag;
  }

  static String _sanitize(String name) {
    var clean = name.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '').trim();
    if (clean.isEmpty) clean = 'download';
    if (clean.length > 80) clean = clean.substring(0, 80).trim();
    return clean;
  }

  static String _formatDuration(int? seconds) {
    if (seconds == null) return '--:--';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  /// Preview mengikuti kualitas terpilih. Gambar dan thumbnail memakai
  /// rasio aslinya (landscape maupun portrait), tanpa letterbox/background.
  Widget _buildPreview(MediaQuality? selected, String? thumb, MediaInfo info) {
    if (selected == null) {
      return const _PreviewFrame(
        aspectRatio: 16 / 9,
        child: Center(
          child: Icon(Icons.movie_outlined, color: Color(0xFF97A2AD), size: 48),
        ),
      );
    }

    final isAudio = selected.extension == 'mp3' ||
        selected.extension == 'm4a' ||
        selected.extension == 'wav' ||
        selected.extension == 'aac' ||
        selected.extension == 'opus' ||
        selected.label.toLowerCase().contains('mp3') ||
        selected.label.toLowerCase().contains('audio');
    if (isAudio) {
      return AudioPreview(
        key: ValueKey('audio:${selected.itag}'),
        audioUrl: selected.itag,
        thumbnailUrl: thumb ?? info.thumbnail,
        title: info.title,
        artist: info.author,
        durationSec: info.durationSec,
        headers: info.downloadHeaders,
      );
    }

    final isVideo = selected.extension == 'mp4' || selected.extension == 'webm';
    if (!isVideo) {
      // Foto: tampilkan utuh sesuai rasio asli, fallback ke thumbnail.
      return _AdaptiveImage(
        key: ValueKey('image:${selected.itag}'),
        url: selected.itag,
        fallbackUrl: thumb,
        maxHeight: 440,
      );
    }

    final previewUrl = _resolvePreviewUrl(selected, info.qualities);
    return VideoPreview(
      key: ValueKey(previewUrl),
      url: previewUrl,
      fallbackThumbnail: thumb,
    );
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    final thumb = info.thumbnail;
    final selected = _selected;
    final scheme = MoriScheme.of(context);
    return Scaffold(
      backgroundColor: scheme.background,
      body: SafeArea(
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.all(MoriSpacing.pagePad),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'PRATINJAU',
                    style: TextStyle(
                      fontFamily: 'Geist',
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: MoriText.labelLetterSpacing,
                      color: scheme.ink,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, color: scheme.ink),
                  tooltip: 'Tutup',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _isPlaylist
                ? (_activePreviewTrackIndex != null
                    ? _buildPlaylistAudioPreview(thumb, info)
                    : _buildPlaylistCover(thumb))
                : _isMediaAlbum
                    ? _buildAlbumSlider()
                    : _buildPreview(selected, thumb, info),
            const SizedBox(height: 16),
            Text(
              info.title,
              style: TextStyle(
                fontFamily: 'Geist',
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: scheme.ink,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _Badge(scheme, info.providerName.toUpperCase()),
                _Badge(scheme, info.source == 'direct' ? 'DIRECT CDN' : 'FALLBACK'),
                if (_isPlaylist)
                  _Badge(
                    scheme,
                    '${info.qualities.where((q) => q.extension == 'mp3').length} LAGU',
                  ),
                if (_isMediaAlbum)
                  _Badge(
                    scheme,
                    '${_batch.items.length} ITEM',
                  ),
                if (info.author.isNotEmpty)
                  Text(
                    info.author,
                    style: TextStyle(
                      fontFamily: 'Geist',
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: scheme.secondary,
                    ),
                  ),
                if (info.durationSec != null)
                  Text(
                    _formatDuration(info.durationSec),
                    style: TextStyle(
                      fontFamily: 'Geist',
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: scheme.secondary,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            if (_isPlaylist)
              ..._playlistBody()
            else if (_isMediaAlbum)
              ..._albumBatchBody()
            else ...[
              Text(
                'PILIH KUALITAS',
                style: TextStyle(
                  fontFamily: 'Geist',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: MoriText.labelLetterSpacing,
                  color: scheme.secondary,
                ),
              ),
              const SizedBox(height: 10),
              QualitySelector(
                qualities: info.qualities,
                selectedItag: _selectedItag,
                onSelect: (itag) => setState(() => _selectedItag = itag),
              ),
              const SizedBox(height: 20),
              AnimatedBuilder(
                animation: _controller,
                builder: (context, _) => _DownloadSection(
                  controller: _controller,
                  onDownload: _download,
                  hasQualities: info.qualities.isNotEmpty,
                ),
              ),
            ],
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  /// Pratinjau audio untuk lagu yang dipilih dalam mode playlist ala Mori.
  Widget _buildPlaylistAudioPreview(String? thumb, MediaInfo info) {
    if (_batch.items.isEmpty || _activePreviewTrackIndex == null) {
      return _buildPlaylistCover(thumb);
    }
    final track = _batch.items[_activePreviewTrackIndex!.clamp(0, _batch.items.length - 1)];
    final previewUrl = track.previewUrl ?? (track.url.startsWith('http') ? track.url : '');
    if (previewUrl.isEmpty) {
      return _buildPlaylistCover(thumb);
    }
    return AudioPreview(
      key: ValueKey('playlist_preview_${_activePreviewTrackIndex}_$previewUrl'),
      audioUrl: previewUrl,
      thumbnailUrl: track.thumbnail ?? thumb,
      title: track.title,
      artist: track.artist.isNotEmpty ? track.artist : info.author,
      headers: info.downloadHeaders,
    );
  }

  /// Cover playlist ("PP") sebagai fallback jika belum ada preview audio.
  Widget _buildPlaylistCover(String? thumb) {
    if (thumb == null || thumb.isEmpty) {
      return const _PreviewFrame(
        aspectRatio: 1,
        maxHeight: 320,
        child: Center(
          child: Icon(
            Icons.library_music_rounded,
            color: Color(0xFF97A2AD),
            size: 48,
          ),
        ),
      );
    }
    return _AdaptiveImage(url: thumb, maxHeight: 320);
  }

  /// Bagian bawah mode playlist: tombol aksi Unduh Semua + daftar lagu dengan
  /// fitur pratinjau putar audio per lagu serta tombol unduh 1 lagu terpisah.
  List<Widget> _playlistBody() {
    final items = _batch.items;
    final scheme = MoriScheme.of(context);
    return [
      AnimatedBuilder(
        animation: _batch,
        builder: (context, _) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Aksi Unduh Semua di bagian atas daftar
              _BatchSection(batch: _batch, onDownloadAll: _downloadAll),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'DAFTAR LAGU (${items.length})',
                    style: TextStyle(
                      fontFamily: 'Geist',
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: MoriText.labelLetterSpacing,
                      color: scheme.secondary,
                    ),
                  ),
                  Text(
                    'Putar pratinjau / Unduh lagu',
                    style: TextStyle(
                      fontFamily: 'Geist',
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: scheme.faint,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              for (var i = 0; i < items.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ProgressTile(
                    key: ValueKey('track-$i-${items[i].url}'),
                    index: i + 1,
                    item: items[i],
                    isSelected: _activePreviewTrackIndex == i,
                    onTap: _batch.running ? null : () => _downloadOne(items[i]),
                    onPlay: () {
                      setState(() {
                        if (_activePreviewTrackIndex == i) {
                          _activePreviewTrackIndex = null;
                        } else {
                          _activePreviewTrackIndex = i;
                        }
                      });
                    },
                    onDownload: _batch.running ? null : () => _downloadOne(items[i]),
                  ),
                ),
            ],
          );
        },
      ),
    ];
  }

  // ---------- Mode album foto (Instagram carousel, dll) ----------

  /// Slider foto untuk carousel. Swipe kiri/kanan antar foto.
  Widget _buildAlbumSlider() {
    final scheme = MoriScheme.of(context);
    final photos = widget.info.qualities
        .where((q) => _isPhotoExtension(q.extension))
        .toList();
    if (photos.isEmpty) return _buildPlaylistCover(widget.info.thumbnail);

    final total = photos.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          height: 320,
          child: PageView.builder(
            onPageChanged: (i) => setState(() => _albumPreviewIndex = i),
            itemCount: total,
            itemBuilder: (ctx, i) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: _AdaptiveImage(
                  key: ValueKey('album-slide-$i-${photos[i].itag}'),
                  url: photos[i].itag,
                  fallbackUrl: widget.info.thumbnail,
                  maxHeight: 312,
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Dot indicators — melebar jika aktif
            ...List.generate(total, (i) {
              final active = _albumPreviewIndex == i;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: active ? 18 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: active ? scheme.accent : scheme.hairline,
                  borderRadius: BorderRadius.circular(3),
                ),
              );
            }),
            const SizedBox(width: 10),
            Text(
              '${_albumPreviewIndex + 1}/$total',
              style: TextStyle(
                fontFamily: 'Geist',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: scheme.secondary,
              ),
            ),
          ],
        ),
      ],
    );
  }

  List<Widget> _albumBatchBody() {
    final scheme = MoriScheme.of(context);
    // Post foto TikTok (photomode) juga punya musik: sediakan tile MP3
    // tambahan di bawah daftar foto, tanpa ikut UNDUH SEMUA FOTO.
    final mp3Qualities = widget.info.qualities
        .where((q) => q.extension == 'mp3')
        .toList();
    final audioItems = <BatchItem>[];
    for (final q in mp3Qualities) {
      audioItems.add(BatchItem(
        url: q.itag,
        filename: '${_sanitize(widget.info.title)}_audio.mp3',
        title: 'Audio MP3',
        artist: widget.info.author,
        extension: 'mp3',
        headers: widget.info.downloadHeaders,
        thumbnail: widget.info.thumbnail,
      ));
    }
    return [
      AnimatedBuilder(
        animation: _batch,
        builder: (context, _) {
          final items = _batch.items;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _BatchSection(
                batch: _batch,
                onDownloadAll: _downloadAll,
                label: 'UNDUH SEMUA FOTO (${items.length})',
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'FOTO (${items.length})',
                    style: TextStyle(
                      fontFamily: 'Geist',
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: MoriText.labelLetterSpacing,
                      color: scheme.secondary,
                    ),
                  ),
                  Text(
                    'Unduh satu per satu',
                    style: TextStyle(
                      fontFamily: 'Geist',
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: scheme.faint,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Daftar foto sebagai list tile (pakai ProgressTile tanpa tombol play)
              for (var i = 0; i < items.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ProgressTile(
                    key: ValueKey('album-$i-${items[i].url}'),
                    index: i + 1,
                    item: items[i],
                    onDownload: _batch.running
                        ? null
                        : () => _downloadOne(items[i]),
                  ),
                ),
              if (audioItems.isNotEmpty) ...[
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'AUDIO (${audioItems.length})',
                      style: TextStyle(
                        fontFamily: 'Geist',
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: MoriText.labelLetterSpacing,
                        color: scheme.secondary,
                      ),
                    ),
                    Text(
                      'Musik dari post ini',
                      style: TextStyle(
                        fontFamily: 'Geist',
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: scheme.faint,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                for (var i = 0; i < audioItems.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: ProgressTile(
                      key: ValueKey('album-audio-$i-${audioItems[i].url}'),
                      index: items.length + i + 1,
                      item: audioItems[i],
                      onDownload: _batch.running
                          ? null
                          : () => _downloadOne(audioItems[i]),
                    ),
                  ),
              ],
              const SizedBox(height: 8),
            ],
          );
        },
      ),
    ];
  }
}

class _PreviewFrame extends StatelessWidget {
  const _PreviewFrame({
    required this.aspectRatio,
    required this.child,
    this.maxHeight = 440,
  });

  final double aspectRatio;
  final double maxHeight;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = MoriScheme.of(context);
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
              color: scheme.surface,
              border: Border.all(
                color: scheme.hairline,
                width: MoriBorder.tile,
              ),
              borderRadius: BorderRadius.circular(MoriRadius.card),
              boxShadow: MoriShadow.product,
            ),
            child: child,
          ),
        );
      },
    );
  }
}

/// Gambar jaringan yang rasio aslinya dibaca dulu, lalu dibingkai pas
/// ([_PreviewFrame]). [fallbackUrl] dipakai kalau [url] gagal dimuat.
///
/// Pasang `key: ValueKey(url)` supaya state ter-reset saat URL berganti.
class _AdaptiveImage extends StatefulWidget {
  const _AdaptiveImage({
    super.key,
    required this.url,
    this.fallbackUrl,
    this.maxHeight = 440,
  });

  final String? url;
  final String? fallbackUrl;
  final double maxHeight;

  @override
  State<_AdaptiveImage> createState() => _AdaptiveImageState();
}

class _AdaptiveImageState extends State<_AdaptiveImage> {
  ImageStream? _stream;
  ImageStreamListener? _listener;
  String? _current;
  double? _ratio;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    final first = _nonEmpty(widget.url);
    if (first != null) {
      _load(first);
    } else {
      final fb = _nonEmpty(widget.fallbackUrl);
      if (fb != null) {
        _load(fb);
      } else {
        _failed = true;
      }
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
      return _PreviewFrame(
        aspectRatio: 16 / 9,
        maxHeight: widget.maxHeight,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_failed)
              const Center(
                child: Icon(
                  Icons.image_outlined,
                  color: Color(0xFF97A2AD),
                  size: 48,
                ),
              )
            else
              const Center(
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
              ),
          ],
        ),
      );
    }

    return _PreviewFrame(
      aspectRatio: ratio,
      maxHeight: widget.maxHeight,
      child: Image(
        image: NetworkImage(_current!),
        // Bingkai sudah pas dengan rasio gambar, jadi cover tidak
        // memotong apa pun dan tidak menyisakan ruang kosong.
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) =>
            const SizedBox.shrink(),
      ),
    );
  }
}

/// Badge metadata: pill netral bordered (bukan aksen).
class _Badge extends StatelessWidget {
  const _Badge(this.scheme, this.text);
  final MoriScheme scheme;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(
          color: scheme.hairline,
          width: MoriBorder.tile,
        ),
        borderRadius: BorderRadius.circular(MoriRadius.pill),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: 'Geist',
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: scheme.secondary,
        ),
      ),
    );
  }
}

class _DownloadSection extends StatelessWidget {
  const _DownloadSection({
    required this.controller,
    required this.onDownload,
    required this.hasQualities,
  });

  final DownloadController controller;
  final VoidCallback onDownload;
  final bool hasQualities;

  @override
  Widget build(BuildContext context) {
    final scheme = MoriScheme.of(context);
    if (controller.status == DownloadStatus.downloading) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: controller.progress >= 0 ? controller.progress : null,
              backgroundColor: scheme.surfaceVariant,
              color: scheme.accent,
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            controller.progress >= 0
                ? '${(controller.progress * 100).toStringAsFixed(0)}%'
                : 'Mengunduh media...',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Geist',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: scheme.ink,
            ),
          ),
        ],
      );
    }

    if (controller.status == DownloadStatus.success) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: scheme.accentTint,
          border: Border.all(color: scheme.hairline, width: MoriBorder.field),
          borderRadius: BorderRadius.circular(MoriRadius.card),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_rounded, color: scheme.success, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                controller.savedLabel ?? 'Tersimpan ke perangkat',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Geist',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: scheme.ink,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (controller.status == DownloadStatus.error) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.error.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(MoriRadius.tile),
              border: Border.all(color: scheme.error.withValues(alpha: 0.35)),
            ),
            child: Text(
              controller.errorMessage ?? 'Gagal mengunduh',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Geist',
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: scheme.error,
              ),
            ),
          ),
          const SizedBox(height: 12),
          _downloadButton(context),
        ],
      );
    }

    return _downloadButton(context);
  }

  Widget _downloadButton(BuildContext context) {
    return ElevatedButton(
      onPressed: hasQualities ? onDownload : null,
      // Warna dari elevatedButtonTheme (dark-aware); tanpa override manual.
      child: const Text(
        'UNDUH',
        style: TextStyle(
          fontFamily: 'Geist',
          fontSize: 15,
          fontWeight: FontWeight.w800,
          letterSpacing: 2,
        ),
      ),
    );
  }
}

/// Aksi unduh mode playlist/album: UNDUH SEMUA, progress keseluruhan,
/// dan BATALKAN selama berjalan.
class _BatchSection extends StatelessWidget {
  const _BatchSection({
    required this.batch,
    required this.onDownloadAll,
    this.label,
  });

  final BatchDownloadController batch;
  final VoidCallback onDownloadAll;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final scheme = MoriScheme.of(context);
    final total = batch.items.length;
    if (total == 0) return const SizedBox.shrink();

    if (batch.running) {
      final pct = (batch.overallProgress * 100).toStringAsFixed(0);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: batch.overallProgress,
              backgroundColor: scheme.surfaceVariant,
              color: scheme.accent,
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            batch.failedCount > 0
                ? '$pct% · ${batch.doneCount}/$total tersimpan, '
                    '${batch.failedCount} gagal'
                : '$pct% · ${batch.doneCount}/$total tersimpan',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Geist',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: scheme.ink,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: batch.cancelAll,
            style: OutlinedButton.styleFrom(
              foregroundColor: scheme.error,
              side: BorderSide(color: scheme.error, width: 1.2),
              minimumSize: const Size.fromHeight(48),
            ),
            child: const Text(
              'BATALKAN SEMUA',
              style: TextStyle(
                fontFamily: 'Geist',
                fontSize: 14,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
              ),
            ),
          ),
        ],
      );
    }

    final finished = batch.doneCount + batch.failedCount > 0;
    final summary = batch.failedCount > 0
        ? '${batch.doneCount} tersimpan, ${batch.failedCount} gagal'
        : batch.doneCount > 0
            ? '${batch.doneCount} lagu tersimpan'
            : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (finished && summary != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              summary,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Geist',
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: batch.failedCount > 0 ? scheme.error : scheme.success,
              ),
            ),
          ),
        ElevatedButton(
          onPressed: onDownloadAll,
          child: Text(
            label ?? 'UNDUH SEMUA ($total)',
            style: const TextStyle(
              fontFamily: 'Geist',
              fontSize: 15,
              fontWeight: FontWeight.w800,
              letterSpacing: 2,
            ),
          ),
        ),
      ],
    );
  }
}

