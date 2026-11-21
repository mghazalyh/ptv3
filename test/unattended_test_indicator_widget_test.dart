import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playtorrio/services/remote/unattended_test_activity.dart';
import 'package:playtorrio/widgets/remote/unattended_test_indicator.dart';

void main() {
  testWidgets('Indicator appears and updates without blocking underlying taps',
      (tester) async {
    var presses = 0;
    final notifier = ValueNotifier<UnattendedTestSnapshot>(
        const UnattendedTestSnapshot());
    addTearDown(notifier.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Stack(children: [
          Positioned.fill(child: ElevatedButton(
            onPressed: () => presses++,
            child: const Text('Player controls'),
          )),
          Positioned(top: 0, left: 0, right: 0,
            child: UnattendedTestIndicator(activity: notifier)),
        ]),
      ),
    ));
    expect(find.text('LIVE TV TEST RUNNING'), findsNothing);
    notifier.value = const UnattendedTestSnapshot(
      phase: 'running', runId: 'trial',
      channelsDone: 20, totalChannels: 150,
      sourcesDone: 47, sustainedPlaybackSessions: 13,
    );
    await tester.pump();
    expect(find.text('LIVE TV TEST RUNNING'), findsOneWidget);
    expect(find.text('20 / 150'), findsOneWidget);
    await tester.tap(find.text('Player controls'));
    expect(presses, 1);
    notifier.value = const UnattendedTestSnapshot(
      phase: 'completed', channelsDone: 150, totalChannels: 150,
    );
    await tester.pump();
    expect(find.text('LIVE TV TEST RUNNING'), findsNothing);
  });

  testWidgets('Native decoder test has its own truthful label',
      (tester) async {
    final notifier = ValueNotifier<UnattendedTestSnapshot>(
      const UnattendedTestSnapshot(phase: 'running', runId: 'nltv:Test'),
    );
    addTearDown(notifier.dispose);
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: UnattendedTestIndicator(activity: notifier),
    )));
    expect(find.text('NATIVE SOURCE TEST RUNNING'), findsOneWidget);
    expect(find.text('0 / 0'), findsNothing);
  });

  testWidgets('Cancel requested is labelled stopping, not completed',
      (tester) async {
    final notifier = ValueNotifier<UnattendedTestSnapshot>(
      const UnattendedTestSnapshot(
        phase: 'running', cancelRequested: true,
        channelsDone: 7, totalChannels: 50,
      ),
    );
    addTearDown(notifier.dispose);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body:
      UnattendedTestIndicator(activity: notifier))));
    expect(find.text('STOPPING LIVE TV TEST'), findsOneWidget);
    expect(find.text('7 / 50'), findsOneWidget);
  });
}
