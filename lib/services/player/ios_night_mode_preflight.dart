import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:media_kit/media_kit.dart';

import 'ios_audio_telemetry.dart';
import 'player_picture_audio.dart';

/// Probe the *actual installed iOS libmpv* against generated PCM before
/// applying any new filter to the user's real media. The shipped Windows DLL
/// is NOT used on iOS. The iOS framework may omit individual FFmpeg filters.
///
/// Tries the existing compressor and a milder compand fallback. Both are
/// validated with native playback; neither is assumed present.
abstract final class IosNightModePreflight {
  static const String compand =
      'lavfi=[compand=attacks=0.02:decays=0.3:'
      'points=-80/-80|-20/-20|0/-13]';

  static String? _chosen;
  static bool _probed = false;
  static Future<String?>? _pending;
  static String? get selected => _probed ? _chosen : null;

  @visibleForTesting
  static void resetForTesting() {
    _chosen = null;
    _probed = false;
    _pending = null;
  }

  static Future<String?> ensure() {
    if (!Platform.isIOS) {
      return Future.value(PlayerPictureAudio.audioFilterChain(true));
    }
    if (_probed) return Future.value(_chosen);
    return _pending ??= _doProbe().then((result) {
      _chosen = result;
      _probed = true;
      return result;
    }).whenComplete(() => _pending = null);
  }

  static Future<String?> _doProbe() async {
    final sample = File('${Directory.systemTemp.path}/ptv-night-mode-probe.wav');
    try {
      await sample.writeAsBytes(_generateTone(), flush: true);
      for (final candidate in [
        PlayerPictureAudio.nightCompressor,
        compand,
      ]) {
        final filter = '${PlayerPictureAudio.normalAudioFilter},$candidate';
        final valid = await _tryFilter(sample, filter);
        if (valid) {
          IosAudioTelemetry.instance.captureCode(
              candidate == compand ? 'compand_supported' : 'acompressor_supported');
          return filter;
        }
      }
      IosAudioTelemetry.instance.captureCode('ios_filter_preflight_failed');
      return null;
    } catch (_) {
      IosAudioTelemetry.instance.captureCode('ios_filter_preflight_failed');
      return null;
    } finally {
      try {
        if (await sample.exists()) await sample.delete();
      } catch (_) {}
    }
  }

  /// 1.2s silent-generated 48 kHz mono PCM with rising amplitude, no user
  /// audio, stream URL, metadata or external network access.
  static Uint8List _generateTone() {
    const rate = 48000, frames = 57600;
    final data = ByteData(44 + frames * 2);
    void ascii(int offset, String value) {
      for (var i = 0; i < value.length; i++) {
        data.setUint8(offset + i, value.codeUnitAt(i));
      }
    }
    ascii(0, 'RIFF');
    data.setUint32(4, 36 + frames * 2, Endian.little);
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little);
    data.setUint16(22, 1, Endian.little);
    data.setUint32(24, rate, Endian.little);
    data.setUint32(28, rate * 2, Endian.little);
    data.setUint16(32, 2, Endian.little);
    data.setUint16(34, 16, Endian.little);
    ascii(36, 'data');
    data.setUint32(40, frames * 2, Endian.little);
    for (var i = 0; i < frames; i++) {
      final gain = i < frames ~/ 2 ? 0.1 : 0.75;
      data.setInt16(44 + i * 2,
          (math.sin(2 * math.pi * 440 * i / rate) * 32760 * gain).round(),
          Endian.little);
    }
    return data.buffer.asUint8List();
  }

  static Future<bool> _tryFilter(File sample, String filter) async {
    final player = Player(configuration: const PlayerConfiguration(
      logLevel: MPVLogLevel.debug,
    ));
    final finished = Completer<bool>();
    final subscriptions = <StreamSubscription<dynamic>>[];
    try {
      subscriptions.add(player.stream.error.listen((error) {
        IosAudioTelemetry.instance.captureNativeLog(error.toString());
        if (!finished.isCompleted) finished.complete(false);
      }));
      subscriptions.add(player.stream.log.listen((log) {
        IosAudioTelemetry.instance.captureNativeLog(log.text);
        if (PlayerPictureAudio.isNightModeFilterError(log.text) &&
            !finished.isCompleted) {
          finished.complete(false);
        }
      }));
      subscriptions.add(player.stream.completed.listen((value) {
        if (value && !finished.isCompleted) finished.complete(true);
      }));
      final dynamic native = player.platform;
      await player.setVolume(0);
      try {
        await native.setProperty('ao', 'null');
      } catch (_) {
        // Volume already muted; lack of null AO is not a filter failure.
      }
      await native.setProperty('audio-normalize-downmix', 'yes');
      await native.setProperty('af', filter);
      await player.open(Media(sample.path), play: true)
          .timeout(const Duration(seconds: 6));
      return await finished.future.timeout(
          const Duration(seconds: 9), onTimeout: () => false);
    } catch (_) {
      return false;
    } finally {
      for (final sub in subscriptions) {
        await sub.cancel();
      }
      await player.dispose();
    }
  }
}
