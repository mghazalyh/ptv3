import 'dart:io';

import 'package:flutter/services.dart';

import 'speech_subtitle_alignment.dart';

/// English speech recognition of a short video-audio excerpt on iOS 15+.
/// On-device is always preferred. If unsupported, a network request to
/// Apple's speech service requires a separate user approval for each attempt.
/// No microphone capture, local transcript persistence, or app-operated server.
abstract final class IosSpeechTranscriber {
  static const MethodChannel _channel =
      MethodChannel('playtorrio/speech_subtitle_sync');

  static Future<List<SpeechTimedWord>> transcribe({
    required String mediaUrl,
    required double startSeconds,
    required double durationSeconds,
    bool allowAppleNetworkRecognition = false,
  }) async {
    if (!Platform.isIOS) {
      throw UnsupportedError('Spoken-audio subtitle alignment requires iOS.');
    }
    if (mediaUrl.trim().isEmpty || !startSeconds.isFinite ||
        !durationSeconds.isFinite || startSeconds < 0 ||
        durationSeconds < 15 || durationSeconds > 80) {
      throw ArgumentError('No valid media audio excerpt is available.');
    }

    final response = await _channel.invokeMapMethod<String, dynamic>(
      'transcribeExcerpt',
      <String, dynamic>{
        'mediaUrl': mediaUrl,
        'startSeconds': startSeconds,
        'durationSeconds': durationSeconds,
        'allowAppleNetworkRecognition': allowAppleNetworkRecognition,
      },
    ).timeout(const Duration(seconds: 115));

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
