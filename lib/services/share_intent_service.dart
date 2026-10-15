import 'package:receive_sharing_intent/receive_sharing_intent.dart';

final _urlPattern = RegExp(r'https?://[^\s]+');

/// Sumber intent share. Abstraksi agar logika filter URL unit-testable
/// tanpa method channel asli.
abstract class ShareIntentSource {
  Future<List<SharedMediaFile>> getInitialMedia();
  Stream<List<SharedMediaFile>> getMediaStream();
  Future<void> reset();
}

class _PluginShareIntentSource implements ShareIntentSource {
  @override
  Future<List<SharedMediaFile>> getInitialMedia() =>
      ReceiveSharingIntent.instance.getInitialMedia();

  @override
  Stream<List<SharedMediaFile>> getMediaStream() =>
      ReceiveSharingIntent.instance.getMediaStream();

  @override
  Future<void> reset() => ReceiveSharingIntent.instance.reset();
}

/// Link yang dibagikan dari aplikasi lain (TikTok/IG/YouTube → Share).
/// Hanya teks berisi URL http(s) yang diteruskan; sisanya diabaikan.
class ShareIntentService {
  final ShareIntentSource _source;

  ShareIntentService({ShareIntentSource? source})
      : _source = source ?? _PluginShareIntentSource();

  /// Link dari cold start (aplikasi dibuka via Share). Sekali pakai.
  Future<List<String>> initialLinks() async {
    final files = await _source.getInitialMedia();
    await _source.reset();
    return _extractUrls(files);
  }

  /// Link saat aplikasi sudah jalan (tiap Share baru = satu batch).
  Stream<List<String>> linkBatches() =>
      _source.getMediaStream().map(_extractUrls);

  static List<String> _extractUrls(List<SharedMediaFile> files) {
    final urls = <String>[];
    for (final f in files) {
      final match = _urlPattern.firstMatch(f.path);
      if (match != null) {
        urls.add(match.group(0)!.replaceAll(RegExp(r'[.,;:!?)]+$'), ''));
      }
    }
    return urls;
  }
}
