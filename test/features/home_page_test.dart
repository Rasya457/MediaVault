import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediavault/core/network/api_client.dart' as client_lib;
import 'package:mediavault/features/home/home_page.dart';
import 'package:mediavault/services/providers/remote_config.dart';

import '../helpers/mock_remote_config.dart';

/// Adapter yang MENAHAN semua permintaan sampai [gate] selesai:
/// menstruktur ulang analisa yang berjalan lama tanpa jaringan nyata.
/// Semua permintaan diarahkan ke config palsu (injectMockEndpoints)
/// sehingga tidak ada socket keluar — aman untuk flutter_test.
class _GateAdapter implements HttpClientAdapter {
  _GateAdapter(this.gate);

  final Completer<void> gate;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) {
    return gate.future.then(
      (_) => ResponseBody.fromString(
        '{}',
        200,
        headers: {
          'content-type': ['application/json'],
        },
      ),
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  final realAdapter = client_lib.httpClient.httpClientAdapter;

  setUp(() {
    injectMockEndpoints({
      'spotify_primary': const EndpointEntry(
        url: 'https://example.invalid/en1',
        method: 'POST',
        enabled: true,
      ),
      'spotify_fallback': const EndpointEntry(
        url: 'https://example.invalid/fb',
        method: 'GET',
        enabled: true,
      ),
    });
  });

  tearDown(() {
    RemoteConfig.instance.resetCache();
    client_lib.httpClient.httpClientAdapter = realAdapter;
  });

  testWidgets('tombol analisa jadi BATAL saat berjalan dan membatalkannya', (
    tester,
  ) async {
    final gate = Completer<void>();
    client_lib.httpClient.httpClientAdapter = _GateAdapter(gate);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HomePage(),
        ),
      ),
    );

    await tester.enterText(
      find.byType(TextField),
      'https://open.spotify.com/track/abc',
    );
    await tester.pump();

    // Tekan ANALISIS → analisa menetap di adapter (jaringan lama/lambat).
    await tester.tap(
      find.ancestor(
        of: find.text('ANALISIS'),
        matching: find.byType(FilledButton),
      ),
    );
    await tester.pump();

    expect(find.text('BATAL'), findsOneWidget);
    expect(find.text('ANALISIS'), findsNothing);

    // Tekan BATAL → analisa dibatalkan, tombol kembali ANALISIS.
    await tester.tap(
      find.ancestor(
        of: find.text('BATAL'),
        matching: find.byType(FilledButton),
      ),
    );
    await tester.pump();

    expect(find.text('Analisa dibatalkan.'), findsOneWidget);
    expect(find.text('ANALISIS'), findsOneWidget);
    expect(find.text('BATAL'), findsNothing);

    // Fetch lama selesai belakangan → hasil dibuang (generasi tidak cocok):
    // tidak ada pratinjau terbuka dan tidak ada snackbar galat tertulis.
    gate.complete();
    await tester.pumpAndSettle();
    // Tempuh snackbar informasi sampai hilang (timer dismiss tidak
    // menjadwalkan frame, pumpAndSettle berhenti sebelum jangkarnya).
    await tester.pump(const Duration(seconds: 3));

    expect(find.byType(HomePage), findsOneWidget);
    expect(find.text('ANALISIS'), findsOneWidget);
    expect(
      find.textContaining('memakan waktu terlalu lama'),
      findsNothing,
    );
  });
}
