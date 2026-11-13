
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:playtorrio/models/stream/stream_model.dart';
import 'package:playtorrio/services/stream/source_availability_service.dart';

void main() {
  final playable = StreamSource(
    url: 'https://example.com/video.m3u8',
    addonName: 'Test addon',
    title: 'Example title',
  );
  final pending = StreamSource(
    url: 'https://example.com/pending',
    addonName: 'Test addon',
    title: '[Pending download]',
  );

  test('details-only probe deduplicates candidates and caches result', () async {
    var calls = 0;
    final service = SourceAvailabilityService(
      loader: ({
        required String type,
        required String id,
        required String title,
        int? year,
        int? season,
        int? episode,
      }) {
        calls++;
        return Stream<StreamSource>.fromIterable([playable, playable]);
      },
    );
    final first = await service.inspect(
        type: 'movie', id: 'tt123', title: 'Example');
    expect(first.complete, isTrue);
    expect(first.count, 1);
    final second = await service.inspect(
        type: 'movie', id: 'tt123', title: 'Example');
    expect(second.count, 1);
    expect(calls, 1);
    expect(service.peek(type: 'movie', id: 'tt123', title: 'Example')?.count, 1);
    expect(SourceAvailabilityService.identityOf(playable), isNotEmpty);
  });

  test('source checks reuse in-flight work for same episode', () async {
    var calls = 0;
    final controller = StreamController<StreamSource>();
    final service = SourceAvailabilityService(
      loader: ({
        required String type,
        required String id,
        required String title,
        int? year,
        int? season,
        int? episode,
      }) {
        calls++;
        return controller.stream;
      },
    );
    final first = service.inspect(type: 'series', id: 'tt55:1:2',
        title: 'Example', season: 1, episode: 2);
    final second = service.existing(type: 'series', id: 'tt55:1:2',
        title: 'Example', season: 1, episode: 2);
    expect(second, isNotNull);
    expect(calls, 1);
    controller.add(playable);
    await controller.close();
    expect((await first).count, 1);
    expect((await second!).count, 1);
  });

  test('different episodes use separate availability requests', () async {
    var calls = 0;
    final service = SourceAvailabilityService(
      loader: ({
        required String type,
        required String id,
        required String title,
        int? year,
        int? season,
        int? episode,
      }) {
        calls++;
        return Stream<StreamSource>.fromIterable([playable]);
      },
    );
    await service.inspect(type: 'series', id: 'tt5:1:1',
        title: 'Example', season: 1, episode: 1);
    await service.inspect(type: 'series', id: 'tt5:1:2',
        title: 'Example', season: 1, episode: 2);
    expect(calls, 2);
  });

  test('expired cached availability is rechecked', () async {
    var calls = 0;
    var now = DateTime.utc(2026, 11, 14);
    final service = SourceAvailabilityService(
      ttl: const Duration(seconds: 10),
      clock: () => now,
      loader: ({
        required String type,
        required String id,
        required String title,
        int? year,
        int? season,
        int? episode,
      }) {
        calls++;
        return Stream<StreamSource>.fromIterable([playable]);
      },
    );
    await service.inspect(type: 'movie', id: 'tt5', title: 'Example');
    now = now.add(const Duration(seconds: 11));
    expect(service.peek(type: 'movie', id: 'tt5', title: 'Example'), isNull);
    await service.inspect(type: 'movie', id: 'tt5', title: 'Example');
    expect(calls, 2);
  });

  test('timeouts are unknown, not falsely reported as no sources', () async {
    final neverCompletes = StreamController<StreamSource>();
    final service = SourceAvailabilityService(
      deadline: const Duration(milliseconds: 20),
      loader: ({
        required String type,
        required String id,
        required String title,
        int? year,
        int? season,
        int? episode,
      }) => neverCompletes.stream,
    );
    final result = await service.inspect(
        type: 'movie', id: 'tt9', title: 'Unknown');
    expect(result.count, 0);
    expect(result.complete, isFalse);
    expect(service.peek(type: 'movie', id: 'tt9', title: 'Unknown'), isNull);
    await neverCompletes.close();
  });

  test('embedded sources are reused and invalid candidates are excluded',
      () async {
    final service = SourceAvailabilityService(
      loader: ({
        required String type,
        required String id,
        required String title,
        int? year,
        int? season,
        int? episode,
      }) => Stream<StreamSource>.empty(),
    );
    final result = await service.inspect(
      type: 'series', id: 'tt9:1:1', title: 'Example',
      season: 1, episode: 1,
      embedded: [playable, playable],
    );
    expect(result.count, 1);
    expect(SourceAvailabilityService.isCandidate(pending), isFalse);
  });
}
