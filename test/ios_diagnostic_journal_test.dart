import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:playtorrio/services/remote/ios_diagnostic_journal.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late IosDiagnosticJournal journal;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('ptv-journal-');
    journal = IosDiagnosticJournal.forTesting(directory);
  });
  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('Persists raw native errors across reader instances', () async {
    await journal.record('mpv.log', {
      'level': 'error',
      'message': 'Demuxer failed: HTTP 403 on https://media.example/segment',
    });
    final other = IosDiagnosticJournal.forTesting(directory);
    final result = await other.tail();
    expect(result['accepted'], true);
    final events = result['events'] as List;
    expect(events, hasLength(1));
    final details = (events.single as Map)['details'] as Map;
    expect(details['message'], contains('HTTP 403'));
  });

  test('Concurrent records are serialized and timestamped', () async {
    await Future.wait(List.generate(40, (i) =>
        journal.record('source.transition', {'index': i})));
    final status = await journal.status();
    expect(status['written'], 40);
    expect(status['writeFailures'], 0);
    final tail = await journal.tail(count: 5);
    expect(tail['returned'], 5);
    expect(((tail['events'] as List).last as Map)['kind'],
        'source.transition');
  });

  test('Exact bytes are returned as resumable export chunks', () async {
    await journal.record('probe', {'payload': 'sample'});
    final first = await journal.readChunk(length: 15);
    expect(first['accepted'], true);
    final second = await journal.readChunk(
      offset: first['nextOffset'] as int,
      length: 200,
    );
    final data = [
      ...base64Decode(first['dataBase64'] as String),
      ...base64Decode(second['dataBase64'] as String),
    ];
    expect(utf8.decode(data), contains('"payload":"sample"'));
    expect(second['complete'], true);
  });

  test('Native screenshot is kept as a binary exportable capture', () async {
    final bytes = List<int>.generate(100000, (i) => i % 256);
    final response = await journal.saveCapture(bytes);
    expect(response['accepted'], true);
    final first = await journal.readChunk(segment: 'capture');
    expect(first['accepted'], true);
    expect(first['bytes'], IosDiagnosticJournal.maxExportBytes);
    final last = await journal.readChunk(segment: 'capture',
        offset: first['nextOffset'] as int);
    expect(last['complete'], false);
    expect((await journal.status())['captureBytes'], bytes.length);
  });

  test('Invalid offsets and segments are rejected', () async {
    await journal.record('event', {});
    expect((await journal.readChunk(offset: -1))['accepted'], false);
    expect((await journal.readChunk(length: IosDiagnosticJournal.maxExportBytes + 1))['accepted'], false);
    expect((await journal.readChunk(offset: 999999))['accepted'], false);
    try {
      await journal.readChunk(segment: '../escape');
      fail('Expected invalid segment');
    } on FormatException {
      // Reject traversal rather than accessing another sandbox file.
    }
  });

  test('Oversized event is retained as a diagnostic record', () async {
    await journal.record('too_large', {'value': List.filled(20000, 'x').join()});
    final stats = await journal.status();
    expect(stats['oversizedEvents'], 1);
    final file = File('${directory.path}/current.jsonl');
    final fragments = (await file.readAsLines())
        .map((line) => jsonDecode(line) as Map<String, dynamic>)
        .toList();
    expect(fragments.length, greaterThan(1));
    expect(fragments.last['kind'], 'journal.event_fragment');
    final payload = fragments.map((fragment) =>
        (fragment['details'] as Map)['dataBase64'] as String).toList();
    final joined = payload.expand((part) => base64Decode(part)).toList();
    final original = jsonDecode(utf8.decode(joined)) as Map<String, dynamic>;
    expect(original['kind'], 'too_large');
    expect((original['details'] as Map)['value'],
        hasLength(20000));
  });
}
