import '../../models/my_list/my_list_item.dart';

/// A non-destructive plan for reconciling local saves with a complete, valid
/// Trakt snapshot. Remote deletions are only acted on if the current Trakt
/// account previously confirmed that item, preventing first-login data loss.
class TraktMergePlan {
  final List<MyListItem> merged;
  final List<MyListItem> toUpload;
  final List<MyListItem> toRemoveRemotely;
  final Set<String> remoteKeys;
  final int unsyncableCount;

  const TraktMergePlan({
    required this.merged,
    required this.toUpload,
    required this.toRemoveRemotely,
    required this.remoteKeys,
    required this.unsyncableCount,
  });

  static bool _contains(Iterable<MyListItem> items, MyListItem candidate) =>
      items.any((item) => item.matches(candidate));

  static bool hasCloudId(MyListItem item) =>
      (item.imdbId?.startsWith('tt') ?? false) ||
      item.tmdbId != null || item.traktId != null;

  static Map<String, dynamic>? toTraktEntry(MyListItem item) {
    final ids = <String, dynamic>{};
    if (item.imdbId?.startsWith('tt') ?? false) {
      ids['imdb'] = item.imdbId;
    }
    if (item.tmdbId != null) ids['tmdb'] = item.tmdbId;
    if (item.traktId != null) ids['trakt'] = item.traktId;
    return ids.isEmpty ? null : {'ids': ids};
  }

  static TraktMergePlan create({
    required List<MyListItem> local,
    required List<MyListItem> remote,
    required List<MyListItem> previouslySeen,
    required List<MyListItem> pendingAdds,
    required List<MyListItem> pendingRemoves,
  }) {
    final visible = <MyListItem>[];
    final toUpload = <MyListItem>[];
    var unsyncable = 0;

    // Remote removal wins only if this same device previously saw it in
    // Trakt and there is no explicit local re-add pending.
    for (final item in local) {
      if (_contains(pendingRemoves, item)) continue;
      final remotePresent = _contains(remote, item);
      final knownPreviously = _contains(previouslySeen, item);
      final locallyReadded = _contains(pendingAdds, item);
      if (!remotePresent && knownPreviously && !locallyReadded) continue;

      final match = remote.where((candidate) => candidate.matches(item));
      visible.add(match.isEmpty ? item : item.mergeWith(match.first));
      if (!remotePresent && (!knownPreviously || locallyReadded)) {
        if (hasCloudId(item)) {
          toUpload.add(item);
        } else {
          unsyncable++;
        }
      }
    }

    for (final item in remote) {
      if (_contains(pendingRemoves, item)) continue;
      if (!_contains(visible, item)) visible.add(item);
    }
    for (final item in pendingAdds) {
      if (_contains(pendingRemoves, item) || _contains(remote, item)) continue;
      if (!_contains(toUpload, item) && hasCloudId(item)) toUpload.add(item);
      if (!_contains(visible, item)) visible.add(item);
    }

    visible.sort((a, b) => b.addedAt.compareTo(a.addedAt));
    return TraktMergePlan(
      merged: visible,
      toUpload: toUpload,
      toRemoveRemotely: pendingRemoves.where(
        (item) => hasCloudId(item) && _contains(remote, item),
      ).toList(),
      remoteKeys: remote.map((item) => item.uniqueKey).toSet(),
      unsyncableCount: unsyncable,
    );
  }
}
