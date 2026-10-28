import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playtorrio/models/player/skip_segment_model.dart';
import 'package:playtorrio/services/player/automatic_skip_policy.dart';
import 'package:playtorrio/widgets/player/player_skip_button.dart';

void main() {
  const intro = MediaSkipSegment(type: 'intro', startMs: 15000, endMs: 96000);
  const credits = MediaSkipSegment(type: 'credits', startMs: 2460000);
  const duration = Duration(minutes: 44);

  test('auto-skip only actual TV intro/credits with safe boundaries', () {
    expect(AutomaticSkipPolicy.eligible(
        isSeriesEpisode: true, segment: intro, mediaDuration: duration), isTrue);
    expect(AutomaticSkipPolicy.eligible(
        isSeriesEpisode: true, segment: credits, mediaDuration: duration), isTrue);
    expect(AutomaticSkipPolicy.eligible(
        isSeriesEpisode: false, segment: intro, mediaDuration: duration), isFalse);
    expect(AutomaticSkipPolicy.eligible(isSeriesEpisode: true,
        segment: const MediaSkipSegment(type: 'recap',
            startMs: 1000, endMs: 2500), mediaDuration: duration), isFalse);
    expect(AutomaticSkipPolicy.eligible(isSeriesEpisode: true,
        segment: const MediaSkipSegment(type: 'preview',
            startMs: 1000, endMs: 2500), mediaDuration: duration), isFalse);
    expect(AutomaticSkipPolicy.countdown, const Duration(seconds: 3));
  });

  test('never guess skip target for absent, invalid or oversized timestamps', () {
    expect(AutomaticSkipPolicy.eligible(isSeriesEpisode: true,
        segment: const MediaSkipSegment(type: 'intro', startMs: 12000),
        mediaDuration: duration), isFalse);
    expect(AutomaticSkipPolicy.eligible(isSeriesEpisode: true,
        segment: const MediaSkipSegment(type: 'intro', endMs: 12000),
        mediaDuration: duration), isFalse);
    expect(AutomaticSkipPolicy.eligible(isSeriesEpisode: true,
        segment: const MediaSkipSegment(type: 'intro',
            startMs: 12000, endMs: 10000),
        mediaDuration: duration), isFalse);
    expect(AutomaticSkipPolicy.eligible(isSeriesEpisode: true,
        segment: const MediaSkipSegment(type: 'credits', startMs: 2500000),
        mediaDuration: Duration.zero), isFalse);
    expect(AutomaticSkipPolicy.eligible(isSeriesEpisode: true,
        segment: const MediaSkipSegment(type: 'intro',
            startMs: 15000, endMs: 5000000),
        mediaDuration: duration), isFalse);
    expect(AutomaticSkipPolicy.eligible(isSeriesEpisode: true,
        segment: const MediaSkipSegment(type: 'credits', startMs: 3000000),
        mediaDuration: duration), isFalse);
    expect(AutomaticSkipPolicy.destination(credits, duration), duration);
    expect(AutomaticSkipPolicy.destination(intro, duration),
        const Duration(seconds: 96));
  });

  testWidgets('TV intro auto-skips after 3s if not cancelled', (tester) async {
    var skips = 0;
    var cancels = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(
      child: PlayerSkipButton(
        segment: intro,
        autoSkip: true,
        onSkip: () => skips++,
        onDismiss: () => cancels++,
      ),
    ))));
    expect(find.text('Skipping Intro in 3s'), findsOneWidget);
    // Flutter starts a new ticker at its first frame, not at pumpWidget.
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(skips, 0);
    await tester.pump(const Duration(milliseconds: 1020));
    expect(skips, 1);
    expect(cancels, 0);
  });

  testWidgets('3-second cancel prevents auto-skip for current segment',
      (tester) async {
    var skips = 0;
    var cancels = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(
      child: PlayerSkipButton(
        segment: credits,
        autoSkip: true,
        onSkip: () => skips++,
        onDismiss: () => cancels++,
      ),
    ))));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(cancels, 1);
    // Parent clears this overlay on cancel, as PlayerScreen does.
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    await tester.pump(const Duration(seconds: 4));
    expect(skips, 0);
  });

  testWidgets('auto-skip countdown does not advance while paused',
      (tester) async {
    var skips = 0;
    Widget view(bool playing) => MaterialApp(home: Scaffold(body: Center(
      child: PlayerSkipButton(
        segment: intro,
        autoSkip: true,
        isPlaying: playing,
        onSkip: () => skips++,
        onDismiss: () {},
      ),
    )));
    await tester.pumpWidget(view(true));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(view(false));
    await tester.pump(const Duration(seconds: 5));
    expect(skips, 0);
    await tester.pumpWidget(view(true));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2020));
    expect(skips, 1);
  });

  testWidgets('recap keeps existing manual dismiss behavior', (tester) async {
    var skips = 0;
    var cancels = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(
      child: PlayerSkipButton(
        segment: const MediaSkipSegment(
            type: 'recap', startMs: 1000, endMs: 10000),
        onSkip: () => skips++,
        onDismiss: () => cancels++,
      ),
    ))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 5020));
    expect(skips, 0);
    expect(cancels, 1);
  });
}
