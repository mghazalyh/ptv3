import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playtorrio/services/player/live_tv/live_signal_health.dart';
import 'package:playtorrio/services/player/player_diagnostic_codes.dart';
import 'package:playtorrio/widgets/player/live_tv_overlay.dart';

void main() {
  LiveSignalSnapshot signal({
    required bool hasPlayed,
    bool recovering = false,
    bool buffering = false,
    bool playing = true,
    int attempts = 0,
    int position = 10,
    int bufferEnd = 30,
    int feedAge = 1,
  }) => LiveSignalSnapshot.evaluate(
    hasPlayed: hasPlayed,
    reconnecting: recovering,
    buffering: buffering,
    playing: playing,
    attempts: attempts,
    position: Duration(seconds: position),
    bufferEnd: Duration(seconds: bufferEnd),
    feedAge: Duration(seconds: feedAge),
  );

  group('Live stream health indicator', () {
    test('no video frames means connecting, not strong', () {
      expect(signal(hasPlayed: false).level, LiveSignalLevel.connecting);
      expect(signal(hasPlayed: false).isConnecting, isTrue);
    });

    test('healthy buffer is strong only after playback is verified', () {
      final result = signal(hasPlayed: true);
      expect(result.level, LiveSignalLevel.strong);
      expect(result.isPlayable, isTrue);
    });

    test('shrinking buffer warns before a stall', () {
      expect(signal(hasPlayed: true, bufferEnd: 19).level,
          LiveSignalLevel.unstable);
      expect(signal(hasPlayed: true, bufferEnd: 14).level,
          LiveSignalLevel.critical);
      expect(signal(hasPlayed: true, buffering: true).level,
          LiveSignalLevel.critical);
    });

    test('long feed inactivity warns even if the time buffer is nonzero', () {
      expect(signal(hasPlayed: true, feedAge: 11, bufferEnd: 17).level,
          LiveSignalLevel.critical);
    });

    test('repeated unverified connections show unavailable state', () {
      final bad = signal(hasPlayed: false, recovering: true, attempts: 5);
      expect(bad.level, LiveSignalLevel.unavailable);
      expect(bad.isConnecting, isTrue);
    });

    test('a native open alone never verifies playback', () {
      expect(LivePlaybackAcceptance.confirmed(
        before: Duration.zero, after: Duration.zero,
        playing: true, buffering: false,
      ), isFalse);
      expect(LivePlaybackAcceptance.confirmed(
        before: Duration.zero, after: const Duration(seconds: 2),
        playing: true, buffering: true,
      ), isFalse);
      expect(LivePlaybackAcceptance.confirmed(
        before: Duration.zero, after: const Duration(seconds: 2),
        playing: true, buffering: false,
      ), isTrue);
    });

    test('initial startup stall selects backups on first attempt', () {
      expect(LivePlaybackAcceptance.shouldAttemptBackup(
        attempts: 1, hasConfirmedPlayback: false,
      ), isTrue);
      expect(LivePlaybackAcceptance.shouldAttemptBackup(
        attempts: 1, hasConfirmedPlayback: true,
      ), isFalse);
      expect(LivePlaybackAcceptance.shouldAttemptBackup(
        attempts: 2, hasConfirmedPlayback: true,
      ), isTrue);
    });

    test('opt-in private telemetry has fixed live event vocabulary', () {
      expect(PlayerDiagnosticCodes.events.contains('live_first_frame_confirmed'),
          isTrue);
      expect(PlayerDiagnosticCodes.events.contains('live_no_backup_available'),
          isTrue);
      expect(PlayerDiagnosticCodes.events.contains('live_startup_unverified'),
          isTrue);
    });
  });

  group('Live TV quality-of-life widgets', () {
    testWidgets('signal badge announces connection health', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: LiveTvSignalBadge(
          snapshot: signal(hasPlayed: true),
        )),
      ));
      expect(find.text('Strong'), findsOneWidget);
      expect(find.byType(LiveTvSignalBadge), findsOneWidget);
    });

    testWidgets('initial channel load uses an honest indeterminate progress bar',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: LiveTvLoadingOverlay(
          channelTitle: 'Pluto TV Drama',
          message: 'Connecting to live channel...',
          snapshot: signal(hasPlayed: false),
        )),
      ));
      expect(find.text('Pluto TV Drama'), findsOneWidget);
      expect(find.text('Connecting to live channel...'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      final bar = tester.widget<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator));
      expect(bar.value, isNull);
    });

    testWidgets('unavailable channel shows an actionable failure state',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: LiveTvLoadingOverlay(
          channelTitle: 'Paramount+ Picks',
          message: 'Live stream unavailable. Retrying...',
          snapshot: signal(hasPlayed: false, recovering: true, attempts: 5),
        )),
      ));
      expect(find.textContaining('not delivered video'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });
  });
}
