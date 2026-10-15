import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediavault/services/share_intent_service.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

class _FakeSource implements ShareIntentSource {
  List<SharedMediaFile> initial = [];
  final controller = StreamController<List<SharedMediaFile>>.broadcast();
  var resetCalled = false;

  @override
  Future<List<SharedMediaFile>> getInitialMedia() async => initial;

  @override
  Stream<List<SharedMediaFile>> getMediaStream() => controller.stream;

  @override
  Future<void> reset() async => resetCalled = true;
}

SharedMediaFile _file(String path) =>
    SharedMediaFile(path: path, type: SharedMediaType.text);

void main() {
  test('initialLinks ekstrak URL + reset sekali pakai', () async {
    final source = _FakeSource()
      ..initial = [
        _file('cek nih https://www.tiktok.com/@u/video/1.'),
        _file('cuma teks tanpa link'),
      ];
    final svc = ShareIntentService(source: source);

    final links = await svc.initialLinks();

    expect(links, ['https://www.tiktok.com/@u/video/1']);
    expect(source.resetCalled, isTrue);
  });

  test('linkBatches teruskan tiap batch', () async {
    final source = _FakeSource();
    final svc = ShareIntentService(source: source);
    final seen = <List<String>>[];
    final sub = svc.linkBatches().listen(seen.add);

    source.controller.add([_file('https://youtu.be/abc')]);
    source.controller.add([_file('bukan link')]);
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();

    expect(seen, [
      ['https://youtu.be/abc'],
      isEmpty,
    ]);
  });
}
