import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:playtorrio/models/my_list/my_list_item.dart';
import 'package:playtorrio/services/my_list/trakt_cloud_library.dart';

MyListItem localTitle(int i) => MyListItem(
  imdbId: 'tt${i.toString().padLeft(7, '0')}',
  title: 'Title $i', type: 'movie', addedAt: DateTime(2026, 1, i),
);

Map<String, dynamic> cloudTitle(int i) => {
  'listed_at': '2026-01-01T00:00:00Z',
  'movie': {'title': 'Title $i', 'year': 2026, 'ids': {
    'imdb': 'tt${i.toString().padLeft(7, '0')}', 'trakt': i,
  }},
};

class FakeTraktGateway extends TraktSyncGateway {
  bool online = true;
  bool failFetch = false;
  bool failUpload = false;
  List<dynamic> movies = [];
  List<dynamic> shows = [];
  final List<String> removed = [];
  final List<String> uploaded = [];
  int fetchCount = 0;

  @override
  Future<bool> connected() async => online;
  @override
  Future<String?> username() async => 'my-test-account';
  @override
  Future<List<dynamic>?> fetch(String type) async {
    fetchCount++;
    if (failFetch) return null;
    return type == 'movies' ? List<dynamic>.from(movies)
        : List<dynamic>.from(shows);
  }
  @override
  Future<bool> add(MyListItem item) async {
    if (!online) return false;
    uploaded.add(item.imdbId!);
    return true;
  }
  @override
  Future<bool> upload(List<Map<String, dynamic>> movieItems,
      List<Map<String, dynamic>> showItems) async {
    if (failUpload) return false;
    for (final item in [...movieItems, ...showItems]) {
      uploaded.add(item['ids']['imdb'].toString());
    }
    return true;
  }
  @override
  Future<bool> remove(MyListItem item) async {
    if (!online) return false;
    removed.add(item.imdbId!);
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('first sync merges device and Trakt, uploads older local items', () async {
    final gateway = FakeTraktGateway()..movies = [cloudTitle(2)];
    final service = TraktCloudLibrary(gateway: gateway);
    var library = [localTitle(1)];
    final ok = await service.reconcile(
      readLocal: () => library,
      persistMerged: (merged) async => library = merged,
    );
    expect(ok, true);
    expect(library, hasLength(2));
    expect(gateway.uploaded, contains(localTitle(1).imdbId));
    expect(service.state.value, TraktSyncState.synced);
  });

  test('failed fetch never overwrites local collection', () async {
    final gateway = FakeTraktGateway()..failFetch = true;
    final service = TraktCloudLibrary(gateway: gateway);
    var library = [localTitle(1)];
    final ok = await service.reconcile(
      readLocal: () => library,
      persistMerged: (merged) async => library = merged,
    );
    expect(ok, false);
    expect(library.single.imdbId, localTitle(1).imdbId);
    expect(gateway.uploaded, isEmpty);
    expect(service.state.value, TraktSyncState.failed);
  });

  test('Trakt removal on another device is respected, not re-uploaded', () async {
    final gateway = FakeTraktGateway()..movies = [cloudTitle(1)];
    final service = TraktCloudLibrary(gateway: gateway);
    var library = <MyListItem>[];
    Future<void> refresh() async {
      await service.reconcile(
        readLocal: () => library,
        persistMerged: (merged) async => library = merged,
      );
    }
    await refresh();
    expect(library, hasLength(1));
    gateway.movies = [];
    await refresh();
    expect(library, isEmpty);
    expect(gateway.uploaded, isEmpty);
  });

  test('offline remove queues remote deletion until next refresh', () async {
    final gateway = FakeTraktGateway()..online = false;
    final service = TraktCloudLibrary(gateway: gateway);
    await service.localChange(localTitle(1), added: false);
    gateway.online = true;
    gateway.movies = [cloudTitle(1)];
    var library = <MyListItem>[];
    await service.reconcile(
      readLocal: () => library,
      persistMerged: (merged) async => library = merged);
    expect(library, isEmpty);
    expect(gateway.removed, contains(localTitle(1).imdbId));
  });

  test('failed uploads stay local and display incomplete state', () async {
    final gateway = FakeTraktGateway()..failUpload = true;
    final service = TraktCloudLibrary(gateway: gateway);
    var library = [localTitle(1)];
    final success = await service.reconcile(
      readLocal: () => library,
      persistMerged: (merged) async => library = merged);
    expect(success, isFalse);
    expect(library, hasLength(1));
    expect(service.state.value, TraktSyncState.partial);
  });

  test('offline add is uploaded on reconnect', () async {
    final gateway = FakeTraktGateway()..online = false;
    final service = TraktCloudLibrary(gateway: gateway);
    await service.localChange(localTitle(1), added: true);
    gateway.online = true;
    var library = [localTitle(1)];
    await service.reconcile(
      readLocal: () => library,
      persistMerged: (merged) async => library = merged);
    expect(gateway.uploaded, contains(localTitle(1).imdbId));
  });
}
