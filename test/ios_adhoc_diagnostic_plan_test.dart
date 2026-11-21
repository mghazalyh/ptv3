import 'package:flutter_test/flutter_test.dart';
import 'package:playtorrio/services/remote/ios_adhoc_diagnostic_plan.dart';

void main() {
  test('Conditional steps skip based on previous device response', () async {
    final called = <String>[];
    final result = await IosAdhocDiagnosticPlan.run({
      'steps': [
        {'action': 'live_matrix_status'},
        {'action': 'diagnostic_journal_status',
         'when': {'phase': 'completed'}},
      ],
    }, matrixRunning: () => false, dispatch: (a, b) async {
      called.add(a);
      return {'accepted': true, 'phase': 'running'};
    });
    expect(result['accepted'], true);
    expect(called, ['live_matrix_status']);
    expect((result['results'] as List).last['skipped'], true);
  });

  test('Conditional plans can execute when previous result matches',
      () async {
    final called = <String>[];
    final result = await IosAdhocDiagnosticPlan.run({
      'steps': [
        {'action': 'live_matrix_status'},
        {'action': 'diagnostic_journal_status',
         'when': {'phase': 'completed'}},
      ],
    }, matrixRunning: () => false, dispatch: (a, b) async {
      called.add(a);
      return {'accepted': true, 'phase': 'completed'};
    });
    expect(result['accepted'], true);
    expect(called, ['live_matrix_status', 'diagnostic_journal_status']);
  });

  test('Cancellation interrupts a delayed observation', () async {
    var cancelled = false;
    var calls = 0;
    final pending = IosAdhocDiagnosticPlan.run({
      'steps': [{'action': 'state', 'waitMs': 500}],
    }, matrixRunning: () => false,
       isCancelled: () => cancelled,
       dispatch: (a, b) async {
         calls++;
         return {'accepted': true};
       });
    cancelled = true;
    final result = await pending;
    expect(result['reason'], 'plan_cancelled');
    expect(calls, 0);
  });

  test('Dry-run validates actions without executing anything', () async {
    var called = 0;
    final result = await IosAdhocDiagnosticPlan.run({
      'dryRun': true,
      'steps': [
        {'action': 'live_matrix_status'},
        {'action': 'test_indicator', 'args': {'visible': false}},
      ],
    }, matrixRunning: () => true, dispatch: (a, b) async {
      called++;
      return {'accepted': true};
    });
    expect(result['accepted'], isTrue);
    expect(result['plannedExecutions'], 2);
    expect(result['wouldInterruptMatrix'], false);
    expect(called, 0);
  });

  test('Dry run can inspect an unapproved playback plan', () async {
    final result = await IosAdhocDiagnosticPlan.run({
      'dryRun': true,
      'steps': [{'action': 'open_channel'}],
    }, matrixRunning: () => true,
       dispatch: (a, b) async => {'accepted': true});
    expect(result['accepted'], true);
    expect(result['requiresPlaybackPermission'], true);
    expect(result['wouldInterruptMatrix'], true);
  });

  test('Read-only plans execute while matrix runs', () async {
    final actions = <String>[];
    final result = await IosAdhocDiagnosticPlan.run({
      'steps': [
        {'action': 'live_matrix_status',
         'expect': {'phase': 'running', 'channelsDone': 23}},
        {'action': 'test_indicator', 'args': {'visible': false}},
        {'action': 'player', 'args': {'command': 'state'}},
      ],
    }, matrixRunning: () => true, dispatch: (a, b) async {
      actions.add(a);
      return {
        'accepted': true,
        if (a == 'live_matrix_status') ...{
          'phase': 'running', 'channelsDone': 23,
        },
      };
    });
    expect(result['accepted'], isTrue);
    expect(result['executed'], 3);
    expect(actions, ['live_matrix_status', 'test_indicator', 'player']);
  });

  test('Refuses playback-changing commands during matrix', () async {
    var called = 0;
    final result = await IosAdhocDiagnosticPlan.run({
      'allowPlaybackChanges': true,
      'steps': [
        {'action': 'open_channel',
          'args': {'channelId': 'nltv:us:Test.us'}},
      ],
    }, matrixRunning: () => true, dispatch: (a, b) async {
      called++;
      return {'accepted': true};
    });
    expect(result['reason'], 'matrix_in_progress');
    expect(called, 0);
  });

  test('Playback commands need explicit permission', () async {
    final result = await IosAdhocDiagnosticPlan.run({
      'steps': [
        {'action': 'remote', 'args': {'command': 'play'}},
      ],
    }, matrixRunning: () => false,
      dispatch: (a, b) async => {'accepted': true});
    expect(result['reason'], 'playback_permission_required');
  });

  test('Control step rechecks matrix busy before dispatch', () async {
    var busy = false;
    var calls = 0;
    final result = await IosAdhocDiagnosticPlan.run({
      'allowPlaybackChanges': true,
      'steps': [
        {'action': 'state'},
        {'action': 'open_channel',
          'args': {'channelId': 'nltv:us:Test.us'}},
      ],
    }, matrixRunning: () => busy, dispatch: (a, b) async {
      calls++;
      busy = true;
      return {'accepted': true};
    });
    expect(result['reason'], 'matrix_became_busy');
    expect(calls, 1);
  });

  test('Assertions and repeats can stop a failing sequence', () async {
    var calls = 0;
    final result = await IosAdhocDiagnosticPlan.run({
      'steps': [
        {'action': 'diagnostic_snapshot', 'repeat': 3,
          'expect': {'matrix.channelsDone': 10}},
      ],
    }, matrixRunning: () => false, dispatch: (a, b) async {
      calls++;
      return {
        'accepted': true,
        'matrix': {'channelsDone': calls == 2 ? 9 : 10},
      };
    });
    expect(result['reason'], 'plan_step_failed');
    expect(result['executed'], 2);
    expect(calls, 2);
  });

  test('Rejects unsupported, nested and malformed plans', () async {
    Future<Map<String, Object?>> check(Map<String, dynamic> input) =>
        IosAdhocDiagnosticPlan.run(input,
          matrixRunning: () => false,
          dispatch: (a, b) async => {'accepted': true});
    expect((await check({'steps': [{'action': 'batch'}]}))['accepted'], false);
    expect((await check({'steps': [{'action': 'arbitrary_shell'}]}))['accepted'], false);
    expect((await check({'steps': [{'action': 'test_indicator',
      'args': {'visible': 'false'}}]}))['accepted'], false);
    expect((await check({'steps': [{'action': 'state', 'repeat': 999}]}))['accepted'], false);
    expect((await check({'steps': []}))['accepted'], false);
  });

  test('Non-stop mode records failures and continues', () async {
    var call = 0;
    final result = await IosAdhocDiagnosticPlan.run({
      'stopOnFailure': false,
      'steps': [
        {'action': 'state', 'repeat': 2, 'expect': {'ready': true}},
      ],
    }, matrixRunning: () => false, dispatch: (a, b) async {
      call++;
      return {'accepted': true, 'ready': call == 2};
    });
    expect(result['accepted'], false);
    expect(result['failed'], 1);
    expect(result['executed'], 2);
  });
}
