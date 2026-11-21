import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Small, sanitized, app-owned summary of real native TV matrix observations.
/// The original per-candidate evidence remains in Torriodb; no stream URLs,
/// headers, passwords or tokens are retained by this summary.
class IosRemoteLiveHealthHistory {
  IosRemoteLiveHealthHistory();

  static final IosRemoteLiveHealthHistory instance =
      IosRemoteLiveHealthHistory();
  static const preferenceKey = 'ios_remote_live_health_history_v1';
  static const maximumChannels = 250;

  Future<void> _tail = Future<void>.value();

  /// Preserve event order when the native matrix finishes candidates quickly.
  Future<void> recordCandidate(Map<String, Object?> candidate) {
    final next = _tail.then((_) => _record(candidate));
    _tail = next.catchError((Object error, StackTrace stack) {
      debugPrint('[LiveHealthHistory] Record: ${error.runtimeType}');
    });
    return next;
  }

  Future<void> get whenIdle => _tail;

  Future<void> _record(Map<String, Object?> candidate) async {
    final id = candidate['channelId'];
    final title = candidate['title'];
    if (id is! String || id.length < 4 || id.length > 180 ||
        !(id.startsWith('nltv:') || id.startsWith('iptv:')) ||
        title is! String || title.trim().isEmpty || title.length > 120) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final records = _readRecords(prefs);
    final current = records[id] ?? <String, Object?>{
      'id': id, 'title': title, 'observations': 0,
      'verified': 0, 'failures': 0,
    };
    final observations = current['observations'] as int? ?? 0;
    final verified = current['verified'] as int? ?? 0;
    final failures = current['failures'] as int? ?? 0;
    final success = candidate['sustainedPlayback'] == true;
    final now = DateTime.now().toUtc().toIso8601String();
    current['title'] = title.trim();
    current['observations'] = (observations + 1).clamp(0, 1000000);
    current['verified'] = (verified + (success ? 1 : 0)).clamp(0, 1000000);
    current['failures'] = (failures + (success ? 0 : 1)).clamp(0, 1000000);
    current['lastTestedUtc'] = now;
    current['lastPassed'] = success;
    current['lastRunId'] = candidate['runId'] is String
        ? (candidate['runId'] as String).substring(
            0, (candidate['runId'] as String).length.clamp(0, 50))
        : null;
    if (success) {
      current['lastVerifiedUtc'] = now;
      current['lastVerifiedSourceIndex'] =
          candidate['requestedSourceVerified'] == true
              ? candidate['requestedSourceIndex']
              : candidate['activeSourceIndex'];
      current['lastVerificationWasFailover'] =
          candidate['sustainedAfterFailover'] == true;
    }
    records[id] = current;
    if (records.length > maximumChannels) {
      final ordered = records.entries.toList()
        ..sort((a, b) => (b.value['lastTestedUtc']?.toString() ?? '')
            .compareTo(a.value['lastTestedUtc']?.toString() ?? ''));
      records
        ..clear()
        ..addEntries(ordered.take(maximumChannels));
    }
    if (!await prefs.setString(preferenceKey,
        jsonEncode(records.values.toList()))) {
      throw StateError('Could not save Live TV health observations');
    }
  }

  Map<String, Map<String, Object?>> _readRecords(
      SharedPreferences prefs) {
    final encoded = prefs.getString(preferenceKey);
    if (encoded == null || encoded.isEmpty) return {};
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! List) return {};
      final result = <String, Map<String, Object?>>{};
      for (final value in decoded.take(maximumChannels)) {
        if (value is! Map) continue;
        final record = Map<String, Object?>.from(value);
        final id = record['id'];
        if (id is! String ||
            !(id.startsWith('nltv:') || id.startsWith('iptv:'))) continue;
        result[id] = record;
      }
      return result;
    } catch (error) {
      debugPrint('[LiveHealthHistory] Read: ${error.runtimeType}');
      return {};
    }
  }

  /// Ranking is historical, not a claim the channel currently plays.
  Future<Map<String, Object?>> rank(Map<String, dynamic> args) async {
    const keys = <String>{'query', 'limit', 'minVerified', 'maxAgeHours'};
    final query = args['query'] ?? '';
    final limit = args['limit'] ?? 10;
    final minVerified = args['minVerified'] ?? 1;
    final hours = args['maxAgeHours'] ?? 168;
    if (args.keys.any((key) => !keys.contains(key)) ||
        query is! String || query.length > 100 ||
        limit is! int || limit < 1 || limit > 50 ||
        minVerified is! int || minVerified < 0 || minVerified > 1000 ||
        hours is! int || hours < 1 || hours > 720) {
      return <String, Object?>{
        'accepted': false, 'reason': 'invalid_health_query',
      };
    }
    await _tail;
    final prefs = await SharedPreferences.getInstance();
    final entries = _readRecords(prefs).values.toList();
    final cutoff = DateTime.now().toUtc().subtract(Duration(hours: hours));
    final matches = entries.where((item) {
      if (!(item['title']?.toString().toLowerCase().contains(
          query.toLowerCase()) ?? false) &&
          !(item['id']?.toString().toLowerCase().contains(
              query.toLowerCase()) ?? false)) return false;
      if ((item['verified'] as int? ?? 0) < minVerified) return false;
      final tested = DateTime.tryParse(
          item['lastTestedUtc']?.toString() ?? '')?.toUtc();
      return tested != null && !tested.isBefore(cutoff);
    }).toList();
    double quality(Map<String, Object?> value) {
      final verified = value['verified'] as int? ?? 0;
      final count = value['observations'] as int? ?? 1;
      final coverage = (count.clamp(0, 3)) / 3.0;
      // Penalize one-off successes relative to repeated successful tests.
      return count == 0 ? 0 :
          (verified / count) * (0.6 + 0.4 * coverage);
    }
    matches.sort((a, b) {
      final byRate = quality(b).compareTo(quality(a));
      if (byRate != 0) return byRate;
      final byVerified = (b['verified'] as int? ?? 0)
          .compareTo(a['verified'] as int? ?? 0);
      if (byVerified != 0) return byVerified;
      return (b['lastVerifiedUtc']?.toString() ?? '')
          .compareTo(a['lastVerifiedUtc']?.toString() ?? '');
    });
    return <String, Object?>{
      'accepted': true,
      'evidence': 'historical_native_matrix',
      'notRealTimeAvailability': true,
      'maxAgeHours': hours,
      'matches': matches.length,
      'items': matches.take(limit).map((item) => <String, Object?>{
        ...item,
        'reliabilityPercent': (quality(item) * 100).round(),
      }).toList(),
    };
  }
}
