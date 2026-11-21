import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:playtorrio/services/remote/github_diagnostic_control.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Private device-scoped commands reject stale and mistargeted payloads', () {
    final now = DateTime.utc(2026, 11, 21, 2, 0);
    final command = <String, dynamic>{
      'id': 'test_cmd_001',
      'deviceId': 'abcd1234',
      'action': 'state',
      'args': <String, dynamic>{},
      'createdAtUtc': now.toIso8601String(),
    };
    expect(GithubDiagnosticControl.validCommand(
        command, deviceId: 'abcd1234', now: now), isTrue);
    expect(GithubDiagnosticControl.validCommand(
        command, deviceId: 'other', now: now), isFalse);
    expect(GithubDiagnosticControl.validCommand(
        command, deviceId: 'abcd1234',
        now: now.add(const Duration(hours: 2))), isFalse);
    expect(GithubDiagnosticControl.validCommand(
        {...command, 'action': 'run; rm -rf /'},
        deviceId: 'abcd1234', now: now), isFalse);
    expect(GithubDiagnosticControl.validCommand(
        {...command, 'id': 'x'},
        deviceId: 'abcd1234', now: now), isFalse);
  });

  test('One authorized command runs exactly once with a private receipt',
      () async {
    SharedPreferences.setMockInitialValues({});
    var performed = 0;
    final uploaded = <Map<String, dynamic>>[];
    late GithubDiagnosticControl controller;
    controller = GithubDiagnosticControl.forTesting(
      tokenProvider: () async => 'TEST_PRIVATE_TOKEN',
      client: MockClient((request) async {
        final path = request.url.path;
        if (request.method == 'PUT') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final payload = jsonDecode(utf8.decode(
              base64Decode(body['content'] as String))) as Map<String, dynamic>;
          uploaded.add(payload);
          return http.Response('{}', 201);
        }
        if (request.method == 'GET' && path.contains('/receipts/')) {
          return http.Response('{}', 404);
        }
        if (request.method == 'GET' && path.contains('/commands/')) {
          final payload = <String, dynamic>{
            'id': 'test_remote_command_001',
            'deviceId': controller.deviceId,
            'action': 'state',
            'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
            'args': <String, dynamic>{},
          };
          return http.Response(jsonEncode({
            'sha': 'test-file-sha',
            'content': base64Encode(utf8.encode(jsonEncode(payload))),
          }), 200);
        }
        return http.Response('{}', 404);
      }),
    )..forceTestPlatform = true;
    addTearDown(controller.dispose);
    await controller.initialize();
    expect(controller.deviceId, matches(RegExp(r'^[a-f0-9]{32}$')));
    controller.enabled.value = true;
    controller.onCommand = (action, args) async {
      performed++;
      expect(action, 'state');
      return <String, Object?>{'accepted': true};
    };
    await controller.pollNow();
    await controller.pollNow();
    expect(performed, 1);
    expect(uploaded.last['state'], 'completed');
    expect(uploaded.last['commandId'], 'test_remote_command_001');
    expect(uploaded.last['result'], <String, dynamic>{'accepted': true});
    expect(jsonEncode(uploaded), isNot(contains('TEST_PRIVATE_TOKEN')));
  });
  test('Matrix uploads recover from GitHub 409 using a fresh SHA',
      () async {
    SharedPreferences.setMockInitialValues({});
    var puts = 0;
    var reads = 0;
    final sentShas = <String?>[];
    final controller = GithubDiagnosticControl.forTesting(
      tokenProvider: () async => 'TEST_PRIVATE_TOKEN',
      client: MockClient((request) async {
        if (request.method == 'GET') {
          reads++;
          return http.Response(jsonEncode({
            'sha': reads == 1 ? 'old-blob-sha' : 'new-blob-sha',
            'content': base64Encode(utf8.encode('{}')),
          }), 200);
        }
        if (request.method == 'PUT') {
          puts++;
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          sentShas.add(body['sha'] as String?);
          return http.Response('{}', puts == 1 ? 409 : 200);
        }
        return http.Response('', 404);
      }),
    )..forceTestPlatform = true;
    addTearDown(controller.dispose);
    await controller.initialize();
    controller.enabled.value = true;
    await controller.publishMatrixFile('matrix_retry_001', 'status',
        <String, Object?>{'phase': 'running'});
    expect(puts, 2);
    expect(reads, 2);
    expect(sentShas, <String?>['old-blob-sha', 'new-blob-sha']);
  });

  test('Concurrent matrix, receipt and heartbeat writes are serialized',
      () async {
    SharedPreferences.setMockInitialValues({});
    var inFlight = 0;
    var peakInFlight = 0;
    var writes = 0;
    final controller = GithubDiagnosticControl.forTesting(
      tokenProvider: () async => 'TEST_PRIVATE_TOKEN',
      client: MockClient((request) async {
        if (request.method == 'GET') return http.Response('{}', 404);
        if (request.method == 'PUT') {
          inFlight++;
          if (inFlight > peakInFlight) peakInFlight = inFlight;
          await Future<void>.delayed(const Duration(milliseconds: 15));
          writes++;
          inFlight--;
          return http.Response('{}', 201);
        }
        return http.Response('', 404);
      }),
    )..forceTestPlatform = true;
    addTearDown(controller.dispose);
    await controller.initialize();
    controller.enabled.value = true;
    await Future.wait([
      controller.publishMatrixFile(
          'matrix_queue_001', 'candidate_0_0', {'accepted': true}),
      controller.publishMatrixFile(
          'matrix_queue_001', 'candidate_0_1', {'accepted': false}),
      controller.publishMatrixFile(
          'matrix_queue_001', 'status', {'phase': 'running'}),
    ]);
    expect(writes, 3);
    expect(peakInFlight, 1);
  });

  test('A failed upload does not poison the later upload queue', () async {
    SharedPreferences.setMockInitialValues({});
    var puts = 0;
    final controller = GithubDiagnosticControl.forTesting(
      tokenProvider: () async => 'TEST_PRIVATE_TOKEN',
      client: MockClient((request) async {
        if (request.method == 'GET') return http.Response('{}', 404);
        if (request.method == 'PUT') {
          puts++;
          return http.Response('{}', puts == 1 ? 400 : 201);
        }
        return http.Response('', 404);
      }),
    )..forceTestPlatform = true;
    addTearDown(controller.dispose);
    await controller.initialize();
    controller.enabled.value = true;
    await expectLater(controller.publishMatrixFile(
        'matrix_queue_001', 'candidate_0_0', {'accepted': true}),
        throwsA(isA<StateError>()));
    await controller.publishMatrixFile(
        'matrix_queue_001', 'candidate_0_1', {'accepted': false});
    expect(puts, 2);
  });

}
