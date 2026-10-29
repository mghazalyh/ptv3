import 'package:flutter_test/flutter_test.dart';
import 'package:playtorrio/services/player/mpv_speech_audio_capture.dart';
import 'package:playtorrio/services/player/ios_speech_transcriber.dart';

void main() {
  test('only accepts RIFF/WAVE audio, not a failed HTTP/HTML stream', () {
    expect(MpvSpeechAudioCapture.isWaveHeader(
      [82, 73, 70, 70, 0, 0, 0, 0, 87, 65, 86, 69]), isTrue);
    expect(MpvSpeechAudioCapture.isWaveHeader(
      '<html>404 denied</html>'.codeUnits), isFalse);
    expect(MpvSpeechAudioCapture.isWaveHeader(
      [0, 0, 0, 0, 0x66, 0x74, 0x79, 0x70, 0, 0, 0, 0]), isFalse);
    expect(MpvSpeechAudioCapture.isWaveHeader([82, 73, 70]), isFalse);
  });

  test('stream decoder may not capture more than one-minute Speech limit', () {
    expect(MpvSpeechAudioCapture.maxDurationSeconds, 55);
    expect(MpvSpeechAudioCapture.maxDurationSeconds,
        IosSpeechTranscriber.maxSampleSeconds);
    expect(MpvSpeechAudioCapture.maxWaveBytes, lessThan(100 * 1024 * 1024));
  });

  test('native speech receives only explicit app-private WAV path', () {
    final args = IosSpeechTranscriber.requestArguments(
      mediaUrl: 'http://127.0.0.1:8090/stream?link=redacted',
      startSeconds: 15,
      durationSeconds: 40,
      audioFilePath: '/tmp/playtorrio-speech-test.wav',
    );
    expect(args['audioFilePath'], '/tmp/playtorrio-speech-test.wav');
    expect(args['allowAppleNetworkRecognition'], isFalse);
    expect(args['durationSeconds'], 40);
  });

  test('no duplicate decoder file path in ordinary speech recognition', () {
    final args = IosSpeechTranscriber.requestArguments(
      mediaUrl: 'https://example.test/movie.mp4',
      startSeconds: 60,
      durationSeconds: 45,
    );
    expect(args.containsKey('audioFilePath'), isFalse);
    expect(args['allowAppleNetworkRecognition'], isFalse);
  });
}
