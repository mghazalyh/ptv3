import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:playtorrio/services/remote/ios_adhoc_diagnostic_coordinator.dart';

void main() {
  test('Long command starts immediately without blocking its inbox', () async {
    final agent = IosAdhocDiagnosticCoordinator();
    final pending = Completer<Map<String, Object?>>();
    final response = await agent.start({
      'runId': 'plan_nonblocking_01',
      'steps': [{'action': 'state'}],
    }, matrixRunning: () => false,
      dispatch: (action, args) => pending.future);
    expect(response['phase'], 'running');
    expect(agent.status()['phase'], 'running');
    pending.complete({'accepted': true, 'routeReady': true});
    await agent.whenComplete;
    expect(agent.status()['phase'], 'completed');
    expect(agent.status()['executedCommands'], 1);
  });

  test('Cancellation interrupts a waiting test between commands', () async {
    final agent = IosAdhocDiagnosticCoordinator();
    var requests = 0;
    final started = await agent.start({
      'steps': [
        {'action': 'state', 'waitMs': 1500, 'repeat': 3},
      ],
    }, matrixRunning: () => false,
      dispatch: (name, args) async {
        requests++;
        return {'accepted': true};
      });
    expect(started['phase'], 'running');
    expect(agent.cancel()['phase'], 'cancelling');
    await agent.whenComplete;
    expect(agent.status()['phase'], 'cancelled');
    expect(requests, 0);
  });

  test('Dry-run does not start device actions', () async {
    final agent = IosAdhocDiagnosticCoordinator();
    var called = false;
    final response = await agent.start({
      'dryRun': true,
      'steps': [{'action': 'diagnostic_http_probe'}],
    }, matrixRunning: () => false,
      dispatch: (name, args) async {
        called = true;
        return {'accepted': true};
      });
    expect(response['dryRun'], true);
    expect(response['plannedExecutions'], 1);
    expect(called, false);
    expect(agent.status()['phase'], 'idle');
  });

  test('Refuses a second active plan and records failed assertion', () async {
    final agent = IosAdhocDiagnosticCoordinator();
    final pending = Completer<Map<String, Object?>>();
    await agent.start({
      'steps': [{'action': 'state', 'expect': {'playing': true}}],
    }, matrixRunning: () => false,
      dispatch: (name, args) => pending.future);
    final rejected = await agent.start({
      'steps': [{'action': 'state'}],
    }, matrixRunning: () => false,
      dispatch: (name, args) async => {'accepted': true});
    expect(rejected['reason'], 'plan_already_running');
    pending.complete({'accepted': true, 'playing': false});
    await agent.whenComplete;
    expect(agent.status()['phase'], 'failed');
    expect(agent.status()['failedCommands'], 1);
  });
}
