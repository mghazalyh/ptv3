import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:playtorrio/models/my_list/my_list_item.dart';
import 'package:playtorrio/services/my_list/github_library_cloud.dart';

MyListItem example(String id) => MyListItem(
  imdbId: id, tmdbId: 118956, title: 'Example', year: 2021,
  type: 'series', addedAt: DateTime.utc(2026, 10, 26),
);
Map<String, dynamic> record(MyListItem item, DateTime edited, {
  bool deleted = false,
}) => GitHubLibraryMerge.toRecord(
  item, changedAt: edited, deleted: deleted,
);

void main() {
  test('concatenated and ranged year inputs use the FIRST release year', () {
    expect(MyListNormalize.releaseYear(20212022), 2021);
    expect(MyListNormalize.releaseYear(20162019), 2016);
    expect(MyListNormalize.releaseYear(20222023), 2022);
    expect(MyListNormalize.releaseYear(20092020), 2009);
    expect(MyListNormalize.releaseYear('2017–2023'), 2017);
    expect(MyListNormalize.releaseYear('2026–'), 2026);
    expect(MyListNormalize.releaseYear('no-year'), isNull);
    expect(MyListItem.fromMovie(
      id: 'tt1', name: 'Example', year: '2021–2022', type: 'series',
    ).year, 2021);
  });

  test('HTML escaped title is decoded for display and new writes', () {
    final item = MyListItem.fromJson({
      'imdbId': 'tt34620612', 'type': 'series', 'year': 2025,
      'title':
          'Even Given the Worthless &quot;Appraiser&quot; Class, I&#39;m Actually the Strongest',
      'addedAt': '2026-10-27T04:04:52.438420',
    });
    expect(item.title, contains('"Appraiser"'));
    expect(item.title, contains("I'm"));
    expect(item.toJson()['title'], item.title);
  });

  test('legacy timezone-less date has consistent UTC meaning', () {
    final item = MyListItem.fromJson({
      'imdbId': 'tt1', 'title': 'Example', 'type': 'series',
      'addedAt': '2026-10-27T03:44:51.518592',
    });
    expect(item.addedAt.isUtc, true);
    expect(item.addedAt.hour, 3);
    expect(item.toJson()['addedAt'], endsWith('Z'));
  });

  test('existing version 1 records still parse and are not rewritten', () {
    final json = jsonEncode({
      'version': 1, 'records': {
        'imdb:tt14069590': {
          'deleted': false, 'item': {
            'imdbId': 'tt14069590', 'tmdbId': 118956,
            'title': "Dota: Dragon's Blood", 'year': 20212022,
            'type': 'series', 'addedAt': '2026-10-25T22:21:14.970099',
            'source': 'local',
          },
        },
        'imdb:tt34620612': {
          'deleted': false, 'item': {
            'imdbId': 'tt34620612', 'tmdbId': 270474,
            'title': 'Worthless &quot;Appraiser&quot; Class',
            'year': 2025, 'type': 'series',
            'addedAt': '2026-10-27T04:04:52.438420',
          },
        },
      },
    });
    final remote = GitHubLibraryMerge.decode(json);
    expect(GitHubLibraryMerge.visible(remote).length, 2);
    final dota = GitHubLibraryMerge.visible(remote)
        .singleWhere((i) => i.imdbId == 'tt14069590');
    expect(dota.year, 2021);
    expect(GitHubLibraryMerge.merge(remote, {}), remote);
    expect(() => GitHubLibraryMerge.decode('{"version":2,"records":{}}'),
        throwsFormatException);
  });

  test('older offline deletion cannot overwrite a newer remote re-add', () {
    final item = example('tt1');
    final merged = GitHubLibraryMerge.merge({
      'imdb:tt1': record(item, DateTime.utc(2026, 10, 27, 10)),
    }, {
      'imdb:tt1': record(
          item, DateTime.utc(2026, 10, 27, 9), deleted: true),
    });
    expect(GitHubLibraryMerge.visible(merged), hasLength(1));
  });

  test('older offline add cannot resurrect a newer deleted title', () {
    final item = example('tt1');
    final merged = GitHubLibraryMerge.merge({
      'imdb:tt1': record(
          item, DateTime.utc(2026, 10, 27, 10), deleted: true),
    }, {
      'imdb:tt1': record(item, DateTime.utc(2026, 10, 27, 9)),
    });
    expect(GitHubLibraryMerge.visible(merged), isEmpty);
  });

  test('newest intentional action wins for same stable key', () {
    final item = example('tt1');
    final merged = GitHubLibraryMerge.merge({
      'imdb:tt1': record(item, DateTime.utc(2026, 10, 27, 9)),
    }, {
      'imdb:tt1': record(
          item, DateTime.utc(2026, 10, 27, 10), deleted: true),
    });
    expect(GitHubLibraryMerge.visible(merged), isEmpty);
  });

  test('parallel edits to separate titles preserve the union', () {
    final merged = GitHubLibraryMerge.merge({
      'imdb:tt1': record(example('tt1'), DateTime.utc(2026, 10, 27)),
    }, {
      'imdb:tt2': record(example('tt2'), DateTime.utc(2026, 10, 27)),
    });
    expect(merged.keys, containsAll(['imdb:tt1', 'imdb:tt2']));
  });

  test('first import cannot bring back an old remotely deleted title', () {
    final item = example('tt1');
    final deleted = {'deleted': true, 'item': item.toJson()};
    final merged = GitHubLibraryMerge.merge({
      'imdb:tt1': deleted,
    }, {}, importLocal: [item]);
    expect(merged['imdb:tt1'], deleted);
    expect(GitHubLibraryMerge.visible(merged), isEmpty);
  });

  test('only new records receive updatedAt and legacy entries remain intact', () {
    final prior = {
      'imdb:tt1': {'deleted': false, 'item': example('tt1').toJson()},
    };
    expect(GitHubLibraryMerge.merge(prior, {}), prior);
    final updated = GitHubLibraryMerge.merge(prior, {
      'imdb:tt2': record(example('tt2'), DateTime.utc(2026, 10, 27)),
    });
    expect((updated['imdb:tt1'] as Map).containsKey('updatedAt'), false);
    expect((updated['imdb:tt2'] as Map).containsKey('updatedAt'), true);
  });
}
