import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';

/// Media playback uses mpv, whose stream/codec support is broader than Apple's
/// AVAssetExportSession (notably torrent HTTP streams containing MKV audio).
/// This second, AUDIO-ONLY mpv instance exports PCM to a temporary WAV file.
/// The actual movie player is never paused, muted, or reconfigured.
class MpvSpeechAudioCapture {
  static const double maxDurationSeconds = 55;
  static const int maxWaveBytes = 96 * 1024 * 1024;

  static Future<File> capture({
    required String mediaUrl,
    required double startSeconds,
    required double durationSeconds,
    Map<String, String>? httpHeaders,
    int? audioTrackId,
  }) async {
    if (!Platform.isIOS) {
      throw UnsupportedError('mpv WAV speech capture is intended for iOS.');
    }
    if (mediaUrl.isEmpty || !startSeconds.isFinite || startSeconds < 0 ||
        !durationSeconds.isFinite || durationSeconds < 15 ||
        durationSeconds > maxDurationSeconds) {
      throw ArgumentError('Invalid spoken audio capture range.');
    }

    final root = await getTemporaryDirectory();
    final random = Random.secure();
    final filename = 'playtorrio-speech-${DateTime.now().microsecondsSinceEpoch}-${random.nextInt(1 << 32)}.wav';
    final wav = File('${root.path}/$filename');
    final decoder = Player();
    StreamSubscription<Duration>? positionListener;
    StreamSubscription<bool>? completionListener;
    StreamSubscription<String>? errorListener;
    final finished = Completer<Object?>();

    void completeOnce([Object? error]) {
      if (!finished.isCompleted) finished.complete(error);
    }

    var exported = false;
    try {
      // Set the output driver BEFORE opening media, and verify configuration.
      // Never fall back to an audible audio driver on this second player.
      final dynamic mpv = decoder.platform;
      if (mpv == null) {
        throw StateError('The mpv audio decoder is unavailable.');
      }
      await mpv.setProperty('ao', 'pcm');
      await mpv.setProperty('ao-pcm-file', wav.path);
      await mpv.setProperty('ao-pcm-waveheader', 'yes');
      await mpv.setProperty('ao-pcm-append', 'no');
      await mpv.setProperty('vid', 'no');
      await mpv.setProperty('sid', 'no');
      await mpv.setProperty('length', durationSeconds.toStringAsFixed(3));
      // Let the PCM output driver control pacing. Forcing untimed audio
      // playback can drop samples on some streams and spoil transcription.
      if (audioTrackId != null && audioTrackId > 0) {
        await mpv.setProperty('aid', '$audioTrackId');
      }
      final selected = (await mpv.getProperty('ao')).trim();
      if (selected != 'pcm') {
        throw StateError('The mpv PCM file-output driver is unavailable.');
      }

      final endSeconds = startSeconds + durationSeconds;
      positionListener = decoder.stream.position.listen((position) {
        final time = position.inMilliseconds / 1000.0;
        if (time >= endSeconds - 0.1) completeOnce();
      });
      completionListener = decoder.stream.completed.listen((done) {
        if (done) completeOnce();
      });
      errorListener = decoder.stream.error.listen((_) {
        completeOnce(StateError('The mpv audio decoder could not read this stream.'));
      });

      await decoder.open(
        Media(
          mediaUrl,
          start: Duration(milliseconds: (startSeconds * 1000).round()),
          end: Duration(milliseconds: (endSeconds * 1000).round()),
          httpHeaders: httpHeaders?.isEmpty == true ? null : httpHeaders,
        ),
        play: true,
      ).timeout(const Duration(seconds: 45));
      final result = await finished.future.timeout(
        const Duration(seconds: 85),
        onTimeout: () => throw TimeoutException(
          'Audio capture timed out. No subtitle timing was changed.',
        ),
      );
      if (result != null) throw result;
      exported = true;
    } catch (_) {
      // Do not log media URLs (torrent credentials, provider tokens or hashes).
      rethrow;
    } finally {
      await positionListener?.cancel();
      await completionListener?.cancel();
      await errorListener?.cancel();
      try {
        await decoder.stop();
      } catch (_) {}
      try {
        await decoder.dispose();
      } catch (_) {}
      // Stop/close flushes the RIFF length and PCM data to disk.
      if (!exported) {
        try {
          if (await wav.exists()) await wav.delete();
        } catch (_) {}
      }
    }

    try {
      final bytes = await wav.length();
      if (bytes < 65536 || bytes > maxWaveBytes ||
          !isWaveHeader(await _readHeader(wav))) {
        throw const FormatException('MPV did not produce a usable WAV excerpt.');
      }
      return wav;
    } catch (_) {
      try {
        if (await wav.exists()) await wav.delete();
      } catch (_) {}
      rethrow;
    }
  }

  static Future<Uint8List> _readHeader(File file) async {
    final stream = file.openRead(0, 12);
    final result = BytesBuilder(copy: false);
    await for (final chunk in stream) {
      result.add(chunk);
    }
    return result.takeBytes();
  }

  /// Fail closed: never pass an empty, raw PCM or HTML response to Speech.
  static bool isWaveHeader(List<int> bytes) {
    if (bytes.length < 12) return false;
    const riff = [0x52, 0x49, 0x46, 0x46]; // RIFF
    const wave = [0x57, 0x41, 0x56, 0x45]; // WAVE
    for (var i = 0; i < 4; i++) {
      if (bytes[i] != riff[i] || bytes[i + 8] != wave[i]) return false;
    }
    return true;
  }
}
