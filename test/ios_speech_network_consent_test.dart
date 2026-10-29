import 'package:flutter_test/flutter_test.dart';
import 'package:playtorrio/services/player/ios_speech_transcriber.dart';

void main() {
  test('Speech sample stays under Apple recognition one-minute limit', () {
    expect(IosSpeechTranscriber.maxSampleSeconds, lessThan(60));
    expect(IosSpeechTranscriber.maxSampleSeconds, 55);
  });

  test('Speech audio is never sent to Apple by default', () {
    final args = IosSpeechTranscriber.requestArguments(
      mediaUrl: 'file:///tmp/episode.mp4',
      startSeconds: 30,
      durationSeconds: 75,
    );
    expect(args['allowAppleNetworkRecognition'], isFalse);
    expect(args['startSeconds'], 30);
    expect(args['durationSeconds'], 75);
  });

  test('Online recognition requires an explicit true flag', () {
    final args = IosSpeechTranscriber.requestArguments(
      mediaUrl: 'file:///tmp/episode.mp4',
      startSeconds: 30,
      durationSeconds: 75,
      allowAppleNetworkRecognition: true,
    );
    expect(args['allowAppleNetworkRecognition'], isTrue);
  });

  test('Separate requests do not carry over network approval', () {
    IosSpeechTranscriber.requestArguments(
      mediaUrl: 'file:///tmp/movie.mp4',
      startSeconds: 0,
      durationSeconds: 60,
      allowAppleNetworkRecognition: true,
    );
    final next = IosSpeechTranscriber.requestArguments(
      mediaUrl: 'file:///tmp/other.mp4',
      startSeconds: 0,
      durationSeconds: 60,
    );
    expect(next['allowAppleNetworkRecognition'], isFalse);
  });
}
