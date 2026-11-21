import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Strictly bounded runtime switches for experimental Stremio Live TV only.
/// This is configuration, not remotely executed Dart/JavaScript code.
@immutable
class LiveTvExperimentPolicy {
  const LiveTvExperimentPolicy({
    required this.id,
    required this.expiresAtUtc,
    this.channelId,
    this.relayMode = 'auto',
    this.headerMode = 'addon',
    this.sourceOrder = 'ranked',
    this.failoverEnabled = true,
    this.relayAfterAttempts = 2,
    this.startupGraceSeconds = 14,
    this.stallSeconds = 13,
    this.feedSeconds = 9,
    this.cacheSeconds = 0,
  });

  final String id;
  final DateTime expiresAtUtc;
  final String? channelId;
  final String relayMode; // auto, never, prefer
  final String headerMode; // addon, browser, minimal
  final String sourceOrder; // ranked, original, reversed
  final bool failoverEnabled;
  final int relayAfterAttempts;
  final int startupGraceSeconds;
  final int stallSeconds;
  final int feedSeconds;
  final int cacheSeconds; // 0 means use the default adaptive cache

  static const allowedKeys = <String>{
    'schema', 'id', 'expiresAtUtc', 'channelId', 'relayMode',
    'failoverEnabled', 'relayAfterAttempts', 'startupGraceSeconds',
    'stallSeconds', 'feedSeconds', 'cacheSeconds',
    'headerMode', 'sourceOrder',
  };

  static LiveTvExperimentPolicy parse(Map<String, dynamic> raw,
      {DateTime? now}) {
    final at = (now ?? DateTime.now()).toUtc();
    if (raw.keys.any((key) => !allowedKeys.contains(key)) ||
        raw['schema'] != 1) {
      throw const FormatException('Unsupported experiment schema or field');
    }
    final id = raw['id'];
    if (id is! String ||
        !RegExp(r'^[A-Za-z0-9_-]{6,64}$').hasMatch(id)) {
      throw const FormatException('Invalid experiment ID');
    }
    final expiryRaw = raw['expiresAtUtc'];
    if (expiryRaw is! String || !expiryRaw.endsWith('Z')) {
      throw const FormatException('UTC expiration required');
    }
    final expiry = DateTime.tryParse(expiryRaw)?.toUtc();
    if (expiry == null || !expiry.isAfter(at) ||
        expiry.difference(at) > const Duration(hours: 24)) {
      throw const FormatException('Experiment expiry must be within 24 hours');
    }
    final scope = raw['channelId'];
    if (scope != null && (scope is! String || scope.length > 180 ||
        !(scope.startsWith('nltv:') || scope.startsWith('iptv:')))) {
      throw const FormatException('Only Stremio TV channel IDs are allowed');
    }
    final mode = raw['relayMode'] ?? 'auto';
    if (mode is! String || !const <String>{'auto', 'never', 'prefer'}
        .contains(mode)) {
      throw const FormatException('Invalid relay mode');
    }
    final headerMode = raw['headerMode'] ?? 'addon';
    if (headerMode is! String ||
        !const <String>{'addon', 'browser', 'minimal'}
            .contains(headerMode)) {
      throw const FormatException('Invalid header mode');
    }
    final sourceOrder = raw['sourceOrder'] ?? 'ranked';
    if (sourceOrder is! String ||
        !const <String>{'ranked', 'original', 'reversed'}
            .contains(sourceOrder)) {
      throw const FormatException('Invalid source order');
    }
    final failover = raw['failoverEnabled'] ?? true;
    if (failover is! bool) {
      throw const FormatException('Invalid failover flag');
    }
    int bounded(String name, int defaultValue, int min, int max) {
      final value = raw[name] ?? defaultValue;
      if (value is! int || value < min || value > max) {
        throw FormatException('Invalid playback threshold: ' + name);
      }
      return value;
    }
    return LiveTvExperimentPolicy(
      id: id,
      expiresAtUtc: expiry,
      channelId: scope as String?,
      relayMode: mode,
      headerMode: headerMode,
      sourceOrder: sourceOrder,
      failoverEnabled: failover,
      relayAfterAttempts: bounded('relayAfterAttempts', 2, 0, 6),
      startupGraceSeconds: bounded('startupGraceSeconds', 14, 5, 90),
      stallSeconds: bounded('stallSeconds', 13, 5, 90),
      feedSeconds: bounded('feedSeconds', 9, 3, 60),
      cacheSeconds: bounded('cacheSeconds', 0, 0, 90),
    );
  }

  bool appliesTo(String id, DateTime at) =>
      expiresAtUtc.isAfter(at.toUtc()) &&
      (channelId == null || channelId == id) &&
      (id.startsWith('nltv:') || id.startsWith('iptv:'));

  Map<String, Object?> toJson() => <String, Object?>{
    'schema': 1,
    'id': id,
    'expiresAtUtc': expiresAtUtc.toUtc().toIso8601String(),
    if (channelId != null) 'channelId': channelId,
    'relayMode': relayMode,
    'headerMode': headerMode,
    'sourceOrder': sourceOrder,
    'failoverEnabled': failoverEnabled,
    'relayAfterAttempts': relayAfterAttempts,
    'startupGraceSeconds': startupGraceSeconds,
    'stallSeconds': stallSeconds,
    'feedSeconds': feedSeconds,
    'cacheSeconds': cacheSeconds,
  };
}

/// Device-local policy cache. Its only update path is the existing opted-in
/// Torriodb owner command channel. Expired policies fail closed to defaults.
class LiveTvExperimentStore {
  LiveTvExperimentStore._();

  static final LiveTvExperimentStore instance = LiveTvExperimentStore._();
  static const preferenceKey = 'live_tv_experiment_policy_v1';

  LiveTvExperimentPolicy? _active;
  String _lastRollback = 'none';
  int _revision = 0;
  int get revision => _revision;

  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final persisted = prefs.getString(preferenceKey);
      if (persisted == null || persisted.length > 4096) return;
      final data = jsonDecode(persisted);
      if (data is! Map) throw const FormatException('Invalid saved policy');
      _active = LiveTvExperimentPolicy.parse(
          Map<String, dynamic>.from(data));
      _revision++;
    } catch (error) {
      debugPrint('[LiveExperiment] Saved policy discarded: ' +
          error.runtimeType.toString());
      _active = null;
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(preferenceKey);
    }
  }

  LiveTvExperimentPolicy? forChannel(String channelId, {DateTime? now}) {
    final policy = _active;
    if (policy == null) return null;
    final at = (now ?? DateTime.now()).toUtc();
    return policy.appliesTo(channelId, at) ? policy : null;
  }

  Future<Map<String, Object?>> apply(Map<String, dynamic> raw) async {
    // No executable strings, arbitrary URLs, or HTTP headers are accepted.
    if (jsonEncode(raw).length > 4096) {
      return <String, Object?>{'accepted': false,
          'reason': 'experiment_too_large'};
    }
    try {
      final next = LiveTvExperimentPolicy.parse(raw);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(preferenceKey, jsonEncode(next.toJson()));
      _active = next;
      _revision++;
      _lastRollback = 'none';
      return status();
    } catch (error) {
      return <String, Object?>{
        'accepted': false, 'reason': 'invalid_experiment',
        'errorClass': error.runtimeType.toString(),
      };
    }
  }

  Future<Map<String, Object?>> rollback({String reason = 'owner'}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(preferenceKey);
    _active = null;
    _revision++;
    _lastRollback = reason;
    return status();
  }

  Map<String, Object?> status() {
    final policy = _active;
    final alive = policy != null &&
        policy.expiresAtUtc.isAfter(DateTime.now().toUtc());
    return <String, Object?>{
      'accepted': true,
      'active': alive,
      'revision': _revision,
      'lastRollback': _lastRollback,
      if (alive) 'policy': policy.toJson(),
    };
  }

  /// Revert a trial that made previously confirmed video repeatedly fail.
  /// Unverified/dead channels alone never trigger a spurious rollback.
  Future<bool> rollbackOnRegression({
    required String channelId,
    required bool hadConfirmedVideo,
    required int failedAttempts,
  }) async {
    if (!hadConfirmedVideo || failedAttempts < 3 ||
        forChannel(channelId) == null) return false;
    await rollback(reason: 'verified_playback_regression');
    return true;
  }
}
