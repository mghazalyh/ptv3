import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/my_list/my_list_item.dart';
import '../continue_watching/github_sync_transport.dart';

enum GitHubLibraryState { disconnected, syncing, synced, failed }

/// GitHub JSON contents with explicit deletions and optimistic SHA updates.
/// Same v1 records; newly edited records add updatedAt in UTC.
/// Untouched legacy entries are preserved exactly (no unsolicited migration).
abstract final class GitHubLibraryMerge {
  static Map<String, dynamic> decode(String source) {
    final parsed = jsonDecode(source);
    if (parsed is! Map || parsed['version'] != 1 ||
        parsed['records'] is! Map) {
      throw const FormatException('Invalid watchlist database version');
    }
    return Map<String, dynamic>.from(parsed['records'] as Map);
  }

  static DateTime timestamp(Object? raw) {
    const epochMs = 0;
    if (raw is! Map) {
      return DateTime.fromMillisecondsSinceEpoch(epochMs, isUtc: true);
    }
    final updated = MyListNormalize.legacyDate(raw['updatedAt']);
    if (updated != null) return updated;
    final item = raw['item'];
    return item is Map
        ? MyListNormalize.legacyDate(item['addedAt']) ??
            DateTime.fromMillisecondsSinceEpoch(epochMs, isUtc: true)
        : DateTime.fromMillisecondsSinceEpoch(epochMs, isUtc: true);
  }

  static Map<String, dynamic> toRecord(MyListItem item, {
    bool deleted = false, DateTime? changedAt,
  }) => {
    'updatedAt': (changedAt ?? DateTime.now()).toUtc().toIso8601String(),
    'deleted': deleted,
    'item': item.toJson(),
  };

  static Map<String, dynamic> merge(
    Map<String, dynamic> remote,
    Map<String, Map<String, dynamic>> pending, {
    List<MyListItem> importLocal = const [],
  }) {
    final output = Map<String, dynamic>.from(remote);
    for (final item in importLocal) {
      // A device's first import never resurrects a remote deleted title.
      output.putIfAbsent(item.uniqueKey,
          () => toRecord(item, changedAt: item.addedAt));
    }
    for (final edit in pending.entries) {
      final current = output[edit.key];
      // Newer remote delete/re-add wins over a stale offline action.
      if (current == null ||
          !timestamp(edit.value).isBefore(timestamp(current))) {
        output[edit.key] = Map<String, dynamic>.from(edit.value);
      }
    }
    return output;
  }

  static List<MyListItem> visible(Map<String, dynamic> records) {
    final byKey = <String, MyListItem>{};
    for (final record in records.values) {
      if (record is! Map || record['deleted'] == true) continue;
      final raw = record['item'];
      if (raw is! Map) continue;
      try {
        final item = MyListItem.fromJson(Map<String, dynamic>.from(raw));
        if (item.title.trim().isEmpty || item.title == 'Unknown') continue;
        final previous = byKey[item.uniqueKey];
        if (previous == null || item.addedAt.isAfter(previous.addedAt)) {
          byKey[item.uniqueKey] = item;
        }
      } catch (_) {
        // One malformed item must not destroy the valid watchlist.
      }
    }
    final result = byKey.values.toList()
      ..sort((a, b) => b.addedAt.compareTo(a.addedAt));
    return result;
  }
}

class GitHubLibraryCloud {
  GitHubLibraryCloud._();
  static final GitHubLibraryCloud instance = GitHubLibraryCloud._();

  static const defaultRepo = 'mghazalyh/ptv3';
  static const defaultBranch = 'library-data';
  static const filePath = 'playtorrio/watchlist-v1.json';
  static const _tokenName = 'playtorrio_github_library_pat_v1';
  static const _prefsRepo = 'playtorrio_github_library_repo_v1';
  static const _prefsBranch = 'playtorrio_github_library_branch_v1';
  static const _prefsEnabled = 'playtorrio_github_library_enabled_v1';
  static const _secureStorage = FlutterSecureStorage();

  final ValueNotifier<bool> enabled = ValueNotifier<bool>(false);
  final ValueNotifier<GitHubLibraryState> state =
      ValueNotifier<GitHubLibraryState>(GitHubLibraryState.disconnected);
  final ValueNotifier<String> status =
      ValueNotifier<String>('Library saved locally');
  String repository = defaultRepo;
  String branch = defaultBranch;
  String? _token;
  bool _loaded = false;
  bool _imported = false;
  int _revision = 0;
  DateTime? _lastSuccessfulSync;
  String? _etag;
  String? _cachedSha;
  Map<String, dynamic>? _cachedRemote;
  final Map<String, Map<String, dynamic>> _pending = {};
  Future<void> _journalWrite = Future<void>.value();
  Future<void>? _activeSync;

  int get queuedChanges => _pending.length;
  DateTime? get lastSuccessfulSync => _lastSuccessfulSync;
  void _clearReadCache() { _etag = null; _cachedSha = null; _cachedRemote = null; }

  String get _journalKey => 'playtorrio_gh_pending:$repository:$branch';
  String get _importKey => 'playtorrio_gh_imported:$repository:$branch';
  bool get configured => enabled.value && (_token?.isNotEmpty ?? false);

  // Shared credentials for the private progress database in the same repo.
  // Never log, upload, or embed this token in the database contents.
  String? get progressAccessToken => configured ? _token : null;

  Future<void> initialize() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    repository = prefs.getString(_prefsRepo) ?? defaultRepo;
    branch = prefs.getString(_prefsBranch) ?? defaultBranch;
    enabled.value = prefs.getBool(_prefsEnabled) ?? false;
    try {
      _token = await _secureStorage.read(key: _tokenName);
    } catch (_) {
      _token = null;
    }
    _loadPending(prefs);
    _imported = prefs.getBool(_importKey) ?? false;
    if (enabled.value && _token == null) {
      status.value = 'Enter your GitHub key in Settings';
      state.value = GitHubLibraryState.failed;
    }
    _loaded = true;
  }

  void _loadPending(SharedPreferences prefs) {
    _pending.clear();
    try {
      final stored = prefs.getString(_journalKey);
      if (stored == null) return;
      final data = jsonDecode(stored) as Map<String, dynamic>;
      for (final entry in data.entries) {
        if (entry.value is Map) {
          _pending[entry.key] = Map<String, dynamic>.from(entry.value as Map);
        }
      }
    } catch (_) {
      status.value = 'Cannot read pending offline changes';
    }
  }

  Future<void> configure({
    required String repo,
    required String targetBranch,
    String? accessToken,
  }) async {
    final name = repo.trim();
    final ref = targetBranch.trim();
    if (!RegExp(r'^[\w.-]+/[\w.-]+$').hasMatch(name) ||
        !RegExp(r'^[\w./-]+$').hasMatch(ref) ||
        ref.isEmpty || ref.contains('..') ||
        ref.startsWith('/') || ref.endsWith('/')) {
      throw const FormatException('Invalid repository or branch');
    }
    await _journalWrite;
    final incoming = accessToken?.trim();
    if (incoming != null && incoming.isNotEmpty) {
      await _secureStorage.write(key: _tokenName, value: incoming);
      _token = incoming;
    }
    if (_token == null || _token!.isEmpty) {
      throw const FormatException('Paste a GitHub token with Contents read/write');
    }
    final prefs = await SharedPreferences.getInstance();
    repository = name;
    branch = ref;
    _loadPending(prefs);
    _imported = prefs.getBool(_importKey) ?? false;
    _revision++;
    _clearReadCache();
    _lastSuccessfulSync = null;
    await prefs.setString(_prefsRepo, repository);
    await prefs.setString(_prefsBranch, branch);
    await prefs.setBool(_prefsEnabled, true);
    enabled.value = true;
    state.value = GitHubLibraryState.disconnected;
    status.value = 'Connected — ready to sync';
  }

  Future<void> disconnect() async {
    await _journalWrite;
    await (await SharedPreferences.getInstance()).setBool(_prefsEnabled, false);
    await _secureStorage.delete(key: _tokenName);
    _revision++;
    _clearReadCache();
    _lastSuccessfulSync = null;
    _token = null;
    enabled.value = false;
    state.value = GitHubLibraryState.disconnected;
    status.value = 'Library saved locally';
  }

  void recordEdit(MyListItem item, {required bool added}) {
    if (!configured) return;
    _pending[item.uniqueKey] =
        GitHubLibraryMerge.toRecord(item, deleted: !added);
    _journalWrite = _journalWrite.then((_) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_journalKey, jsonEncode(_pending));
    }).catchError((Object _) {
      status.value = 'Cannot save offline edit queue';
    });
  }

  Uri get _readUri => Uri.https('api.github.com',
      '/repos/$repository/contents/$filePath', {'ref': branch});
  Uri get _writeUri => Uri.https('api.github.com',
      '/repos/$repository/contents/$filePath');
  Map<String, String> get _headers => {
    'Accept': 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28',
    'Authorization': 'Bearer $_token',
    'User-Agent': 'PlayTorrio-GitHub-Library',
  };

  Future<({Map<String, dynamic> data, String sha})> _fetch(
      http.Client client) async {
    GitHubSyncGate.checkAllowed();
    final headers = Map<String, String>.from(_headers);
    if (_etag != null && _cachedSha != null && _cachedRemote != null) {
      headers['If-None-Match'] = _etag!;
    }
    final response = await client.get(_readUri, headers: headers)
        .timeout(const Duration(seconds: 18));
    GitHubSyncGate.inspect(response);
    if (response.statusCode == 304 &&
        _cachedRemote != null && _cachedSha != null) {
      return (data: Map<String, dynamic>.from(_cachedRemote!), sha: _cachedSha!);
    }
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw StateError('GitHub key invalid or Contents permission missing');
    }
    if (response.statusCode == 404) {
      throw StateError('GitHub repository, branch or database file not found');
    }
    if (response.statusCode != 200) {
      throw StateError('GitHub read HTTP ' + response.statusCode.toString());
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final encoded = (json['content'] as String).replaceAll(RegExp(r'\s+'), '');
    final remote = GitHubLibraryMerge.decode(utf8.decode(base64Decode(encoded)));
    final sha = json['sha']?.toString() ?? '';
    if (sha.isEmpty) throw const FormatException('GitHub watchlist SHA missing');
    _cachedRemote = Map<String, dynamic>.from(remote);
    _cachedSha = sha;
    _etag = response.headers['etag'];
    return (data: remote, sha: sha);
  }

  /// Optimistic SHA updates: only 409 is an edit conflict. 422 is not.
  Future<void> sync({
    required List<MyListItem> Function() readLocal,
    required Future<void> Function(List<MyListItem>) persistMerged,
  }) async {
    if (!configured) return;
    if (_activeSync != null) {
      await _activeSync;
      return;
    }
    final action = _doSync(readLocal, persistMerged);
    _activeSync = action;
    try {
      await action;
    } finally {
      _activeSync = null;
    }
  }

  Future<void> _doSync(
    List<MyListItem> Function() readLocal,
    Future<void> Function(List<MyListItem>) persistMerged,
  ) async {
    final epoch = _revision;
    state.value = GitHubLibraryState.syncing;
    status.value = 'Syncing watchlist with GitHub...';
    await _journalWrite;
    final snapshot = {
      for (final e in _pending.entries)
        e.key: Map<String, dynamic>.from(e.value),
    };
    final imports = _imported ? <MyListItem>[] : readLocal();
    final client = http.Client();
    try {
      Map<String, dynamic>? result;
      for (var attempt = 0; attempt < 4; attempt++) {
        if (!configured || epoch != _revision) return;
        final current = await _fetch(client);
        final merged = GitHubLibraryMerge.merge(current.data, snapshot,
            importLocal: imports);
        if (jsonEncode(current.data) != jsonEncode(merged)) {
          final content = jsonEncode({'version': 1, 'records': merged});
          final response = await GitHubSyncGate.write(() => client.put(
            _writeUri,
            headers: {..._headers, 'Content-Type': 'application/json'},
            body: jsonEncode({
              'message': 'library: sync watchlist',
              'branch': branch,
              'sha': current.sha,
              'content': base64Encode(utf8.encode(content)),
            }),
          ).timeout(const Duration(seconds: 30)));
          if (response.statusCode == 409) {
            _clearReadCache();
            await Future<void>.delayed(
                Duration(milliseconds: 1200 * (attempt + 1)));
            continue;
          }
          if (response.statusCode == 422) {
            throw StateError('GitHub rejected watchlist update (validation)');
          }
          if (response.statusCode != 200 && response.statusCode != 201) {
            throw StateError('GitHub write HTTP ' +
                response.statusCode.toString());
          }
          _clearReadCache();
        }
        result = merged;
        break;
      }
      if (result == null) {
        throw StateError('Other devices are editing; retry synchronization');
      }
      if (epoch != _revision || !configured) return;
      for (final entry in snapshot.entries) {
        if (mapEquals(_pending[entry.key], entry.value)) {
          _pending.remove(entry.key);
        }
      }
      final prefs = await SharedPreferences.getInstance();
      _journalWrite = _journalWrite.then((_) async {
        await prefs.setString(_journalKey, jsonEncode(_pending));
        await prefs.setBool(_importKey, true);
      });
      await _journalWrite;
      _imported = true;
      _lastSuccessfulSync = DateTime.now();
      // Keep new edits made while the network request was in progress.
      await persistMerged(GitHubLibraryMerge.visible(
          GitHubLibraryMerge.merge(result, _pending)));
      state.value = GitHubLibraryState.synced;
      status.value = _pending.isEmpty ? 'Watchlist synced' :
          'Watchlist synced; ' + _pending.length.toString() + ' edits pending';
    } on GitHubSyncDeferred {
      state.value = GitHubLibraryState.failed;
      status.value = 'GitHub busy; ' + _pending.length.toString() +
          ' watchlist edits saved locally';
    } catch (error) {
      state.value = GitHubLibraryState.failed;
      status.value = 'Watchlist sync failed; ' + _pending.length.toString() +
          ' edits saved locally';
      debugPrint('[GitHubLibrary] Sync failed (' +
          error.runtimeType.toString() + ')');
    } finally {
      client.close();
    }
  }
}
