import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:path_provider/path_provider.dart';

/// Windows-only decoder for formats not handled by the PCM mpv driver.
/// Bundled unmodified LGPL FFmpeg writes WAV from the MEDIA SOURCE itself,
/// without using a microphone. URLs/tokens must never be logged.
abstract final class FfmpegSpeechAudioCapture {
  static const maxSeconds = 55.0;
  static File executable() => File(
      '${File(Platform.resolvedExecutable).parent.path}'
      '${Platform.pathSeparator}ffmpeg${Platform.pathSeparator}ffmpeg.exe');

  static List<String> arguments({
    required String mediaUrl,
    required double startSeconds,
    required double durationSeconds,
    required String outputPath,
    Map<String, String>? httpHeaders,
  }) {
    if (mediaUrl.isEmpty || startSeconds < 0 ||
        !startSeconds.isFinite || !durationSeconds.isFinite ||
        durationSeconds < 1 || durationSeconds > maxSeconds ||
        outputPath.isEmpty) {
      throw const FormatException('Invalid speech audio extraction range');
    }
    final args = <String>['-hide_banner', '-nostdin', '-loglevel', 'error', '-y'];
    // Audio source headers may contain secrets; do not print arguments.
    if (mediaUrl.startsWith('http://') || mediaUrl.startsWith('https://')) {
      if (httpHeaders != null && httpHeaders.isNotEmpty) {
        final headers = StringBuffer();
        for (final entry in httpHeaders.entries) {
          if (!RegExp(r'^[A-Za-z0-9-]+$').hasMatch(entry.key) ||
              entry.value.contains('\r') || entry.value.contains('\n')) {
            throw const FormatException('Invalid stream HTTP header');
          }
          headers.write('${entry.key}: ${entry.value}\r\n');
        }
        args.addAll(['-headers', headers.toString()]);
      }
    }
    args.addAll([
      '-ss', startSeconds.toStringAsFixed(3),
      '-i', mediaUrl,
      '-t', durationSeconds.toStringAsFixed(3),
      '-map', '0:a:0', '-vn', '-sn', '-dn',
      '-ac', '1', '-ar', '16000', '-c:a', 'pcm_s16le',
      '-f', 'wav', outputPath,
    ]);
    return args;
  }

  static Future<File> capture({
    required String mediaUrl,
    required double startSeconds,
    required double durationSeconds,
    Map<String, String>? httpHeaders,
  }) async {
    if (!Platform.isWindows) throw UnsupportedError('Windows only');
    final cli = executable();
    if (!await cli.exists()) {
      throw StateError('Bundled FFmpeg audio decoder is missing');
    }
    final directory = await getTemporaryDirectory();
    final random = Random.secure();
    final path = '${directory.path}${Platform.pathSeparator}'
        'playtorrio-ffmpeg-speech-${DateTime.now().microsecondsSinceEpoch}-'
        '${random.nextInt(1 << 32)}.wav';
    final wav = File(path);
    var completed = false;
    try {
      final args = arguments(
        mediaUrl: mediaUrl, startSeconds: startSeconds,
        durationSeconds: durationSeconds, outputPath: path,
        httpHeaders: httpHeaders,
      );
      final process = await Process.start(cli.path, args,
        workingDirectory: cli.parent.path);
      // Drain both pipes to avoid backpressure, discard stderr as it may
      // contain authenticated media URLs.
      final out = process.stdout.drain<void>();
      final err = process.stderr.drain<void>();
      final code = await process.exitCode.timeout(
        const Duration(seconds: 90),
        onTimeout: () {
          process.kill();
          throw TimeoutException('FFmpeg audio extraction timed out');
        },
      );
      await Future.wait([out, err]);
      if (code != 0) {
        throw StateError('FFmpeg could not decode movie audio (exit $code)');
      }
      if (!await wav.exists() || await wav.length() < 65536) {
        throw StateError('FFmpeg produced no usable movie audio sample');
      }
      final input = await wav.open();
      try {
        final header = await input.read(44);
        if (header.length < 44 || header[0] != 82 || header[1] != 73 ||
            header[2] != 70 || header[3] != 70 || header[8] != 87 ||
            header[9] != 65 || header[10] != 86 || header[11] != 69) {
          throw const FormatException('FFmpeg returned invalid WAV audio');
        }
      } finally {
        await input.close();
      }
      completed = true;
      return wav;
    } finally {
      if (!completed) {
        try { if (await wav.exists()) await wav.delete(); } catch (_) {}
      }
    }
  }
}
