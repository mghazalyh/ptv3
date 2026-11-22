import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playtorrio/widgets/remote/torriodb_live_overlay.dart';

void main() {
  final store = TorriodbLiveOverlayStore.instance;

  tearDown(() => store.apply(null));

  Map<String, dynamic> config({String action = 'adaptive_stop'}) =>
      <String, dynamic>{
        'schema': 1,
        'enabled': true,
        'panels': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'owner-surf-controls',
            'anchor': 'bottomRight',
            'when': 'always',
            'width': 280,
            'margin': 12,
            'background': '#E0161B2E',
            'items': <Map<String, dynamic>>[
              <String, dynamic>{
                'type': 'text',
                'text': 'Adaptive Live TV',
                'bold': true,
              },
              <String, dynamic>{
                'type': 'button',
                'label': 'STOP SURFING',
                'action': action,
                'args': <String, dynamic>{},
              },
            ],
          }
        ],
      };

  test('allows owner-specified overlay controls and layouts', () {
    expect(TorriodbLiveOverlayStore.isValid(config()), isTrue);
    final nested = config();
    (nested['panels'] as List).first['items'].add(<String, dynamic>{
      'type': 'row',
      'children': <Map<String, dynamic>>[
        {'type': 'text', 'text': 'Quality'},
        {'type': 'divider'},
      ],
    });
    expect(TorriodbLiveOverlayStore.isValid(nested), isTrue);
  });

  test('rejects arbitrary code and unknown actions', () {
    expect(TorriodbLiveOverlayStore.isValid(
        config(action: 'eval_javascript')), isFalse);
    final invalid = config();
    (invalid['panels'] as List).first['items'].add(
      <String, dynamic>{'type': 'webview', 'url': 'https://example.com'},
    );
    expect(TorriodbLiveOverlayStore.isValid(invalid), isFalse);
  });

  test('rejects unbounded layouts and unsafe panel sizes', () {
    final invalid = config();
    (invalid['panels'] as List).first['width'] = 10000;
    expect(TorriodbLiveOverlayStore.isValid(invalid), isFalse);
    expect(TorriodbLiveOverlayStore.isValid(
      <String, dynamic>{'schema': 2, 'enabled': true, 'panels': []}),
      isFalse);
  });

  testWidgets('a Torriodb-created button performs its configured action',
      (tester) async {
    String? lastAction;
    store.apply(config());
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TorriodbLiveOverlay(onAction: (action, args) async {
          lastAction = action;
          return <String, Object?>{'accepted': true};
        }),
      ),
    ));
    expect(find.text('Adaptive Live TV'), findsOneWidget);
    await tester.tap(find.text('STOP SURFING'));
    await tester.pump();
    expect(lastAction, 'adaptive_stop');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('modifying the document updates UI without navigation',
      (tester) async {
    store.apply(config());
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TorriodbLiveOverlay(onAction: (action, args) async =>
            <String, Object?>{'accepted': true}),
      ),
    ));
    expect(find.text('STOP SURFING'), findsOneWidget);
    final changed = config();
    (changed['panels'] as List).first['items'][1]['label'] = 'HALT NOW';
    store.apply(changed);
    await tester.pump();
    expect(find.text('STOP SURFING'), findsNothing);
    expect(find.text('HALT NOW'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
