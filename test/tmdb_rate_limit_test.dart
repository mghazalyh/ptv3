import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:playtorrio/services/metadata/tmdb_discover_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'local_tmdb_discover_api_key': 'unit-test-not-real',
    });
    TmdbDiscoverService.instance.resetForTesting(
      spacing: Duration.zero,
      cooldown: const Duration(seconds: 5),
    );
  });

  tearDown(() {
    TmdbDiscoverService.instance.resetForTesting();
  });

  test('many taps for identical filter share one TMDB request', () async {
    var calls = 0;
    final service = TmdbDiscoverService.instance;
    service.httpGetOverride = (uri, headers) async {
      calls++;
      expect(uri.host, 'api.themoviedb.org');
      expect(uri.path, '/3/discover/tv');
      expect(uri.queryParameters['api_key'], 'unit-test-not-real');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      return http.Response(jsonEncode({
        'page': 1,
        'total_pages': 2,
        'total_results': 1,
        'results': [
          {'id': 135, 'name': 'Returning TV', 'first_air_date': '2026-01-01'}
        ],
      }), 200);
    };
    const filter = DiscoverFilters(type: DiscoverType.series,
        fromYear: 2026, toYear: 2026);
    final results = await Future.wait([
      service.browse(filter),
      service.browse(filter),
      service.browse(filter),
    ]);
    expect(calls, 1);
    expect(results.every((x) => x.titles.first.premiereYear == 2026), isTrue);
    await service.browse(filter);
    expect(calls, 1, reason: '15-minute discovery cache should be reused.');
    await service.browse(const DiscoverFilters(type: DiscoverType.series,
        fromYear: 2026, toYear: 2026, page: 2));
    expect(calls, 2, reason: 'A deliberate next-page action makes a new request.');
  });

  test('429 stops further requests and never automatically retries', () async {
    var calls = 0;
    final service = TmdbDiscoverService.instance;
    service.httpGetOverride = (uri, headers) async {
      calls++;
      return http.Response('{}', 429, headers: {'retry-after': '90'});
    };
    await expectLater(service.browse(const DiscoverFilters()),
        throwsFormatException);
    expect(calls, 1);
    await expectLater(service.browse(const DiscoverFilters(page: 2)),
        throwsFormatException);
    expect(calls, 1, reason: '429 cooldown must block new HTTP traffic.');
  });

  test('switching key clears cached content', () async {
    var calls = 0;
    final service = TmdbDiscoverService.instance;
    service.httpGetOverride = (uri, headers) async {
      calls++;
      return http.Response(jsonEncode({
        'page': 1, 'total_pages': 1, 'total_results': 0,
        'results': <Object>[],
      }), 200);
    };
    await service.browse(const DiscoverFilters());
    await service.browse(const DiscoverFilters());
    expect(calls, 1);
    await service.saveKey('test-key-replacement');
    await service.browse(const DiscoverFilters());
    expect(calls, 2);
  });

  test('a v4 access token is sent in header, not URL', () async {
    final service = TmdbDiscoverService.instance;
    await service.saveKey('Bearer eyJ-this-is-only-a-test');
    service.httpGetOverride = (uri, headers) async {
      expect(uri.queryParameters.containsKey('api_key'), isFalse);
      expect(headers['Authorization'], 'Bearer eyJ-this-is-only-a-test');
      return http.Response(jsonEncode({
        'page': 1, 'total_pages': 1, 'total_results': 0,
        'results': <Object>[],
      }), 200);
    };
    await service.browse(const DiscoverFilters());
  });
}
