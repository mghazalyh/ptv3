import 'dart:io';
import 'dart:async';

import 'package:flutter/services.dart';

import 'speech_subtitle_alignment.dart';
import 'mpv_speech_audio_capture.dart';

/// English speech recognition of a short video-audio excerpt on iOS 15+.
/// On-device is always preferred. If unsupported, a network request to
/// Apple's speech service requires a separate user approval for each attempt.
/// No microphone capture, local transcript persistence, or app-operated server.
abstract final class IosSpeechTranscriber {
  // Apple Speech recognition limits tasks to about 60 seconds.
  static const double maxSampleSeconds = 55.0;

  static const MethodChannel _channel =
      MethodChannel('playtorrio/speech_subtitle_sync');

  /// Network processing is NEVER authorized by default. The player must
  /// obtain explicit consent before passing [allowAppleNetworkRecognition].
  static Map<String, dynamic> requestArguments({
    required String mediaUrl,
    required double startSeconds,
    required double durationSeconds,
    bool allowAppleNetworkRecognition = false,
    String? audioFilePath,
  }) => <String, dynamic>{
    'mediaUrl': mediaUrl,
    'startSeconds': startSeconds,
    'durationSeconds': durationSeconds,
    'allowAppleNetworkRecognition': allowAppleNetworkRecognition,
    if (audioFilePath != null) 'audioFilePath': audioFilePath,
  };

  static Future<List<SpeechTimedWord>> transcribe({
    required String mediaUrl,
    required double startSeconds,
    required double durationSeconds,
    bool allowAppleNetworkRecognition = false,
    Map<String, String>? httpHeaders,
    int? audioTrackId,
    void Function()? onPlaybackDecoderFallback,
  }) async {
    if (!Platform.isIOS) {
      throw UnsupportedError('Spoken-audio subtitle alignment requires iOS.');
    }
    if (mediaUrl.trim().isEmpty || !startSeconds.isFinite ||
        !durationSeconds.isFinite || startSeconds < 0 ||
        durationSeconds < 15 || durationSeconds > maxSampleSeconds) {
      throw ArgumentError('No valid media audio excerpt is available.');
    }

    Future<Map<String, dynamic>?> recognize({String? audioFilePath}) =>
        _channel.invokeMapMethod<String, dynamic>(
          'transcribeExcerpt',
          requestArguments(
            mediaUrl: mediaUrl,
            startSeconds: startSeconds,
            durationSeconds: durationSeconds,
            allowAppleNetworkRecognition: allowAppleNetworkRecognition,
            audioFilePath: audioFilePath,
          ),
        ).timeout(const Duration(seconds: 115));

    Map<String, dynamic>? response;
    try {
      // Fast path for directly supported MP4/HLS/local formats.
      response = await recognize();
    } on PlatformException catch (error) {
      if (error.code != 'audio_extract_failed' &&
          error.code != 'unsupported_media') rethrow;

      onPlaybackDecoderFallback?.call();

      // AVFoundation cannot demux every stream libmpv is already playing
      // (e.g. MKV delivered by local torrent HTTP servers). Decode a bounded
      // audio-only excerpt with a separate mpv instance and feed that WAV
      // directly to the very same iOS Speech framework.
      File wav;
      try {
        wav = await MpvSpeechAudioCapture.capture(
          mediaUrl: mediaUrl,
          startSeconds: startSeconds,
          durationSeconds: durationSeconds,
          httpHeaders: httpHeaders,
          audioTrackId: audioTrackId,
        );
      } catch (exception) {
        throw PlatformException(
          code: 'decoder_audio_extract_failed',
          message: exception is TimeoutException
              ? 'Audio extraction timed out. The stream may not support seeking.'
              : 'This stream can play, but its audio cannot be exported by the '
                  'installed decoder. Speech sync cannot run on this source.',
        );
      }
      try {
        response = await recognize(audioFilePath: wav.path);
      } finally {
        try {
          if (await wav.exists()) await wav.delete();
        } catch (_) {}
      }
    }

    final raw = response?['words'];
    if (raw is! List) {
      throw const FormatException('Speech recognizer did not provide timed words');
    }
    return raw.whereType<Map>().map((item) {
      final text = item['text'];
      final start = item['startSeconds'];
      if (text is! String || start is! num ||
          !start.toDouble().isFinite) return null;
      return SpeechTimedWord(
        text: text,
        startSeconds: start.toDouble(),
      );
    }).whereType<SpeechTimedWord>().take(600).toList(growable: false);
  }
}
