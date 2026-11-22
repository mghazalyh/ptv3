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

  test('Sports surf stop keeps the current channel and skips future switches', () async {
    final agent = IosAdhocDiagnosticCoordinator();
    final firstOpened = Completer<void>();
    final opened = <String>[];

    final response = await agent.start({
      'runId': 'sports_surf_local_stop_20261122',
      'allowPlaybackChanges': true,
      'steps': [
        {'action': 'open_channel',
          'args': {'channelId': 'nltv:us:FirstSports.us'}},
        {'action': 'open_channel', 'waitMs': 15000,
          'args': {'channelId': 'nltv:us:SecondSports.us'}},
      ],
    }, matrixRunning: () => false, dispatch: (action, args) async {
      final id = args['channelId'];
      if (id is String) opened.add(id);
      if (!firstOpened.isCompleted) firstOpened.complete();
      return {'accepted': true};
    });

    expect(response['phase'], 'running');
    expect(agent.sportsSurfing.value, isTrue);
    await firstOpened.future;
    expect(agent.stopSportsSurfing(), isTrue);
    expect(agent.sportsSurfing.value, isFalse);
    await agent.whenComplete;
    expect(agent.status()['phase'], 'cancelled');
    expect(opened, ['nltv:us:FirstSports.us']);
    expect(agent.stopSportsSurfing(), isFalse);
  });

  test('Sports stop does not cancel an unrelated diagnostic plan', () async {
    final agent = IosAdhocDiagnosticCoordinator();
    final pending = Completer<Map<String, Object?>>();
    final response = await agent.start({
      'runId': 'plan_not_sports_20261122',
      'steps': [{'action': 'state'}],
    }, matrixRunning: () => false,
      dispatch: (_, __) => pending.future);
    expect(response['phase'], 'running');
    expect(agent.sportsSurfing.value, isFalse);
    expect(agent.stopSportsSurfing(), isFalse);
    expect(agent.status()['phase'], 'running');
    pending.complete({'accepted': true});
    await agent.whenComplete;
    expect(agent.status()['phase'], 'completed');
  });
}
