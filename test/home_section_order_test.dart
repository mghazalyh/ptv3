import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:playtorrio/models/addon/addon.dart';
import 'package:playtorrio/models/movie/movie_section.dart';
import 'package:playtorrio/services/home/home_section_order_service.dart';

AddonCatalog catalog(String id, {String type = 'movie'}) =>
    AddonCatalog(type: type, id: id, name: id, genres: const [],
      supportsSearch: false, supportsSkip: false);

MovieSection row(String addon, String id, {bool curated = false}) =>
    MovieSection(
      title: addon, subtitle: addon,
      contentType: 'movie',
      addonBaseUrl: 'https://example.com/private-key/manifest.json',
      sourceAddonId: addon,
      catalog: catalog(id),
      movies: const [],
      isCurated: curated,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    HomeSectionOrderService.orderedKeys.value = const <String>[];
  });

  test('provider and catalog identifiers are stable, not private URLs', () {
    final a = HomeSectionOrderService.idForSection(row('xperience', 'trending'));
    final b = HomeSectionOrderService.idForSection(row('torbox', 'trending'));
    expect(a, isNot(b));
    expect(a, isNot(contains('private-key')));
    expect(a, HomeSectionOrderService.idForSection(row('xperience', 'trending')));
  });

  test('Trakt is ordered as a curated recommendation, not an addon', () {
    final trakt = HomeSectionOrderService.idForSection(
      row('trakt', 'trakt_recommendations', curated: true));
    expect(trakt, HomeSectionOrderService.recommendationId('trakt_recommendations'));
    expect(trakt, isNot(HomeSectionOrderService.idForSection(
      row('trakt', 'trakt_recommendations'))));
  });

  test('sorts loaded rows without modifying their original list', () {
    final continueWatching = HomeSectionOrderService.continueWatchingId;
    final trakt = HomeSectionOrderService.recommendationId('trakt_recommendations');
    final xperience = HomeSectionOrderService.catalogId('xperience', 'movie', 'trending');
    final torbox = HomeSectionOrderService.catalogId('torbox', 'movie', 'torrents');
    HomeSectionOrderService.orderedKeys.value = [xperience, trakt, continueWatching];
    final source = [continueWatching, trakt, torbox, xperience, 'new:catalog'];
    expect(HomeSectionOrderService.apply(source, (value) => value),
      [xperience, trakt, continueWatching, torbox, 'new:catalog']);
    expect(source.first, continueWatching);
  });

  test('keeps temporarily unavailable addon rankings', () async {
    HomeSectionOrderService.orderedKeys.value = ['hidden:provider'];
    await HomeSectionOrderService.saveVisibleOrder(['visible:one', 'visible:two']);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList(HomeSectionOrderService.storageKey),
      ['visible:one', 'visible:two', 'hidden:provider']);
  });

  test('cloud restore updates the order without a sync write-back', () async {
    await HomeSectionOrderService.restoreFromCloud(
      ['recommendation:trakt_recommendations', 'catalog:xperience:movie:featured']);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('torriodb_portable_sync_dirty_v1'), isNull);
    expect(HomeSectionOrderService.orderedKeys.value.length, 2);
    await HomeSectionOrderService.reset();
    expect(HomeSectionOrderService.orderedKeys.value, isEmpty);
  });

  test('rejects malformed and overlong section order', () {
    expect(() => HomeSectionOrderService.normalize('invalid'), throwsFormatException);
    expect(() => HomeSectionOrderService.normalize(['ok', 3]), throwsFormatException);
    expect(() => HomeSectionOrderService.normalize(
      List.generate(251, (n) => 'row:$n')), throwsFormatException);
    expect(HomeSectionOrderService.normalize(['a', 'a', 'b']), ['a', 'b']);
  });
}
