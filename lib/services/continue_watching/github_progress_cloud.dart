import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/continue_watching/continue_watching_item.dart';
import '../my_list/github_library_cloud.dart';
import 'github_sync_transport.dart';

/// Pure merge logic: the newest action for a show wins, including a completed
/// episode or deliberate removal (both represented as tombstones).
abstract final class GitHubProgressMerge {
  static Map<String, dynamic> decode(String jsonText) {
    final root = jsonDecode(jsonText);
    if (root is! Map || root['version'] != 1 || root['records'] is! Map) {
      throw const FormatException('Unsupported Continue Watching database');
    }
    return Map<String, dynamic>.from(root['records'] as Map);
  }

  static Map<String, dynamic> toRecord(ContinueWatchingItem item,
      {bool removed = false, DateTime? changedAt}) {
    final metadata = Map<String, dynamic>.from(item.toJson())
      ..remove('rawUrl')
      ..remove('magnetUrl')
      ..remove('infoHash')
      ..remove('headers')
      ..remove('fileIdx')
      ..remove('streamTitle');
    metadata['lastWatchedAt'] = item.lastWatchedAt.toUtc().toIso8601String();
    // Streaming source URLs frequently contain per-user credentials or
    // expiring tokens. Resume playback will rescrape the preferred provider.
    return {
      'updatedAt': (changedAt ?? item.lastWatchedAt).toUtc().toIso8601String(),
      'deleted': removed || item.isCompleted,
      'item': metadata,
    };
  }

  static DateTime timestamp(dynamic record) {
    if (record is! Map) return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    return DateTime.tryParse(record['updatedAt']?.toString() ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }

  static Map<String, dynamic> merge(Map<String, dynamic> remote,
      Map<String, Map<String, dynamic>> edits,
      {List<ContinueWatchingItem> firstImport = const []}) {
    final records = Map<String, dynamic>.from(remote);
    for (final item in firstImport) {
      records.putIfAbsent(item.sessionKey,
          () => toRecord(item, changedAt: item.lastWatchedAt));
    }
    for (final entry in edits.entries) {
      final existing = records[entry.key];
      if (existing == null ||
          !timestamp(entry.value).isBefore(timestamp(existing))) {
        records[entry.key] = Map<String, dynamic>.from(entry.value);
      }
    }
    return records;
  }

  static List<ContinueWatchingItem> visible(Map<String, dynamic> records) {
    final sessions = <ContinueWatchingItem>[];
    for (final data in records.values) {
      if (data is! Map || data['deleted'] == true) continue;
      final content = data['item'];
      if (content is! Map) continue;
      try {
        final normalized = Map<String, dynamic>.from(content);
        final watched = normalized['lastWatchedAt']?.toString() ?? '';
        if (watched.isNotEmpty &&
            !RegExp(r'(Z|[+-]\d{2}:?\d{2})$').hasMatch(watched)) {
          final utc = data['updatedAt']?.toString();
          if (utc != null && DateTime.tryParse(utc) != null) {
            normalized['lastWatchedAt'] = utc;
          }
        }
        final item = ContinueWatchingItem.fromJson(normalized);
        if (!item.isCompleted && item.positionSeconds > 10) sessions.add(item);
      } catch (_) {
        // Ignore one malformed record without losing the other shows.
      }
    }
    sessions.sort((a, b) => b.lastWatchedAt.compareTo(a.lastWatchedAt));
    return sessions;
  }
}

/// Uses the SAME private GitHub repository and device token as My List.
/// Commits are throttled: local player progress can update every five seconds
/// without creating a GitHub commit for every single playback tick.
class GitHubProgressCloud {
  GitHubProgressCloud._();
  static final GitHubProgressCloud instance = GitHubProgressCloud._();
  static const path = 'playtorrio/continue-watching-v1.json';

  final ValueNotifier<String> status =
      ValueNotifier<String>('Continue Watching stored locally');
  final ValueNotifier<bool> isSyncing = ValueNotifier<bool>(false);
  final Map<String, Map<String, dynamic>> _pending = {};
  Future<void> _journalWrite = Future<void>.value();
  Future<void>? _activeSync;
  Timer? _uploadTimer;
  Future<void> Function()? flushPending;
  String _account = '';
  bool _imported = false;
  DateTime? _lastDownload;
  String? _etag;
  String? _cachedAccount;
  String? _cachedSha;
  Map<String, dynamic>? _cachedRecords;

  GitHubLibraryCloud get _connection => GitHubLibraryCloud.instance;
  bool get configured => _connection.configured;
  String get _accountKey => _connection.repository + ':' + _connection.branch;
  String get _journalKey => 'playtorrio_progress_pending:' + _accountKey;
  String get _importKey => 'playtorrio_progress_imported:' + _accountKey;

  Future<void> _prepare() async {
    if (!configured) return;
    final currentAccount = _accountKey;
    if (_account == currentAccount) return;
    // Called from the serialized journal writer as well; awaiting the
    // journal here would deadlock playback updates.
    final prefs = await SharedPreferences.getInstance();
    _account = currentAccount;
    _pending.clear();
    _etag = null;
    _cachedAccount = null;
    _cachedSha = null;
    _cachedRecords = null;
    try {
      final text = prefs.getString(_journalKey);
      if (text != null) {
        final entries = jsonDecode(text) as Map<String, dynamic>;
        for (final e in entries.entries) {
          if (e.value is Map) {
            _pending[e.key] = Map<String, dynamic>.from(e.value as Map);
          }
        }
      }
    } catch (_) {
      status.value = 'Cannot read offline progress queue';
    }
    _imported = prefs.getBool(_importKey) ?? false;
  }

  void save(ContinueWatchingItem item, {bool removed = false}) {
    if (!configured) return;
    _writeAfterPrepare(item, removed: removed);
  }

  void _writeAfterPrepare(ContinueWatchingItem item, {required bool removed}) {
    _journalWrite = _journalWrite.then((_) async {
      await _prepare();
      if (!configured) return;
      _pending[item.sessionKey] =
          GitHubProgressMerge.toRecord(item, removed: removed);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_journalKey, jsonEncode(_pending));
    }).catchError((Object error) {
      debugPrint('[GitHubProgress] Pending progress write failed (' +
          error.runtimeType.toString() + ')');
    });
    // Do NOT reset the timer on each playback tick.
    _uploadTimer ??= Timer(const Duration(minutes: 4), () {
      _uploadTimer = null;
      // Use the owner service for a full sync: it supplies the complete local
      // import and updates the visible Continue Watching shelf.
      final flush = flushPending;
      if (flush != null) unawaited(flush());
    });
  }

  /// Explicit refresh, screen entry or player exit can upload immediately.
  int get queuedChanges => _pending.length;
  DateTime? get lastSuccessfulSync => _lastDownload;

  Future<void> sync({
    required List<ContinueWatchingItem> Function() readLocal,
    required Future<void> Function(List<ContinueWatchingItem>) persist,
    bool force = false,
  }) async {
    if (!configured) return;
    if (!force && _pending.isEmpty && _lastDownload != null &&
        DateTime.now().difference(_lastDownload!) <
            const Duration(seconds: 45)) return;
    final previous = _activeSync;
    if (previous != null) {
      await previous;
      return;
    }
    final operation = _sync(readLocal, persist);
    _activeSync = operation;
    try {
      await operation;
    } finally {
      _activeSync = null;
    }
  }

  Future<void> _sync(
    List<ContinueWatchingItem> Function() readLocal,
    Future<void> Function(List<ContinueWatchingItem>) persist,
  ) async {
    await _journalWrite;
    await _prepare();
    if (!configured) return;
    final account = _accountKey;
    isSyncing.value = true;
    status.value = 'Syncing Continue Watching...';
    final snapshot = {
      for (final e in _pending.entries)
        e.key: Map<String, dynamic>.from(e.value),
    };
    final import = _imported ? <ContinueWatchingItem>[] : readLocal();
    final client = http.Client();
    try {
      Map<String, dynamic>? result;
      for (int tries = 0; tries < 4; tries++) {
        if (!configured || account != _accountKey) return;
        GitHubSyncGate.checkAllowed();
        final base = Uri.https('api.github.com',
            '/repos/' + _connection.repository + '/contents/' + path);
        final readHeaders = <String, String>{..._headers};
        if (_cachedAccount == account && _cachedRecords != null &&
            _cachedSha != null && _etag != null) {
          readHeaders['If-None-Match'] = _etag!;
        }
        final response = await client.get(
          base.replace(queryParameters: {'ref': _connection.branch}),
          headers: readHeaders,
        ).timeout(const Duration(seconds: 18));
        GitHubSyncGate.inspect(response);
        late Map<String, dynamic> remote;
        late String sha;
        if (response.statusCode == 304 &&
            _cachedAccount == account && _cachedRecords != null &&
            _cachedSha != null) {
          remote = Map<String, dynamic>.from(_cachedRecords!);
          sha = _cachedSha!;
        } else if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final raw = (data['content'] as String)
              .replaceAll(RegExp(r'\s+'), '');
          remote = GitHubProgressMerge.decode(utf8.decode(base64Decode(raw)));
          sha = data['sha']?.toString() ?? '';
          if (sha.isEmpty) throw const FormatException('Missing GitHub blob SHA');
          _etag = response.headers['etag'];
          _cachedAccount = account;
          _cachedSha = sha;
          _cachedRecords = Map<String, dynamic>.from(remote);
        } else {
          throw StateError('GitHub progress read HTTP ' +
              response.statusCode.toString());
        }
        final merged = GitHubProgressMerge.merge(remote, snapshot,
            firstImport: import);
        if (jsonEncode(remote) != jsonEncode(merged)) {
          final write = await GitHubSyncGate.write(() => client.put(
            base,
            headers: {..._headers, 'Content-Type': 'application/json'},
            body: jsonEncode({
              'branch': _connection.branch,
              'sha': sha,
              'message': 'progress: sync Continue Watching sessions',
              'content': base64Encode(utf8.encode(
                  jsonEncode({'version': 1, 'records': merged}))),
            }),
          ).timeout(const Duration(seconds: 30)));
          if (write.statusCode == 409) {
            _etag = null;
            _cachedRecords = null;
            await Future<void>.delayed(
                Duration(milliseconds: 900 * (tries + 1)));
            continue;
          }
          if (write.statusCode != 200 && write.statusCode != 201) {
            throw StateError('GitHub progress write HTTP ' +
                write.statusCode.toString());
          }
          _etag = null;
          _cachedRecords = null;
        }
        result = merged;
        break;
      }
      if (result == null) throw StateError('Progress conflict; retry later');
      if (!configured || account != _accountKey) return;
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
      _lastDownload = DateTime.now();
      await persist(GitHubProgressMerge.visible(
          GitHubProgressMerge.merge(result, _pending)));
      status.value = 'Continue Watching synced · 0 queued';
    } on GitHubSyncDeferred catch (_) {
      status.value = 'GitHub busy; ${_pending.length} edits queued locally';
    } catch (error) {
      status.value = 'Progress sync failed; ${_pending.length} edits queued locally (' +
          error.runtimeType.toString() + ')';
      debugPrint('[GitHubProgress] Sync failed (' +
          error.runtimeType.toString() + ')');
    } finally {
      client.close();
      isSyncing.value = false;
    }
  }

  Map<String, String> get _headers => {
    'Accept': 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28',
    'User-Agent': 'PlayTorrio-Progress',
    'Authorization': 'Bearer ' + (_connection.progressAccessToken ?? ''),
  };
}
