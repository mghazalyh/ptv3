import 'package:flutter_test/flutter_test.dart';
import 'package:playtorrio/models/my_list/my_list_item.dart';
import 'package:playtorrio/services/my_list/trakt_merge_plan.dart';

MyListItem item(int id, {DateTime? time}) => MyListItem(
  imdbId: 'tt${id.toString().padLeft(7, '0')}',
  title: 'Movie $id',
  year: 2020,
  type: 'movie',
  addedAt: time ?? DateTime(2026, 1, 1),
);

void main() {
  group('Non-destructive Trakt merge plan', () {
    test('first pairing uploads older local saves and merges remote titles', () {
      final p = TraktMergePlan.create(
        local: [item(1)],
        remote: [item(2)],
        previouslySeen: [],
        pendingAdds: [],
        pendingRemoves: [],
      );
      expect(p.merged.length, 2);
      expect(p.toUpload.map((x) => x.imdbId), contains(item(1).imdbId));
      expect(p.toRemoveRemotely, isEmpty);
    });

    test('remote deletion on same account stays deleted, no re-upload', () {
      final p = TraktMergePlan.create(
        local: [item(1), item(2)],
        remote: [item(2)],
        previouslySeen: [item(1), item(2)],
        pendingAdds: [],
        pendingRemoves: [],
      );
      expect(p.merged.length, 1);
      expect(p.merged.single.imdbId, item(2).imdbId);
      expect(p.toUpload, isEmpty);
    });

    test('explicit offline re-add wins over prior remote deletion', () {
      final p = TraktMergePlan.create(
        local: [item(1)],
        remote: [],
        previouslySeen: [item(1)],
        pendingAdds: [item(1)],
        pendingRemoves: [],
      );
      expect(p.merged.length, 1);
      expect(p.toUpload, hasLength(1));
    });

    test('pending offline remove cannot be pulled back from remote', () {
      final p = TraktMergePlan.create(
        local: [],
        remote: [item(1)],
        previouslySeen: [item(1)],
        pendingAdds: [],
        pendingRemoves: [item(1)],
      );
      expect(p.merged, isEmpty);
      expect(p.toRemoveRemotely, hasLength(1));
    });

    test('items without identifiers remain locally saved', () {
      final noId = MyListItem(title: 'Unmapped show',
          type: 'series', addedAt: DateTime(2026));
      final p = TraktMergePlan.create(
        local: [noId], remote: [], previouslySeen: [],
        pendingAdds: [], pendingRemoves: [],
      );
      expect(p.merged, hasLength(1));
      expect(p.toUpload, isEmpty);
      expect(p.unsyncableCount, 1);
    });

    test('matching IMDb titles are merged, not duplicated', () {
      final old = item(1);
      final fetched = MyListItem(
        imdbId: old.imdbId, traktId: 8765, title: old.title,
        type: 'movie', addedAt: DateTime(2026, 5),
      );
      final p = TraktMergePlan.create(
        local: [old], remote: [fetched], previouslySeen: [],
        pendingAdds: [], pendingRemoves: [],
      );
      expect(p.merged, hasLength(1));
      expect(p.merged.single.traktId, 8765);
      expect(p.toUpload, isEmpty);
    });
  });
}
