import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../models/download/download_task_model.dart';
import '../../utils/download/download_path_helper.dart';
import '../download/download_service.dart';
import '../stream/torrent_stream_service.dart';

class StorageSnapshot {
  final int temporaryBytes;
  final int incompleteBytes;
  final int savedBytes;
  final int incompleteCount;

  const StorageSnapshot({
    required this.temporaryBytes,
    required this.incompleteBytes,
    required this.savedBytes,
    required this.incompleteCount,
  });
}

class StorageCleanupResult {
  final int freedBytes;
  final int deletedCount;
  final List<String> errors;

  const StorageCleanupResult(this.freedBytes, this.deletedCount, this.errors);
}

class StorageCacheService {
  StorageCacheService._();
  static final StorageCacheService instance = StorageCacheService._();

  static const int maxTemporaryBytes = 512 * 1024 * 1024;

  bool get hasActiveDownloads => DownloadService.instance.tasksNotifier.value.any(
    (task) => task.status == DownloadStatus.downloading ||
        task.status == DownloadStatus.queued,
  );

  Future<List<Directory>> _cacheDirectories() async {
    final result = <Directory>[];
    for (final resolver in <Future<Directory> Function()>[
      getTemporaryDirectory,
      getApplicationCacheDirectory,
    ]) {
      try {
        result.add(await resolver());
      } catch (error) {
        debugPrint('[StorageCache] Cannot locate cache directory: ' + error.toString());
      }
    }
    result.sort((a, b) => a.path.length.compareTo(b.path.length));
    final unique = <Directory>[];
    for (final dir in result) {
      final path = p.normalize(dir.absolute.path);
      if (!unique.any((existing) {
        final root = p.normalize(existing.absolute.path);
        return path == root || p.isWithin(root, path);
      })) {
        unique.add(dir);
      }
    }
    return unique;
  }

  Future<int> _folderSize(Directory dir) async {
    if (!await dir.exists()) return 0;
    var size = 0;
    await for (final entry in dir.list(recursive: true, followLinks: false)) {
      if (entry is! File) continue;
      try {
        size += await entry.length();
      } catch (error) {
        debugPrint('[StorageCache] Stat error: ' + error.toString());
      }
    }
    return size;
  }

  Set<String> _protectedPartials() {
    final protected = <String>{};
    for (final task in DownloadService.instance.tasksNotifier.value) {
      if (task.status != DownloadStatus.downloading &&
          task.status != DownloadStatus.queued &&
          task.status != DownloadStatus.paused) {
        continue;
      }
      final target = p.normalize(task.targetFilePath);
      protected.add(target + '.part');
      protected.add(target + '.hls_meta.json');
    }
    return protected;
  }

  Future<List<File>> _unusedPartials() async {
    final root = Directory(await DownloadPathHelper.getDownloadsDirectoryPath());
    if (!await root.exists()) return [];
    final protected = _protectedPartials();
    final found = <File>[];
    await for (final entry in root.list(recursive: true, followLinks: false)) {
      if (entry is! File) continue;
      final path = p.normalize(entry.path);
      if (protected.contains(path)) continue;
      if (path.endsWith('.part') || path.endsWith('.hls_meta.json')) {
        found.add(entry);
      }
    }
    return found;
  }

  Future<StorageSnapshot> scan() async {
    var cache = 0;
    for (final dir in await _cacheDirectories()) {
      cache += await _folderSize(dir);
    }
    final incompleteFiles = await _unusedPartials();
    var incomplete = 0;
    for (final file in incompleteFiles) {
      try {
        incomplete += await file.length();
      } catch (error) {
        debugPrint('[StorageCache] Partial file stat: ' + error.toString());
      }
    }
    var saved = 0;
    final seen = <String>{};
    for (final task in DownloadService.instance.tasksNotifier.value) {
      if (task.status != DownloadStatus.completed) continue;
      if (!seen.add(p.normalize(task.targetFilePath))) continue;
      final file = File(task.targetFilePath);
      try {
        if (await file.exists()) saved += await file.length();
      } catch (error) {
        debugPrint('[StorageCache] Saved file stat: ' + error.toString());
      }
    }
    return StorageSnapshot(
      temporaryBytes: cache,
      incompleteBytes: incomplete,
      savedBytes: saved,
      incompleteCount: incompleteFiles.length,
    );
  }

  Future<StorageCleanupResult> clearStreamingCache() async {
    if (hasActiveDownloads) {
      throw StateError('Pause or finish active downloads first.');
    }
    // Removes torrent sessions but retains sessions used for downloads.
    await TorrentStreamService().cleanup();
    var freed = 0;
    var count = 0;
    final errors = <String>[];
    for (final dir in await _cacheDirectories()) {
      if (!await dir.exists()) continue;
      await for (final entry in dir.list(followLinks: false)) {
        try {
          if (entry is File) {
            final bytes = await entry.length();
            await entry.delete();
            freed += bytes;
            count++;
          } else if (entry is Directory) {
            final bytes = await _folderSize(entry);
            await entry.delete(recursive: true);
            freed += bytes;
            count++;
          } else if (entry is Link) {
            await entry.delete();
            count++;
          }
        } catch (error) {
          errors.add(entry.path + ': ' + error.toString());
          debugPrint('[StorageCache] Cache delete failed: ' + error.toString());
        }
      }
    }
    return StorageCleanupResult(freed, count, errors);
  }

  Future<StorageCleanupResult> clearUnusedDownloads() async {
    if (hasActiveDownloads) {
      throw StateError('Pause or finish active downloads first.');
    }
    var freed = 0;
    var count = 0;
    final errors = <String>[];
    for (final file in await _unusedPartials()) {
      try {
        final bytes = await file.length();
        await file.delete();
        freed += bytes;
        count++;
      } catch (error) {
        errors.add(file.path + ': ' + error.toString());
      }
    }
    return StorageCleanupResult(freed, count, errors);
  }

  /// Best effort limit for app-owned cache, pruning only files older than 24h.
  Future<void> pruneOldTemporaryCache() async {
    if (hasActiveDownloads) return;
    try {
      final roots = await _cacheDirectories();
      var size = 0;
      final old = <({File file, int bytes, DateTime modified})>[];
      final cutoff = DateTime.now().subtract(const Duration(hours: 24));
      for (final dir in roots) {
        size += await _folderSize(dir);
        if (!await dir.exists()) continue;
        await for (final entry in dir.list(recursive: true, followLinks: false)) {
          if (entry is! File) continue;
          try {
            final modified = await entry.lastModified();
            if (modified.isBefore(cutoff)) {
              old.add((file: entry, bytes: await entry.length(), modified: modified));
            }
          } catch (error) {
            debugPrint('[StorageCache] Cache prune stat: ' + error.toString());
          }
        }
      }
      if (size <= maxTemporaryBytes) return;
      old.sort((a, b) => a.modified.compareTo(b.modified));
      for (final entry in old) {
        if (size <= maxTemporaryBytes) break;
        try {
          await entry.file.delete();
          size -= entry.bytes;
        } catch (error) {
          debugPrint('[StorageCache] Cache prune delete: ' + error.toString());
        }
      }
    } catch (error, stack) {
      debugPrint('[StorageCache] Auto cleanup: ' + error.toString() + '\n' + stack.toString());
    }
  }
}
