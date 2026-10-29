import 'package:flutter_test/flutter_test.dart';
import 'package:playtorrio/services/player/speech_subtitle_alignment.dart';
import 'package:playtorrio/services/subtitles/subtitle_parser.dart';

void main() {
  const firstLine = 'We should probably leave this place now';
  const secondLine = 'I think we are already much too late';
  const thirdLine = 'Everyone deserves to know what happened here';

  List<SpeechTimedWord> spoken(
      String text, double phraseStart) {
    final tokens = SpeechSubtitleAlignment.normalize(text);
    return <SpeechTimedWord>[
      for (var i = 0; i < tokens.length; i++)
        SpeechTimedWord(
            text: tokens[i], startSeconds: phraseStart + i * 0.27),
    ];
  }

  List<SubCue> cues() => const [
        SubCue(start: 10, end: 13, text: firstLine),
        SubCue(start: 30, end: 33, text: secondLine),
        SubCue(start: 56, end: 60, text: thirdLine),
      ];

  test('matches real spoken phrases and moves delayed subtitles later', () {
    final result = SpeechSubtitleAlignment.estimate(
      cues: cues(),
      speech: [
        ...spoken(firstLine, 14.0),
        ...spoken(secondLine, 34.1),
        ...spoken(thirdLine, 60.05),
      ],
      sampleStartSeconds: 0,
      sampleEndSeconds: 78,
    );
    expect(result, isNotNull);
    expect(result!.supportingCues, 3);
    expect(result.delaySeconds, closeTo(4.05, 0.15));
  });

  test('recognizes subtitles that must appear earlier', () {
    final result = SpeechSubtitleAlignment.estimate(
      cues: cues(),
      speech: [
        ...spoken(firstLine, 4),
        ...spoken(secondLine, 24.1),
        ...spoken(thirdLine, 50.0),
      ],
      sampleStartSeconds: 0,
      sampleEndSeconds: 78,
    );
    expect(result, isNotNull);
    expect(result!.delaySeconds, closeTo(-6, 0.15));
  });

  test('rejects a single coincidental matching subtitle line', () {
    final result = SpeechSubtitleAlignment.estimate(
      cues: cues(),
      speech: [
        ...spoken(firstLine, 14),
        ...spoken('Sometimes all the people just want to go home', 44),
        ...spoken('Many other things have happened just today', 56),
      ],
      sampleStartSeconds: 0,
      sampleEndSeconds: 78,
    );
    expect(result, isNull);
  });

  test('rejects contradictory offsets instead of seeking by guess', () {
    final result = SpeechSubtitleAlignment.estimate(
      cues: cues(),
      speech: [
        ...spoken(firstLine, 16),
        ...spoken(secondLine, 23),
        ...spoken(thirdLine, 67),
      ],
      sampleStartSeconds: 0,
      sampleEndSeconds: 85,
    );
    expect(result, isNull);
  });

  test('does not make up timing from silent or unrelated audio', () {
    final result = SpeechSubtitleAlignment.estimate(
      cues: cues(),
      speech: [
        ...spoken('This is clearly a completely different episode now', 12),
        ...spoken('No one knows where the others could have gone', 42),
      ],
      sampleStartSeconds: 0,
      sampleEndSeconds: 80,
    );
    expect(result, isNull);
  });

  test('matches a shorter prefix when ASR mistranscribes later words', () {
    final result = SpeechSubtitleAlignment.estimate(
      cues: cues(),
      speech: [
        ...spoken('We should probably leave this city right now', 14),
        ...spoken(secondLine, 34),
        ...spoken('Everyone deserves to know what different story', 60),
      ],
      sampleStartSeconds: 0,
      sampleEndSeconds: 80,
    );
    expect(result, isNotNull);
    expect(result!.delaySeconds, closeTo(4, 0.15));
  });

  test('rejects impossible offsets beyond the bounded range', () {
    final result = SpeechSubtitleAlignment.estimate(
      cues: cues(),
      speech: [
        ...spoken(firstLine, 200),
        ...spoken(secondLine, 220),
        ...spoken(thirdLine, 246),
      ],
      sampleStartSeconds: 175,
      sampleEndSeconds: 250,
    );
    expect(result, isNull);
  });

  test('strips punctuation and style markup before comparison', () {
    expect(SpeechSubtitleAlignment.normalize(
      '<i>Hello</i>, [my] dear friend!'),
      ['hello', 'my', 'dear', 'friend']);
  });
}
