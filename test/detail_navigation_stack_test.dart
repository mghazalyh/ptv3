import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playtorrio/utils/navigation/detail_navigation.dart';

class _SearchLanding extends StatelessWidget {
  const _SearchLanding();
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: ElevatedButton(
        key: const Key('open-search-show'),
        onPressed: () => DetailNavigation.push(
          context, (_) => const _NestedDetail(name: 'First show', depth: 1)),
        child: const Text('Search results'),
      ),
    ),
  );
}

class _NestedDetail extends StatefulWidget {
  const _NestedDetail({required this.name, required this.depth});
  final String name;
  final int depth;
  @override
  State<_NestedDetail> createState() => _NestedDetailState();
}

class _NestedDetailState extends State<_NestedDetail> {
  int likes = 0;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.name)),
    body: Column(
      children: [
        Text('Likes ${widget.name}: $likes'),
        TextButton(
          key: Key('like-${widget.depth}'),
          onPressed: () => setState(() => likes++),
          child: const Text('Mark liked'),
        ),
        ElevatedButton(
          key: Key('similar-${widget.depth}'),
          onPressed: () => DetailNavigation.push(
            context, (_) => _NestedDetail(
              name: 'Similar ${widget.depth + 1}',
              depth: widget.depth + 1,
            )),
          child: const Text('Next similar show'),
        ),
      ],
    ),
  );
}

void main() {
  testWidgets('Similar routes retain every detail and back unwinds exact order',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _SearchLanding()));
    await tester.tap(find.byKey(const Key('open-search-show')));
    await tester.pumpAndSettle();

    expect(find.text('First show'), findsOneWidget);
    await tester.tap(find.byKey(const Key('like-1')));
    await tester.pump();
    expect(find.text('Likes First show: 1'), findsOneWidget);

    await tester.tap(find.byKey(const Key('similar-1')));
    await tester.pumpAndSettle();
    expect(find.text('Similar 2'), findsOneWidget);
    await tester.tap(find.byKey(const Key('like-2')));
    await tester.pump();

    await tester.tap(find.byKey(const Key('similar-2')));
    await tester.pumpAndSettle();
    expect(find.text('Similar 3'), findsOneWidget);

    await tester.tap(find.byKey(const Key('similar-3')));
    await tester.pumpAndSettle();
    expect(find.text('Similar 4'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Similar 3'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Similar 2'), findsOneWidget);
    expect(find.text('Likes Similar 2: 1'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('First show'), findsOneWidget);
    expect(find.text('Likes First show: 1'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Search results'), findsOneWidget);
  });
}
