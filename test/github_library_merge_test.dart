import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:playtorrio/models/my_list/my_list_item.dart';
import 'package:playtorrio/services/my_list/github_library_cloud.dart';

MyListItem entry(String imdb) => MyListItem(
  imdbId: imdb, title: imdb, type: 'series', addedAt: DateTime.utc(2026));

Map<String, dynamic> record(MyListItem item, {bool deleted = false}) => {
  'item': item.toJson(), 'deleted': deleted,
};

void main() {
  test('database version must be supported; corrupt data never becomes empty', () {
    expect(() => GitHubLibraryMerge.decode('oops'), throwsFormatException);
    expect(() => GitHubLibraryMerge.decode('{"version":2,"records":{}}'),
        throwsFormatException);
    expect(GitHubLibraryMerge.decode('{"version":1,"records":{}}'), isEmpty);
  });

  test('new device pulls existing remote library without duplicating', () {
    final remote = {'imdb:tt1': record(entry('tt1'))};
    final result = GitHubLibraryMerge.merge(remote, {});
    expect(GitHubLibraryMerge.visible(result).length, 1);
    expect(GitHubLibraryMerge.visible(result).single.imdbId, 'tt1');
  });

  test('first connection imports local library without overwriting remote entries', () {
    final remote = {'imdb:tt1': record(entry('tt1'), deleted: true)};
    final imported = [entry('tt1'), entry('tt2')];
    final result = GitHubLibraryMerge.merge(remote, {}, importLocal: imported);
    expect(GitHubLibraryMerge.visible(result).map((e) => e.imdbId), ['tt2']);
    expect((result['imdb:tt1'] as Map)['deleted'], isTrue);
  });

  test('queued tombstone wins over remote old title', () {
    final remote = {
      'imdb:tt1': record(entry('tt1')),
      'imdb:tt2': record(entry('tt2')),
    };
    final pending = {'imdb:tt1': record(entry('tt1'), deleted: true)};
    final result = GitHubLibraryMerge.merge(remote, pending);
    expect(GitHubLibraryMerge.visible(result).map((e) => e.imdbId), ['tt2']);
    expect(jsonEncode(result), contains('"deleted":true'));
  });

  test('concurrent additions on different devices are preserved by refetch/rebase', () {
    final remoteAfterOtherDevice = {'imdb:tt1': record(entry('tt1'))};
    final ownPending = {'imdb:tt2': record(entry('tt2'))};
    final result = GitHubLibraryMerge.merge(remoteAfterOtherDevice, ownPending);
    expect(GitHubLibraryMerge.visible(result).map((e) => e.imdbId),
        containsAll(['tt1', 'tt2']));
  });

  test('one malformed title does not erase another', () {
    final result = GitHubLibraryMerge.visible({
      'bad': {'deleted': false, 'item': 'invalid'},
      'good': record(entry('tt3')),
    });
    expect(result.single.imdbId, 'tt3');
  });
}
