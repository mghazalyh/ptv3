import 'package:flutter_test/flutter_test.dart';
import 'package:playtorrio/services/remote/torriodb_write_queue.dart';

void main() {
  test('Shared Torriodb queue serializes independent uploaders', () async {
    final queue = TorriodbWriteQueue();
    final order = <int>[];
    var inFlight = 0;
    var peak = 0;

    Future<int> write(int id) async {
      inFlight++;
      if (inFlight > peak) peak = inFlight;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      order.add(id);
      inFlight--;
      return id;
    }

    final values = await Future.wait([
      queue.run<int>(() => write(1)),
      queue.run<int>(() => write(2)),
      queue.run<int>(() => write(3)),
    ]);
    expect(values, <int>[1, 2, 3]);
    expect(order, <int>[1, 2, 3]);
    expect(peak, 1);
  });

  test('A failed upload is reported and later queued upload succeeds',
      () async {
    final queue = TorriodbWriteQueue();
    await expectLater(queue.run<int>(() async {
      throw StateError('simulated conflict');
    }), throwsA(isA<StateError>()));
    expect(await queue.run<int>(() async => 42), 42);
  });
}
