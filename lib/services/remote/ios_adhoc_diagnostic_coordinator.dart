import 'dart:async';

import 'package:flutter/foundation.dart';

import 'ios_adhoc_diagnostic_plan.dart';

/// Non-blocking, cancellable coordinator around the declarative plan engine.
/// A Torriodb command acknowledges the START immediately. Later commands can
/// read status or request cancellation even during lengthy native experiments.
class IosAdhocDiagnosticCoordinator {
  IosAdhocDiagnosticCoordinator();

  static final IosAdhocDiagnosticCoordinator instance =
      IosAdhocDiagnosticCoordinator();

  Future<void>? _job;
  String? _runId;
  String _phase = 'idle';
  bool _cancelled = false;
  int _finishedSteps = 0;
  int _executed = 0;
  int _failed = 0;
  int _skipped = 0;
  int _plannedExecutions = 0;
  Map<String, Object?>? _lastStep;
  String? _reason;
  DateTime? _startedAt;
  DateTime? _finishedAt;

  bool get isRunning => _phase == 'running' || _phase == 'cancelling';

  @visibleForTesting
  Future<void> get whenComplete => _job ?? Future<void>.value();

  Map<String, Object?> status() => <String, Object?>{
    'accepted': true,
    'runId': _runId,
    'phase': _phase,
    'cancelRequested': _cancelled,
    'completedSteps': _finishedSteps,
    'executedCommands': _executed,
    'failedCommands': _failed,
    'skippedSteps': _skipped,
    'plannedExecutions': _plannedExecutions,
    'lastStep': _lastStep,
    'reason': _reason,
    'startedAtUtc': _startedAt?.toIso8601String(),
    'finishedAtUtc': _finishedAt?.toIso8601String(),
  };

  Map<String, Object?> cancel() {
    if (!isRunning) {
      return <String, Object?>{
        ...status(), 'accepted': false, 'reason': 'no_active_plan',
      };
    }
    _cancelled = true;
    _phase = 'cancelling';
    return status();
  }

  Future<Map<String, Object?>> start(
    Map<String, dynamic> request, {
    required IosAdhocCommand dispatch,
    required bool Function() matrixRunning,
    void Function(Map<String, Object?>)? onStep,
    void Function(Map<String, Object?>)? onFinished,
  }) async {
    if (isRunning) {
      return <String, Object?>{
        ...status(), 'accepted': false, 'reason': 'plan_already_running',
      };
    }
    final requested = request['runId'];
    final runId = requested ??
        'plan_${DateTime.now().toUtc().microsecondsSinceEpoch}';
    if (runId is! String ||
        !RegExp(r'^[A-Za-z0-9_-]{8,50}$').hasMatch(runId)) {
      return <String, Object?>{
        'accepted': false, 'reason': 'invalid_plan_run_id',
      };
    }
    final rawPlan = Map<String, dynamic>.from(request)..remove('runId');
    final checked = await IosAdhocDiagnosticPlan.run(
      <String, dynamic>{...rawPlan, 'dryRun': true},
      dispatch: dispatch, matrixRunning: matrixRunning,
    );
    if (checked['accepted'] != true) return checked;
    if (request['dryRun'] == true) {
      return <String, Object?>{
        ...checked, 'runId': runId,
      };
    }

    _runId = runId;
    _phase = 'running';
    _cancelled = false;
    _finishedSteps = 0;
    _executed = 0;
    _failed = 0;
    _skipped = 0;
    _plannedExecutions = checked['plannedExecutions'] as int? ?? 0;
    _lastStep = null;
    _reason = null;
    _startedAt = DateTime.now().toUtc();
    _finishedAt = null;

    _job = _execute(rawPlan, dispatch, matrixRunning, onStep, onFinished);
    return status();
  }

  Future<void> _execute(
    Map<String, dynamic> plan,
    IosAdhocCommand dispatch,
    bool Function() matrixRunning,
    void Function(Map<String, Object?>)? onStep,
    void Function(Map<String, Object?>)? onFinished,
  ) async {
    Map<String, Object?> result;
    try {
      result = await IosAdhocDiagnosticPlan.run(
        plan,
        dispatch: dispatch,
        matrixRunning: matrixRunning,
        isCancelled: () => _cancelled,
        onStep: (entry) {
          _lastStep = entry;
          _finishedSteps++;
          if (entry['skipped'] == true) {
            _skipped++;
          } else {
            _executed++;
            if (entry['passed'] != true) _failed++;
          }
          try { onStep?.call(entry); } catch (_) {}
        },
      );
    } catch (error) {
      result = <String, Object?>{
        'accepted': false,
        'reason': 'plan_executor_exception',
        'errorClass': error.runtimeType.toString(),
      };
    }

    if (_cancelled || result['reason'] == 'plan_cancelled') {
      _phase = 'cancelled';
    } else {
      _phase = result['accepted'] == true ? 'completed' : 'failed';
    }
    _reason = result['reason']?.toString();
    _finishedAt = DateTime.now().toUtc();
    try {
      onFinished?.call(status());
    } catch (_) {}
  }
}
