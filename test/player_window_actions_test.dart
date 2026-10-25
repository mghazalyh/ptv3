import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:playtorrio/widgets/player/player_window_actions.dart';

void main() {
  testWidgets('Windows playback actions are visible, labeled and clickable',
      (tester) async {
    var detached = 0;
    var minimized = 0;
    var stopped = 0;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: PlayerWindowActions(
            onSeparateWindow: () => detached++,
            onMinimize: () => minimized++,
            onStop: () => stopped++,
          ),
        ),
      ),
    ));

    expect(find.byKey(const Key('player-window-actions')), findsOneWidget);
    expect(find.text('Separate window'), findsOneWidget);
    expect(find.text('Mini player'), findsOneWidget);
    expect(find.text('Stop'), findsOneWidget);

    await tester.tap(find.byKey(const Key('player-separate-window')));
    await tester.pump();
    expect(detached, 1);

    await tester.tap(find.byKey(const Key('player-mini-player')));
    await tester.pump();
    expect(minimized, 1);

    await tester.tap(find.byKey(const Key('player-stop')));
    await tester.pump();
    expect(stopped, 1);
  });

  testWidgets('Separate window is visible but disabled during handoff',
      (tester) async {
    var detached = 0;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: PlayerWindowActions(
            openingSeparateWindow: true,
            onSeparateWindow: () => detached++,
            onMinimize: () {},
            onStop: () {},
          ),
        ),
      ),
    ));

    final separate = tester.widget<TextButton>(
      find.byKey(const Key('player-separate-window')),
    );
    expect(separate.onPressed, isNull);
    expect(find.text('Separate window'), findsOneWidget);
    expect(detached, 0);
  });

  testWidgets('Compact actions still provide all three controls',
      (tester) async {
    var opened = false;
    var minimized = false;
    var stopped = false;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: PlayerWindowActions(
            compact: true,
            onSeparateWindow: () => opened = true,
            onMinimize: () => minimized = true,
            onStop: () => stopped = true,
          ),
        ),
      ),
    ));

    expect(find.byKey(const Key('player-separate-window')), findsOneWidget);
    expect(find.byKey(const Key('player-mini-player')), findsOneWidget);
    expect(find.byKey(const Key('player-stop')), findsOneWidget);

    await tester.tap(find.byKey(const Key('player-separate-window')));
    await tester.tap(find.byKey(const Key('player-mini-player')));
    await tester.tap(find.byKey(const Key('player-stop')));

    expect(opened, isTrue);
    expect(minimized, isTrue);
    expect(stopped, isTrue);
  });

  testWidgets('Standalone secondary viewer exposes all 3 functional controls',
      (tester) async {
    var stopped = false;
    var madeMovable = false;
    var miniWindow = false;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: PlayerWindowActions(
            separateWindowActive: true,
            onSeparateWindow: () => madeMovable = true,
            onMinimize: () => miniWindow = true,
            onStop: () => stopped = true,
          ),
        ),
      ),
    ));

    expect(find.byKey(const Key('player-separate-window')), findsOneWidget);
    expect(find.byKey(const Key('player-mini-player')), findsOneWidget);
    expect(find.byKey(const Key('player-stop')), findsOneWidget);
    await tester.tap(find.byKey(const Key('player-separate-window')));
    await tester.tap(find.byKey(const Key('player-mini-player')));
    await tester.tap(find.byKey(const Key('player-stop')));
    expect(madeMovable, isTrue);
    expect(miniWindow, isTrue);
    expect(stopped, isTrue);
  });
}
