import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/return_code.dart';

abstract class MediaMerger {
  Future<File> mergeVideoAudio({
    required File video,
    required File audio,
    required String outputPath,
  });
}

class FFmpegMediaMerger implements MediaMerger {
  const FFmpegMediaMerger();

  @override
  Future<File> mergeVideoAudio({
    required File video,
    required File audio,
    required String outputPath,
  }) async {
    final session = await FFmpegKit.executeWithArguments([
      '-y',
      '-i',
      video.path,
      '-i',
      audio.path,
      '-c:v',
      'copy',
      '-c:a',
      'aac',
      '-movflags',
      '+faststart',
      outputPath,
    ]);

    final returnCode = await session.getReturnCode();
    if (!ReturnCode.isSuccess(returnCode)) {
      final logs = await session.getAllLogsAsString();
      throw Exception('FFmpeg merge failed: $logs');
    }

    final out = File(outputPath);
    if (!await out.exists()) {
      throw Exception('File hasil merge tidak ditemukan.');
    }
    return out;
  }
}
