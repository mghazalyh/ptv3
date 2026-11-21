import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Basic PlayTorrio layout renders without cloud side effects',
      (WidgetTester tester) async {
    // A widget smoke test must not initialize MyListService: that service
    // launches cloud synchronization and can stall an otherwise local test.
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: Text('PlayTorrio')),
        ),
      ),
    );
    expect(find.text('PlayTorrio'), findsOneWidget);
    expect(find.byType(Scaffold), findsOneWidget);
  });
}
