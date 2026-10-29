import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'mpv_speech_audio_capture.dart';
import 'ffmpeg_speech_audio_capture.dart';
import 'speech_subtitle_alignment.dart';

/// Stage-specific, privacy-safe error shown in the Windows player.
/// Never expose media URLs or bearer-like HTTP headers.
class WindowsSpeechSyncFailure implements Exception {
  final String message;
  const WindowsSpeechSyncFailure(this.message);
  @override
  String toString() => message;
}

/// CPU-only whisper.cpp on Windows. The 148 MB English model is downloaded
/// once after user approval and verified by SHA-256. No microphone or cloud ASR.
abstract final class WindowsWhisperTranscriber {
  static const modelName = 'ggml-base.en.bin';
  static const modelBytes = 147964211;
  static const modelSha256 =
      'a03779c86df3323075f5e796cb2ce5029f00ec8869eee3fdfb897afe36c6d002';
  static const modelUrl =
      'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin';
  static Future<File>? _pendingDownload;

  static File executable() => File(
      File(Platform.resolvedExecutable).parent.path +
          Platform.pathSeparator + 'whisper' + Platform.pathSeparator +
          'whisper-cli.exe');

  static Future<File> _modelFile() async {
    final support = await getApplicationSupportDirectory();
    return File(support.path + Platform.pathSeparator +
        'speech_models' + Platform.pathSeparator + modelName);
  }

  static Future<bool> hasModel() async {
    if (!Platform.isWindows) return false;
    final model = await _modelFile();
    return await model.exists() && await model.length() == modelBytes;
  }

  static Future<File> ensureModel() =>
      _pendingDownload ??= _downloadModel().whenComplete(() {
        _pendingDownload = null;
      });

  static Future<File> _downloadModel() async {
    if (!Platform.isWindows) throw UnsupportedError('Windows only');
    final model = await _modelFile();
    if (await hasModel()) return model;
    await model.parent.create(recursive: true);
    final partial = File(model.path + '.part');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
    try {
      final request = await client.getUrl(Uri.parse(modelUrl));
      request.followRedirects = true;
      final response = await request.close().timeout(const Duration(seconds: 45));
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('Whisper download HTTP ' + response.statusCode.toString());
      }
      final sink = partial.openWrite();
      try {
        await sink.addStream(response).timeout(const Duration(minutes: 8));
      } finally {
        await sink.close();
      }
      if (await partial.length() != modelBytes ||
          (await sha256.bind(partial.openRead()).first).toString() != modelSha256) {
        throw const FormatException('Whisper model checksum mismatch');
      }
      if (await model.exists()) await model.delete();
      return partial.rename(model.path);
    } finally {
      client.close(force: true);
      if (await partial.exists()) await partial.delete();
    }
  }

  /// Convert MPV WAV (PCM 16/24/32 or float 32, mono/stereo) to 16 kHz
  /// mono signed 16-bit WAV, as required by whisper-cli.
  static Uint8List whisperWave(Uint8List input) {
    if (!MpvSpeechAudioCapture.isWaveHeader(input) || input.length < 44) {
      throw const FormatException('Invalid WAV header');
    }
    final data = ByteData.sublistView(input);
    int? fmt, fmtSize, audio, audioBytes;
    for (var pos = 12; pos + 8 <= input.length;) {
      final tag = ascii.decode(input.sublist(pos, pos + 4), allowInvalid: true);
      final length = data.getUint32(pos + 4, Endian.little);
      if (length > input.length - pos - 8) break;
      if (tag == 'fmt ') { fmt = pos + 8; fmtSize = length; }
      if (tag == 'data') { audio = pos + 8; audioBytes = length; }
      pos += 8 + length + (length.isOdd ? 1 : 0);
    }
    if (fmt == null || fmtSize == null || fmtSize < 16 ||
        audio == null || audioBytes == null) {
      throw const FormatException('WAV format/data missing');
    }
    var kind = data.getUint16(fmt, Endian.little);
    final channels = data.getUint16(fmt + 2, Endian.little);
    final rate = data.getUint32(fmt + 4, Endian.little);
    final blockSize = data.getUint16(fmt + 12, Endian.little);
    final bits = data.getUint16(fmt + 14, Endian.little);
    if (kind == 0xfffe && fmtSize >= 40) {
      kind = data.getUint16(fmt + 24, Endian.little);
    }
    if (channels < 1 || channels > 8 || rate < 8000 || rate > 192000 ||
        blockSize < channels * (bits ~/ 8) ||
        !((kind == 1 && [16, 24, 32].contains(bits)) ||
          (kind == 3 && bits == 32))) {
      throw const FormatException('Unsupported PCM WAV format');
    }
    final frames = audioBytes ~/ blockSize;
    final count = (frames * 16000 / rate).floor();
    if (count < 16000 || count > 16000 * 56) {
      throw const FormatException('Invalid WAV sample duration');
    }
    double sampleAt(int frame) {
      final position = audio! + math.min(frame, frames - 1) * blockSize;
      var sum = 0.0;
      for (var ch = 0; ch < channels; ch++) {
        final pos = position + ch * (bits ~/ 8);
        double value;
        if (kind == 3) {
          value = data.getFloat32(pos, Endian.little);
        } else if (bits == 16) {
          value = data.getInt16(pos, Endian.little) / 32768;
        } else if (bits == 24) {
          var raw = input[pos] | (input[pos + 1] << 8) | (input[pos + 2] << 16);
          if (raw & 0x800000 != 0) raw -= 0x1000000;
          value = raw / 8388608;
        } else {
          value = data.getInt32(pos, Endian.little) / 2147483648;
        }
        sum += value.isFinite ? value : 0;
      }
      return sum / channels;
    }
    final output = Uint8List(44 + count * 2);
    final result = ByteData.sublistView(output);
    void writeTag(int offset, String value) =>
        output.setRange(offset, offset + value.length, ascii.encode(value));
    writeTag(0, 'RIFF'); result.setUint32(4, output.length - 8, Endian.little);
    writeTag(8, 'WAVE'); writeTag(12, 'fmt ');
    result.setUint32(16, 16, Endian.little);
    result.setUint16(20, 1, Endian.little);
    result.setUint16(22, 1, Endian.little);
    result.setUint32(24, 16000, Endian.little);
    result.setUint32(28, 32000, Endian.little);
    result.setUint16(32, 2, Endian.little);
    result.setUint16(34, 16, Endian.little);
    writeTag(36, 'data');
    result.setUint32(40, count * 2, Endian.little);
    for (var i = 0; i < count; i++) {
      final source = i * rate / 16000;
      final first = source.floor();
      final mix = source - first;
      final value = sampleAt(first) * (1 - mix) + sampleAt(first + 1) * mix;
      result.setInt16(44 + i * 2,
          (value * 32767).round().clamp(-32768, 32767).toInt(), Endian.little);
    }
    return output;
  }

  /// whisper-cli -ml 1 emits individual word-sized JSON timestamps (ms).
  static List<SpeechTimedWord> parseJson(String source, double sampleStart) {
    final payload = jsonDecode(source);
    if (payload is! Map || payload['transcription'] is! List) {
      throw const FormatException('Missing Whisper transcription');
    }
    final result = <SpeechTimedWord>[];
    for (final item in payload['transcription'] as List) {
      if (item is! Map || item['text'] is! String || item['offsets'] is! Map) {
        continue;
      }
      final offset = (item['offsets'] as Map)['from'];
      if (offset is! num || offset < 0 || offset > 60000) continue;
      for (final word in RegExp(r'[a-zA-Z0-9]+').allMatches(item['text'] as String)) {
        result.add(SpeechTimedWord(
          text: word.group(0)!, startSeconds: sampleStart + offset / 1000.0));
      }
    }
    return result.take(600).toList(growable: false);
  }

  /// Do not include exception.toString(): media URLs can embed access tokens.
  static String captureFailureReason(Object error) {
    if (error is TimeoutException) return 'timed out';
    if (error is FormatException) return 'invalid audio output';
    final message = error.toString();
    if (message.contains('decoder is missing')) return 'decoder not packaged';
    if (message.contains('no usable')) return 'empty audio';
    if (message.contains('exit')) return 'decoder could not read source';
    if (message.contains('PCM')) return 'PCM output unavailable';
    return 'source unreadable by decoder';
  }

  static Future<List<SpeechTimedWord>> transcribe({
    required String mediaUrl,
    required double startSeconds,
    required double durationSeconds,
    Map<String, String>? httpHeaders,
    int? audioTrackId,
  }) async {
    if (!Platform.isWindows) throw UnsupportedError('Windows only');
    final cli = executable();
    if (!await cli.exists()) {
      throw StateError('Offline Whisper executable is missing from Windows package');
    }
    final model = await _modelFile();
    if (!await hasModel()) throw StateError('Download the English model first');
    File? raw, wav, json;
    try {
      // On Windows prefer separately bundled FFmpeg: seekable Torrentio/MKV
      // audio often fails libmpv's PCM output despite normal movie playback.
      // If FFmpeg cannot read this particular stream, retry with mpv.
      try {
        raw = await FfmpegSpeechAudioCapture.capture(
          mediaUrl: mediaUrl, startSeconds: startSeconds,
          durationSeconds: durationSeconds, httpHeaders: httpHeaders,
        );
      } catch (ffmpegError) {
        try {
          raw = await MpvSpeechAudioCapture.capture(
            mediaUrl: mediaUrl, startSeconds: startSeconds,
            durationSeconds: durationSeconds, httpHeaders: httpHeaders,
            audioTrackId: audioTrackId,
          );
        } catch (mpvError) {
          throw WindowsSpeechSyncFailure(
            'could not extract stream audio (FFmpeg: '
            '${captureFailureReason(ffmpegError)}; mpv: '
            '${captureFailureReason(mpvError)}).',
          );
        }
      }
      if (raw.path.contains('playtorrio-ffmpeg-speech-')) {
        // FFmpeg produces whisper-ready 16 kHz/mono/16-bit WAV directly.
        wav = raw;
      } else {
        try {
          wav = File(raw.path + '.whisper.wav');
          await wav.writeAsBytes(
              whisperWave(await raw.readAsBytes()), flush: true);
        } on FormatException {
          throw const WindowsSpeechSyncFailure(
              'movie audio could not be converted to 16 kHz WAV.');
        }
      }
      final output = wav.path + '.result';
      json = File(output + '.json');
      Process process;
      try {
        process = await Process.start(cli.path, [
          '-m', model.path, '-f', wav.path, '-l', 'en', '-ml', '1',
          '-sow', '-oj', '-of', output, '-t', '4', '-np',
        ], workingDirectory: cli.parent.path);
      } on ProcessException {
        throw const WindowsSpeechSyncFailure(
            'Whisper executable could not start (Windows runtime issue).');
      }
      final out = process.stdout.drain<void>();
      final err = process.stderr.drain<void>();
      final exit = await process.exitCode.timeout(const Duration(minutes: 4),
        onTimeout: () {
          process.kill();
          throw const WindowsSpeechSyncFailure(
              'Whisper recognition timed out on this PC.');
        });
      await Future.wait([out, err]);
      if (exit != 0 || !await json.exists()) {
        throw WindowsSpeechSyncFailure(
          'Whisper could not recognize this clip (exit $exit).');
      }
      try {
        return parseJson(await json.readAsString(), startSeconds);
      } on FormatException {
        throw const WindowsSpeechSyncFailure(
            'Whisper returned an invalid transcript.');
      }
    } finally {
      for (final file in [raw, wav, json]) {
        try { if (file != null && await file.exists()) await file.delete(); }
        catch (_) {}
      }
    }
  }
}
