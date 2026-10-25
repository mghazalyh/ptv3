import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:playtorrio/models/my_list/my_list_item.dart';
import 'package:playtorrio/services/my_list/simkl_hearts_cloud.dart';

MyListItem saved(int number) => MyListItem(
  imdbId: 'tt${number.toString().padLeft(7, '0')}',
  title: 'Show $number', type: 'series', addedAt: DateTime(2026, 1, number),
);
Map<String, dynamic> remote(int n, {String status = 'plantowatch',
    int watched = 0}) => {
  'status': status, 'watched_episodes_count': watched,
  'show': {'title': 'Show $n', 'year': 2026,
    'ids': {'imdb': 'tt${n.toString().padLeft(7, '0')}', 'simkl': n}},
};

class FakeSimkl extends SimklHeartGateway {
  bool online = true, failFetch = false, failWrite = false;
  String activity = '2026-10-25T00:00:00Z';
  List<dynamic> shows = [], movies = [], anime = [];
  List<String> uploaded = [], removed = [];
  int fetchCount = 0;
  @override
  Future<bool> connected() async => online;
  @override
  Future<String?> username() async => 'simkl-home';
  @override
  Future<Map<String, dynamic>?> activities() async =>
    online ? {'all': activity} : null;
  @override
  Future<Map<String, dynamic>?> snapshot() async {
    fetchCount++;
    if (failFetch) return null;
    return {'shows': List<dynamic>.from(shows),
      'movies': List<dynamic>.from(movies),
      'anime': List<dynamic>.from(anime)};
  }
  @override
  Future<bool> addBatch(List<Map<String, dynamic>> movieItems,
      List<Map<String, dynamic>> showItems) async {
    if (failWrite) return false;
    for (final row in [...movieItems, ...showItems]) {
      uploaded.add((row['ids'] as Map)['imdb'].toString());
    }
    return true;
  }
  @override
  Future<bool> remove(MyListItem item) async {
    if (failWrite) return false;
    removed.add(item.imdbId!);
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('first account connection merges local hearts and Simkl plan-to-watch', () async {
    final api = FakeSimkl()..shows = [remote(2)];
    final cloud = SimklHeartsCloud(gateway: api);
    var list = [saved(1)];
    final result = await cloud.reconcile(
      readLocal: () => list,
      persistMerged: (items) async { list = items; });
    expect(result, true);
    expect(list, hasLength(2));
    expect(api.uploaded, contains(saved(1).imdbId));
    expect(cloud.state.value, SimklHeartState.synced);
  });

  test('failure to fetch never replaces local library', () async {
    final api = FakeSimkl()..failFetch = true;
    final cloud = SimklHeartsCloud(gateway: api);
    var list = [saved(1)];
    final result = await cloud.reconcile(
      readLocal: () => list,
      persistMerged: (items) async { list = items; });
    expect(result, false);
    expect(list, hasLength(1));
    expect(api.uploaded, isEmpty);
    expect(cloud.state.value, SimklHeartState.failed);
  });

  test('remote unheart is respected on the next activity change', () async {
    final api = FakeSimkl()..shows = [remote(1)];
    final cloud = SimklHeartsCloud(gateway: api);
    var list = <MyListItem>[];
    Future<void> refresh() async {
      await cloud.reconcile(readLocal: () => list,
        persistMerged: (items) async { list = items; });
    }
    await refresh();
    expect(list, hasLength(1));
    api.shows = [];
    api.activity = '2026-10-25T01:00:00Z';
    await refresh();
    expect(list, isEmpty);
    expect(api.uploaded, isEmpty);
  });

  test('offline heart queues upload, no lost saves', () async {
    final api = FakeSimkl()..online = false;
    final cloud = SimklHeartsCloud(gateway: api);
    await cloud.localChange(saved(1), added: true);
    api.online = true;
    var list = [saved(1)];
    await cloud.reconcile(readLocal: () => list,
      persistMerged: (items) async { list = items; });
    expect(api.uploaded, contains(saved(1).imdbId));
  });

  test('offline unheart only deletes remote unwatched plan-to-watch item', () async {
    final api = FakeSimkl()..shows = [remote(1)];
    final cloud = SimklHeartsCloud(gateway: api);
    await cloud.localChange(saved(1), added: false);
    var list = <MyListItem>[];
    await cloud.reconcile(readLocal: () => list,
      persistMerged: (items) async { list = items; });
    expect(list, isEmpty);
    expect(api.removed, contains(saved(1).imdbId));
  });

  test('unheart never destroys watched episode history', () async {
    final api = FakeSimkl()..shows = [remote(1, watched: 3)];
    final cloud = SimklHeartsCloud(gateway: api);
    await cloud.localChange(saved(1), added: false);
    var list = <MyListItem>[];
    final ok = await cloud.reconcile(readLocal: () => list,
      persistMerged: (items) async { list = items; });
    expect(ok, false);
    expect(list, isEmpty);
    expect(api.removed, isEmpty);
    expect(cloud.state.value, SimklHeartState.partial);
  });

  test('subsequent unchanged activity skips heavy library fetch', () async {
    final api = FakeSimkl()..shows = [remote(1)];
    final cloud = SimklHeartsCloud(gateway: api);
    var list = <MyListItem>[];
    Future<void> refresh() async {
      await cloud.reconcile(readLocal: () => list,
        persistMerged: (items) async { list = items; });
    }
    await refresh();
    await refresh();
    expect(api.fetchCount, 1);
  });

  test('completed and dropped are not mistaken for user hearts', () async {
    final api = FakeSimkl()..shows = [
      remote(1, status: 'completed'),
      remote(2, status: 'dropped'),
      remote(3, status: 'plantowatch'),
    ];
    final cloud = SimklHeartsCloud(gateway: api);
    var list = <MyListItem>[];
    await cloud.reconcile(readLocal: () => list,
      persistMerged: (items) async { list = items; });
    expect(list.length, 1);
    expect(list.single.imdbId, saved(3).imdbId);
  });
}
