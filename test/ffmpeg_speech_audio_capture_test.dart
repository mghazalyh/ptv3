import 'package:flutter_test/flutter_test.dart';
import 'package:playtorrio/services/player/ffmpeg_speech_audio_capture.dart';
import 'package:playtorrio/services/player/windows_whisper_transcriber.dart';

void main() {
  test('Windows FFmpeg seeks and produces Whisper 16-kHz mono PCM without mic', () {
    final args = FfmpegSpeechAudioCapture.arguments(
      mediaUrl: 'http://127.0.0.1:8090/video.mkv',
      startSeconds: 1412.5,
      durationSeconds: 55,
      outputPath: r'C:\Temp\test.wav',
    );
    expect(args.indexOf('-ss'), lessThan(args.indexOf('-i')));
    expect(args[args.indexOf('-ss') + 1], '1412.500');
    expect(args[args.indexOf('-i') + 1], 'http://127.0.0.1:8090/video.mkv');
    expect(args[args.indexOf('-t') + 1], '55.000');
    expect(args.sublist(args.indexOf('-map') + 1), contains('0:a:0'));
    expect(args, containsAll(['-ac', '1', '-ar', '16000',
      '-c:a', 'pcm_s16le', '-f', 'wav']));
    expect(args, isNot(contains('microphone')));
  });

  test('HTTP stream headers accepted only without CRLF injection', () {
    final args = FfmpegSpeechAudioCapture.arguments(
      mediaUrl: 'https://provider.invalid/stream.mkv',
      startSeconds: 60, durationSeconds: 30,
      outputPath: r'C:\Temp\speech.wav',
      httpHeaders: {'Authorization': 'Bearer hidden-secret'},
    );
    expect(args[args.indexOf('-headers') + 1],
        contains('Authorization: Bearer hidden-secret\r\n'));
    expect(() => FfmpegSpeechAudioCapture.arguments(
      mediaUrl: 'https://provider.invalid/stream',
      startSeconds: 60, durationSeconds: 30, outputPath: 'speech.wav',
      httpHeaders: {'Authorization': 'Bearer x\r\nInjected: y'},
    ), throwsFormatException);
  });

  test('Capture is bounded and source failures are reported without leaking URLs', () {
    expect(() => FfmpegSpeechAudioCapture.arguments(
      mediaUrl: 'test.mkv', startSeconds: 10, durationSeconds: 56,
      outputPath: 'speech.wav'), throwsFormatException);
    expect(WindowsWhisperTranscriber.captureFailureReason(
        StateError('https://provider.invalid/secret?key=private')),
        'source unreadable by decoder');
    expect(WindowsWhisperTranscriber.captureFailureReason(
        StateError('FFmpeg could not decode movie audio (exit 1)')),
        'decoder could not read source');
  });
}
