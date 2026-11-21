import 'dart:async';
import 'dart:convert';

typedef IosAdhocCommand = Future<Map<String, Object?>> Function(
    String action, Map<String, dynamic> args);

/// Execute an owner-supplied declarative diagnostic sequence using the
/// commands already implemented by this IPA. No new native code is loaded.
/// Plans are validated in full before execution, then checked again before
/// every state-changing step to avoid interfering with a running TV matrix.
abstract final class IosAdhocDiagnosticPlan {
  static const maxSteps = 80;
  static const maxExecutions = 300;

  static const _observationalActions = <String>{
    'diagnostic_capabilities',
    'diagnostic_snapshot',
    'test_status',
    'addon_inventory',
    'state',
    'live_matrix_status',
    'live_experiment_status',
    'discover_live_matrix',
    'probe_addon',
    'test_indicator',
    'diagnostic_journal_status',
    'diagnostic_journal_tail',
    'device_inventory',
    'diagnostic_process_metrics',
    'diagnostic_http_probe',
    'diagnostic_plan_status',
    'diagnostic_plan_cancel',
    'diagnostic_media_sources',
  };

  static const _controllingActions = <String>{
    'capture_telemetry',
    'diagnostic_export',
    'diagnostic_open_media',
    'diagnostic_open_reference',
    'apply_live_experiment',
    'rollback_live_experiment',
    'open_channel',
    'remote',
    'player',
    'probe_native_channel',
    'start_live_matrix',
    'start_live_matrix_catalog',
    'cancel_live_matrix',
  };

  static bool isReadOnly(String action, Map<String, dynamic> args) {
    if (_observationalActions.contains(action)) return true;
    if (action == 'player') {
      return args['command'] == 'state' ||
          args['command'] == 'probe_live';
    }
    return false;
  }

  static bool isSupported(String action) =>
      _observationalActions.contains(action) ||
      _controllingActions.contains(action);

  static Object? _lookup(Map<String, Object?> result, String key) {
    Object? node = result;
    for (final part in key.split('.')) {
      if (node is! Map || !node.containsKey(part)) return null;
      node = node[part];
    }
    return node;
  }

  static Map<String, Object?> _boundedResult(Map<String, Object?> result) {
    // A receipt must remain small even for large catalog discoveries.
    if (jsonEncode(result).length <= 1200) return result;
    return <String, Object?>{
      'accepted': result['accepted'],
      'reason': result['reason'],
      'truncated': true,
      'keys': result.keys.take(20).toList(growable: false),
    };
  }

  static Future<Map<String, Object?>> run(
    Map<String, dynamic> request, {
    required IosAdhocCommand dispatch,
    required bool Function() matrixRunning,
    bool Function()? isCancelled,
    void Function(Map<String, Object?>)? onStep,
  }) async {
    try {
      if (request.keys.any((key) => !const <String>{
            'steps', 'dryRun', 'allowPlaybackChanges', 'stopOnFailure',
          }.contains(key))) {
        return {'accepted': false, 'reason': 'unknown_plan_option'};
      }
      final rawSteps = request['steps'];
      final dryRun = request['dryRun'] ?? false;
      final allowPlayback = request['allowPlaybackChanges'] ?? false;
      final stopOnFailure = request['stopOnFailure'] ?? true;
      if (rawSteps is! List || rawSteps.isEmpty ||
          rawSteps.length > maxSteps ||
          dryRun is! bool || allowPlayback is! bool ||
          stopOnFailure is! bool) {
        return {'accepted': false, 'reason': 'invalid_plan'};
      }

      final steps = <({String action, Map<String, dynamic> args,
          Map<String, Object?> expected, Map<String, Object?> when,
          int waitMs, int repeat, bool readOnly})>[];
      var plannedExecutions = 0;
      for (final raw in rawSteps) {
        if (raw is! Map ||
            raw.keys.any((key) => !const <String>{
              'action', 'args', 'expect', 'when', 'waitMs', 'repeat',
            }.contains(key))) {
          return {'accepted': false, 'reason': 'invalid_plan_step'};
        }
        final action = raw['action'];
        final rawArgs = raw['args'];
        final rawExpect = raw['expect'];
        final repeat = raw['repeat'] ?? 1;
        final rawWhen = raw['when'];
        final rawWaitMs = raw['waitMs'] ?? 0;
        if (action is! String || !isSupported(action) ||
            rawArgs != null && rawArgs is! Map ||
            rawExpect != null && rawExpect is! Map ||
            rawWhen != null && rawWhen is! Map ||
            rawWaitMs is! int || rawWaitMs < 0 || rawWaitMs > 60000 ||
            repeat is! int || repeat < 1 || repeat > 25) {
          return {'accepted': false, 'reason': 'unsupported_plan_step'};
        }
        final args = rawArgs == null
            ? <String, dynamic>{}
            : Map<String, dynamic>.from(rawArgs as Map);
        final readOnly = isReadOnly(action, args);
        if (!readOnly && !allowPlayback && !dryRun) {
          return {'accepted': false, 'reason': 'playback_permission_required'};
        }
        if (action == 'test_indicator' &&
            (args.length != 1 || args['visible'] is! bool)) {
          return {'accepted': false, 'reason': 'invalid_indicator_setting'};
        }
        if (action == 'player' && args['command'] is! String) {
          return {'accepted': false, 'reason': 'missing_player_action'};
        }
        final expected = rawExpect == null
            ? <String, Object?>{}
            : Map<String, Object?>.from(rawExpect as Map);
        if (expected.length > 12 ||
            expected.entries.any((entry) =>
                !RegExp(r'^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z][a-zA-Z0-9_]*){0,3}$')
                    .hasMatch(entry.key) ||
                entry.value is Map || entry.value is List)) {
          return {'accepted': false, 'reason': 'invalid_assertion'};
        }
        final when = rawWhen == null
            ? <String, Object?>{}
            : Map<String, Object?>.from(rawWhen as Map);
        if (when.length > 8 ||
            when.entries.any((entry) =>
                !RegExp(r'^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z][a-zA-Z0-9_]*){0,3}$')
                    .hasMatch(entry.key) ||
                entry.value is Map || entry.value is List)) {
          return {'accepted': false, 'reason': 'invalid_condition'};
        }
        plannedExecutions += repeat;
        if (plannedExecutions > maxExecutions) {
          return {'accepted': false, 'reason': 'too_many_executions'};
        }
        steps.add((action: action, args: args,
            expected: expected, when: when, waitMs: rawWaitMs,
            repeat: repeat, readOnly: readOnly));
      }

      if (dryRun) {
        return <String, Object?>{
          'accepted': true,
          'dryRun': true,
          'stepCount': steps.length,
          'plannedExecutions': plannedExecutions,
          'requiresPlaybackPermission':
              steps.any((step) => !step.readOnly),
          'wouldInterruptMatrix': matrixRunning() &&
              steps.any((step) => !step.readOnly),
          'actions': steps.map((step) => step.action).toList(),
        };
      }

      if (matrixRunning() && steps.any((step) => !step.readOnly)) {
        return {'accepted': false, 'reason': 'matrix_in_progress'};
      }

      final results = <Map<String, Object?>>[];
      var failed = 0;
      Map<String, Object?>? previousResponse;
      bool cancelled() => isCancelled?.call() == true;
      Map<String, Object?> cancellation() => <String, Object?>{
        'accepted': false,
        'reason': 'plan_cancelled',
        'executed': results.where((result) =>
            result['skipped'] != true).length,
        'failed': failed,
        'results': results,
      };
      for (var i = 0; i < steps.length; i++) {
        final step = steps[i];
        if (cancelled()) return cancellation();
        if (step.when.isNotEmpty &&
            (previousResponse == null || step.when.entries.any((entry) =>
                _lookup(previousResponse!, entry.key) != entry.value))) {
          final skipped = <String, Object?>{
            'index': i, 'action': step.action,
            'skipped': true, 'reason': 'condition_not_met',
          };
          results.add(skipped);
          try { onStep?.call(skipped); } catch (_) {}
          continue;
        }
        for (var iteration = 0; iteration < step.repeat; iteration++) {
          if (cancelled()) return cancellation();
          var remaining = step.waitMs;
          while (remaining > 0) {
            if (cancelled()) return cancellation();
            final slice = remaining < 250 ? remaining : 250;
            await Future<void>.delayed(Duration(milliseconds: slice));
            remaining -= slice;
          }
          if (cancelled()) return cancellation();
          if (!step.readOnly && matrixRunning()) {
            return <String, Object?>{
              'accepted': false,
              'reason': 'matrix_became_busy',
              'executed': results.length,
              'results': results,
            };
          }
          Map<String, Object?> response;
          try {
            response = await dispatch(step.action, step.args);
          } catch (error) {
            response = <String, Object?>{
              'accepted': false,
              'reason': 'command_exception',
              'errorClass': error.runtimeType.toString(),
            };
          }
          previousResponse = response;
          final unmet = <String>[];
          for (final e in step.expected.entries) {
            if (_lookup(response, e.key) != e.value) {
              unmet.add(e.key);
            }
          }
          final passed = response['accepted'] != false && unmet.isEmpty;
          if (!passed) failed++;
          final observation = <String, Object?>{
            'index': i,
            'repeat': iteration,
            'action': step.action,
            'passed': passed,
            if (unmet.isNotEmpty) 'unmetAssertions': unmet,
            'result': _boundedResult(response),
          };
          results.add(observation);
          try { onStep?.call(observation); } catch (_) {} 
          if (!passed && stopOnFailure) {
            return <String, Object?>{
              'accepted': false,
              'reason': 'plan_step_failed',
              'executed': results.length,
              'failed': failed,
              'results': results,
            };
          }
        }
      }
      return <String, Object?>{
        'accepted': failed == 0,
        'executed': results.length,
        'failed': failed,
        'results': results,
      };
    } catch (error) {
      return <String, Object?>{
        'accepted': false,
        'reason': 'invalid_plan',
        'errorClass': error.runtimeType.toString(),
      };
    }
  }
}
