import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new_min/return_code.dart';

abstract class MediaMerger {
  Future<File> mergeVideoAudio({
    required File video,
    required File audio,
    required String outputPath,
  });

  Future<File> convertToMp3({
    required File input,
    required String outputPath,
  });
}

class FFmpegMediaMerger implements MediaMerger {
  FFmpegMediaMerger();

  @override
  Future<File> mergeVideoAudio({
    required File video,
    required File audio,
    required String outputPath,
  }) async {
    // 1) Remux murni (copy/copy): tercepat dan tidak butuh encoder apa pun.
    //    Valid saat pasangan berkontainer sama (mp4+avc1 dengan m4a/aac —
    //    pasangan yang dipilih _filterYouTubeQualities). Gagal/invalid
    //    untuk webm+opus, lanjut ke re-encode di bawah.
    final remuxable = _isMp4Family(video.path) && _isMp4Family(audio.path);
    if (remuxable) {
      final ok = await _run([
        '-y',
        '-i',
        video.path,
        '-i',
        audio.path,
        '-c',
        'copy',
        '-movflags',
        '+faststart',
        outputPath,
      ]);
      if (ok) return _ensureOutput(outputPath, 'remux');
    }

    // 2) Re-encode audio ke AAC (video tetap copy) — bekerja untuk
    //    sumber webm/opus maupun mp4 apa pun.
    final ok = await _run([
      '-y',
      '-i',
      video.path,
      '-i',
      audio.path,
      '-c:v',
      'copy',
      '-c:a',
      'aac',
      '-b:a',
      '192k',
      '-movflags',
      '+faststart',
      outputPath,
    ]);
    if (!ok) {
      throw Exception('FFmpeg merge failed: ${await _lastLogs}');
    }
    return _ensureOutput(outputPath, 're-encode');
  }

  @override
  Future<File> convertToMp3({
    required File input,
    required String outputPath,
  }) async {
    // 1) Encode MP3 via libmp3lame (kualitas tinggi).
    final ok = await _run([
      '-y',
      '-i',
      input.path,
      '-vn',
      '-c:a',
      'libmp3lame',
      '-q:a',
      '2',
      outputPath,
    ]);
    if (ok) return _ensureOutput(outputPath, 'mp3');

    // 2) Fallback m4a copy: package ffmpeg "min" tidak selalu memuat
    //    libmp3lame. Salin stream AAC apa adanya ke .m4a — tetap audio
    //    penuh dan bisa diputar semua pemutar musik.
    final m4aPath = outputPath.replaceFirst(
      RegExp(r'\.mp3$', caseSensitive: false),
      '.m4a',
    );
    final copyOk = await _run([
      '-y',
      '-i',
      input.path,
      '-vn',
      '-c:a',
      'copy',
      m4aPath,
    ]);
    if (copyOk) return _ensureOutput(m4aPath, 'm4a');

    final logs = await _lastLogs;
    throw Exception('FFmpeg konversi audio gagal: $logs');
  }

  /// Session FFmpeg terakhir yang dijalankan (untuk log error).
  FFmpegSession? _lastSession;

  /// Jalankan satu perintah FFmpeg. True bila sukses.
  Future<bool> _run(List<String> args) async {
    try {
      final session = await FFmpegKit.executeWithArguments(args);
      _lastSession = session;
      final returnCode = await session.getReturnCode();
      return ReturnCode.isSuccess(returnCode);
    } catch (_) {
      return false;
    }
  }

  Future<String> get _lastLogs async {
    try {
      return await _lastSession?.getAllLogsAsString() ?? '';
    } catch (_) {
      return '';
    }
  }

  static bool _isMp4Family(String path) {
    final ext = path.split('.').last.toLowerCase();
    return ext == 'mp4' || ext == 'm4a';
  }

  static Future<File> _ensureOutput(String path, String stage) async {
    final out = File(path);
    if (!await out.exists() || await out.length() == 0) {
      throw Exception('File hasil $stage tidak ditemukan/kosong.');
    }
    return out;
  }
}
