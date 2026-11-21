import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../player/ios_audio_telemetry.dart';

/// Sanitized process and framework exception evidence. Native hard crashes
/// cannot be caught from within the dying process. An unclosed foreground
/// marker is a clue, NOT definitive proof of a native crash.
class IosRemoteCrashEvidence {
  IosRemoteCrashEvidence();

  static final IosRemoteCrashEvidence instance =
      IosRemoteCrashEvidence();
  static const _activeKey = 'ios_remote_last_foreground_session_active_v1';
  static const _eventsKey = 'ios_remote_recent_exception_events_v1';
  static const maximumEvents = 12;

  Future<void> _tail = Future<void>.value();
  bool _initialized = false;
  bool _previousSessionUnclosed = false;
  bool _installed = false;
  List<Map<String, Object?>> _events = [];

  Future<void> initialize() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();
    _previousSessionUnclosed = prefs.getBool(_activeKey) ?? false;
    final raw = prefs.getString(_eventsKey);
    try {
      final decoded = raw == null ? null : jsonDecode(raw);
      if (decoded is List) {
        _events = decoded.whereType<Map>()
            .map((item) => Map<String, Object?>.from(item))
            .take(maximumEvents).toList();
      }
    } catch (error) {
      debugPrint('[IosRemoteCrashEvidence] Read: ${error.runtimeType}');
    }
    _initialized = true;
    await markForeground(true);
  }

  Future<void> markForeground(bool active) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setBool(_activeKey, active)) {
      debugPrint('[IosRemoteCrashEvidence] Session marker write failed');
    }
  }

  void installHandlers() {
    if (_installed) return;
    _installed = true;
    final previousFlutter = FlutterError.onError;
    FlutterError.onError = (details) {
      unawaited(record('flutter_framework',
          details.exception.runtimeType.toString()));
      previousFlutter?.call(details);
    };
    final previousPlatform = ui.PlatformDispatcher.instance.onError;
    ui.PlatformDispatcher.instance.onError = (error, stack) {
      unawaited(record('uncaught_platform',
          error.runtimeType.toString()));
      return previousPlatform?.call(error, stack) ?? false;
    };
  }

  Future<void> record(String category, String errorClass) {
    if (!const {'flutter_framework', 'uncaught_platform',
        'command_failure', 'native_bridge'}.contains(category)) {
      return Future<void>.value();
    }
    final safeClass = RegExp(r'^[A-Za-z0-9_]{1,90}$')
            .hasMatch(errorClass)
        ? errorClass : 'UnknownError';
    final job = _tail.then((_) async {
      try {
        await initialize();
        final event = <String, Object?>{
          'timeUtc': DateTime.now().toUtc().toIso8601String(),
          'category': category,
          'errorClass': safeClass,
          'buildRun': IosAudioTelemetry.buildRun,
          'buildCommit': IosAudioTelemetry.buildCommit,
        };
        _events = <Map<String, Object?>>[
          event, ..._events.take(maximumEvents - 1),
        ];
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_eventsKey, jsonEncode(_events));
      } catch (error) {
        debugPrint('[IosRemoteCrashEvidence] Store: ${error.runtimeType}');
      }
    });
    _tail = job.catchError((Object error, StackTrace stack) {
      debugPrint('[IosRemoteCrashEvidence] Queue: ${error.runtimeType}');
    });
    return job;
  }

  Future<Map<String, Object?>> status() async {
    await initialize();
    await _tail;
    return <String, Object?>{
      'accepted': true,
      'previousSessionUnclosed': _previousSessionUnclosed,
      'unclosedDoesNotProveCrash': true,
      'recentEventCount': _events.length,
      'events': _events.take(maximumEvents).toList(),
    };
  }
}
