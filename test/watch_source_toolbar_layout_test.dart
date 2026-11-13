import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playtorrio/pages/player/watch_screen.dart';

void main() {
  Future<void> renderToolbar(WidgetTester tester, double width) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: WatchSourceFilterToolbar(
              sizeFilter: const SizedBox(
                key: ValueKey('size-button'),
                width: 142,
                height: 36,
                child: Center(child: Text('All Sizes')),
              ),
              addonFilter: const SizedBox(
                key: ValueKey('addon-button'),
                width: 176,
                height: 36,
                child: Center(child: Text('All Sources')),
              ),
              preferencesButton: const SizedBox(
                key: ValueKey('preferences-button'),
                width: 48,
                height: 36,
                child: Icon(Icons.tune),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();

    expect(tester.takeException(), isNull);
    for (final key in const [
      ValueKey('size-button'),
      ValueKey('addon-button'),
      ValueKey('preferences-button'),
    ]) {
      final rect = tester.getRect(find.byKey(key));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(width + 0.1));
    }
  }

  testWidgets('All Sources wraps inside narrow iPad-side panel', (tester) async {
    await renderToolbar(tester, 260);
    final firstRow = tester.getTopLeft(find.byKey(const ValueKey('size-button')));
    final addonRow = tester.getTopLeft(find.byKey(const ValueKey('addon-button')));
    expect(addonRow.dy, greaterThan(firstRow.dy));
  });

  testWidgets('all filter controls remain visible at wider widths', (tester) async {
    await renderToolbar(tester, 440);
    expect(find.text('All Sources'), findsOneWidget);
    expect(find.text('All Sizes'), findsOneWidget);
  });
}
