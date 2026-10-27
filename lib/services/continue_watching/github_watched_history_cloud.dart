import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../my_list/github_library_cloud.dart';
import 'github_sync_transport.dart';
import 'watched_history_service.dart';

/// Independent, title-level watched history; never overwrites Continue
/// Watching or the independently maintained watchlist. New file, old format
/// remains valid. False "completed" for one episode must never mark its series.
abstract final class GitHubWatchedHistoryMerge {
  static Map<String, dynamic> decode(String text) {
    final raw = jsonDecode(text);
    if (raw is! Map || raw['version'] != 1 || raw['records'] is! Map) {
      throw const FormatException('Unsupported watched history format');
    }
    return Map<String, dynamic>.from(raw['records'] as Map);
  }

  static Map<String, dynamic> toRecord(WatchedTitle item) => {
    'updatedAt': item.lastWatchedAt.toUtc().toIso8601String(),
    'deleted': false,
    'item': item.toJson(),
  };

  static DateTime changed(dynamic record) {
    if (record is! Map) return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    return DateTime.tryParse(record['updatedAt']?.toString() ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }

  static bool completed(dynamic record) {
    if (record is! Map || record['item'] is! Map) return false;
    return (record['item'] as Map)['completed'] == true;
  }

  static Map<String, dynamic> merge(
      Map<String, dynamic> remote, Map<String, dynamic> changes, {
        List<WatchedTitle> firstImport = const [],
      }) {
    final result = Map<String, dynamic>.from(remote);
    for (final watched in firstImport) {
      result.putIfAbsent(watched.identity, () => toRecord(watched));
    }
    for (final entry in changes.entries) {
      final current = result[entry.key];
      if (current == null || !changed(entry.value).isBefore(changed(current))) {
        final next = Map<String, dynamic>.from(entry.value as Map);
        if (completed(current) && !completed(next) && next['item'] is Map) {
          next['item'] = Map<String, dynamic>.from(next['item'] as Map)
            ..['completed'] = true;
        }
        result[entry.key] = next;
      } else if (completed(entry.value) && !completed(current) &&
          current is Map && current['item'] is Map) {
        final next = Map<String, dynamic>.from(current);
        next['item'] = Map<String, dynamic>.from(current['item'] as Map)
          ..['completed'] = true;
        result[entry.key] = next;
      }
    }
    return result;
  }

  static List<WatchedTitle> visible(Map<String, dynamic> records) {
    final results = <String, WatchedTitle>{};
    for (final record in records.values) {
      if (record is! Map || record['deleted'] == true) continue;
      final item = WatchedTitle.fromJson(record['item']);
      if (item == null) continue;
      final original = results[item.identity];
      if (original == null ||
          item.lastWatchedAt.isAfter(original.lastWatchedAt)) {
        results[item.identity] = item;
      }
    }
    return results.values.toList()
      ..sort((a, b) => b.lastWatchedAt.compareTo(a.lastWatchedAt));
  }
}

class GitHubWatchedHistoryCloud {
  GitHubWatchedHistoryCloud._();
  static final instance = GitHubWatchedHistoryCloud._();
  static const path = 'playtorrio/watched-history-v1.json';
  static const _suffix = 'playtorrio_watched_history_';

  final status = ValueNotifier<String>('Watched history saved locally');
  final isSyncing = ValueNotifier<bool>(false);
  final Map<String, Map<String, dynamic>> _pending = {};
  Future<void> _journalWrite = Future<void>.value();
  Future<void>? _activeSync;
  Timer? _timer;
  bool _imported = false;
  String _account = '';
  DateTime? _lastDownload;
  String? _etag;
  Map<String, dynamic>? _cached;
  String? _cachedSha;

  GitHubLibraryCloud get _connection => GitHubLibraryCloud.instance;
  bool get configured => _connection.configured;
  String get _accountKey => _connection.repository + ':' + _connection.branch;
  String get _journalKey => _suffix + 'pending:' + _accountKey;
  String get _importKey => _suffix + 'imported:' + _accountKey;
  int get queuedChanges => _pending.length;
  DateTime? get lastSuccessfulSync => _lastDownload;

  Future<void> _prepare() async {
    if (!configured) return;
    final account = _accountKey;
    if (_account == account) return;
    final prefs = await SharedPreferences.getInstance();
    _account = account;
    _pending.clear();
    _etag = null;
    _cached = null;
    _cachedSha = null;
    try {
      final value = prefs.getString(_journalKey);
      if (value != null) {
        final map = jsonDecode(value) as Map<String, dynamic>;
        for (final entry in map.entries) {
          if (entry.value is Map) {
            _pending[entry.key] =
                Map<String, dynamic>.from(entry.value as Map);
          }
        }
      }
    } catch (_) {
      status.value = 'Cannot load offline watched-history changes';
    }
    _imported = prefs.getBool(_importKey) ?? false;
  }

  void save(WatchedTitle item) {
    if (!configured) return;
    _journalWrite = _journalWrite.then((_) async {
      await _prepare();
      if (!configured) return;
      _pending[item.identity] = GitHubWatchedHistoryMerge.toRecord(item);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_journalKey, jsonEncode(_pending));
    }).catchError((Object error) {
      status.value = 'Unable to queue watched-history update locally';
    });
    // Independent, low-frequency writes. Never create a commit every tick.
    _timer ??= Timer(const Duration(minutes: 4), () {
      _timer = null;
      unawaited(WatchedHistoryService.syncGitHubHistory());
    });
  }

  Future<void> sync({
    required List<WatchedTitle> Function() readLocal,
    required Future<void> Function(List<WatchedTitle>) persist,
    bool force = false,
  }) async {
    await _connection.initialize();
    if (!configured) return;
    if (!force && _lastDownload != null &&
        DateTime.now().difference(_lastDownload!) <
            const Duration(seconds: 50)) return;
    if (_activeSync != null) { await _activeSync; return; }
    final operation = _sync(readLocal, persist);
    _activeSync = operation;
    try { await operation; } finally { _activeSync = null; }
  }

  Future<void> _sync(
    List<WatchedTitle> Function() readLocal,
    Future<void> Function(List<WatchedTitle>) persist,
  ) async {
    await _journalWrite;
    await _prepare();
    if (!configured) return;
    final account = _accountKey;
    final snapshot = {
      for (final entry in _pending.entries)
        entry.key: Map<String, dynamic>.from(entry.value),
    };
    final firstImport = _imported ? <WatchedTitle>[] : readLocal();
    isSyncing.value = true;
    status.value = 'Syncing watched history...';
    final client = http.Client();
    try {
      Map<String, dynamic>? result;
      for (var attempt = 0; attempt < 4; attempt++) {
        if (!configured || account != _accountKey) return;
        GitHubSyncGate.checkAllowed();
        final uri = Uri.https('api.github.com',
            '/repos/' + _connection.repository + '/contents/' + path);
        final headers = <String, String>{..._headers};
        if (_cached != null && _cachedSha != null && _etag != null) {
          headers['If-None-Match'] = _etag!;
        }
        final response = await client.get(
          uri.replace(queryParameters: {'ref': _connection.branch}),
          headers: headers,
        ).timeout(const Duration(seconds: 18));
        GitHubSyncGate.inspect(response);
        late Map<String, dynamic> remote;
        String? sha;
        if (response.statusCode == 304 &&
            _cached != null && _cachedSha != null) {
          remote = Map<String, dynamic>.from(_cached!);
          sha = _cachedSha;
        } else if (response.statusCode == 404) {
          // Missing only on initial rollout. Do not erase an existing file.
          remote = <String, dynamic>{};
          _etag = null;
          _cached = null;
          _cachedSha = null;
        } else if (response.statusCode == 200) {
          final parsed = jsonDecode(response.body) as Map<String, dynamic>;
          remote = GitHubWatchedHistoryMerge.decode(
              utf8.decode(base64Decode(
                  (parsed['content'] as String).replaceAll(RegExp(r'\s+'), ''))));
          sha = parsed['sha']?.toString();
          if (sha == null || sha.isEmpty) {
            throw const FormatException('GitHub history SHA missing');
          }
          _etag = response.headers['etag'];
          _cachedSha = sha;
          _cached = Map<String, dynamic>.from(remote);
        } else {
          throw StateError('History read HTTP ' +
              response.statusCode.toString());
        }
        final merged = GitHubWatchedHistoryMerge.merge(remote, snapshot,
            firstImport: firstImport);
        if (jsonEncode(remote) != jsonEncode(merged)) {
          final payload = <String, dynamic>{
            'branch': _connection.branch,
            if (sha != null) 'sha': sha,
            'message': 'history: sync watched titles',
            'content': base64Encode(utf8.encode(
                jsonEncode({'version': 1, 'records': merged}))),
          };
          final write = await GitHubSyncGate.write(() => client.put(
            uri, headers: {..._headers, 'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          ).timeout(const Duration(seconds: 30)));
          if (write.statusCode == 409) {
            _etag = null;
            _cached = null;
            await Future<void>.delayed(
                Duration(milliseconds: 900 * (attempt + 1)));
            continue;
          }
          if (write.statusCode != 200 && write.statusCode != 201) {
            throw StateError('History write HTTP ' +
                write.statusCode.toString());
          }
          _etag = null;
          _cached = null;
        }
        result = merged;
        break;
      }
      if (result == null) throw StateError('History conflict; try again');
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
      await persist(GitHubWatchedHistoryMerge.visible(
          GitHubWatchedHistoryMerge.merge(result, _pending)));
      status.value = 'Watched history synced · 0 queued';
    } on GitHubSyncDeferred catch (_) {
      status.value = 'GitHub busy; watched history queued locally';
    } catch (error) {
      status.value = 'History sync failed; edits queued locally (' +
          error.runtimeType.toString() + ')';
    } finally {
      client.close();
      isSyncing.value = false;
    }
  }

  Map<String, String> get _headers => {
    'Accept': 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28',
    'User-Agent': 'PlayTorrio-Watched-History',
    'Authorization': 'Bearer ' + (_connection.progressAccessToken ?? ''),
  };
}
