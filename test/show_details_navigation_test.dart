import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:playtorrio/models/continue_watching/continue_watching_item.dart';
import 'package:playtorrio/services/continue_watching/continue_watching_service.dart';
import 'package:playtorrio/widgets/home/continue_watching_slider.dart';
import 'package:playtorrio/widgets/player/player_top_bar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('player has a labeled and working Show Details action',
      (tester) async {
    var opened = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PlayerTopBar(
          title: 'Example Series',
          subtitle: 'S1E3',
          onBack: () {},
          onShowDetails: () => opened++,
        ),
      ),
    ));
    expect(find.byKey(const ValueKey('player-show-details')), findsOneWidget);
    expect(find.text('Show Details'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('player-show-details')));
    expect(opened, 1);
  });

  testWidgets('player hides Show Details when no title ID is available',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: PlayerTopBar(title: 'Local file', onBack: () {})),
    ));
    expect(find.byKey(const ValueKey('player-show-details')), findsNothing);
  });

  testWidgets('Continue Watching displays Show Details without hover',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    ContinueWatchingService.activeItems.value = [
      ContinueWatchingItem(
        id: 'tt1111111',
        title: 'Example Series',
        type: 'series',
        season: 1,
        episode: 3,
        positionSeconds: 500,
        totalDurationSeconds: 2500,
        lastWatchedAt: DateTime.utc(2026, 10, 26),
        isTorrent: false,
      ),
    ];
    addTearDown(() => ContinueWatchingService.activeItems.value = []);
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: ContinueWatchingSlider()),
    ));
    expect(
      find.byKey(const ValueKey('continue-watching-details-tt1111111')),
      findsOneWidget,
    );
    expect(find.text('Show Details'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
