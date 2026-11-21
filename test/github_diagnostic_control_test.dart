import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:playtorrio/services/remote/github_diagnostic_control.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Resumable journal uploads use stable artifact paths', () async {
    SharedPreferences.setMockInitialValues({});
    final requests = <String>[];
    final controller = GithubDiagnosticControl.forTesting(
      tokenProvider: () async => 'TEST_TOKEN',
      client: MockClient((req) async {
        if (req.method == 'GET') return http.Response('{}', 404);
        if (req.method == 'PUT') {
          requests.add(req.url.path);
          return http.Response('{}', 201);
        }
        return http.Response('{}', 404);
      }),
    )..forceTestPlatform = true;
    addTearDown(controller.dispose);
    await controller.initialize();
    controller.enabled.value = true;
    await controller.publishJournalFile(
      'new_diagnostic_run',
      'chunk_current_00000000',
      {'dataBase64': 'YWJj', 'bytes': 3},
    );
    expect(requests, hasLength(1));
    expect(requests.single, contains('/artifacts/'));
    expect(requests.single, contains('chunk_current_00000000.json'));
    expect(
      () => controller.publishJournalFile('run',
          'chunk_current_00000000', {}),
      throwsA(isA<FormatException>()),
    );
  });


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

  test('Matrix upload retries transient GET transport loss', () async {
    SharedPreferences.setMockInitialValues({});
    var reads = 0;
    var writes = 0;
    final controller = GithubDiagnosticControl.forTesting(
      tokenProvider: () async => 'TEST_PRIVATE_TOKEN',
      client: MockClient((request) async {
        if (request.method == 'GET') {
          reads++;
          if (reads == 1) throw http.ClientException('connection dropped');
          return http.Response('{}', 404);
        }
        if (request.method == 'PUT') {
          writes++;
          return http.Response('{}', 201);
        }
        return http.Response('', 404);
      }),
    )..forceTestPlatform = true;
    addTearDown(controller.dispose);
    await controller.initialize();
    controller.enabled.value = true;
    await controller.publishMatrixFile(
        'matrix_retry_002', 'candidate_0_0', {'accepted': true});
    expect(reads, 2);
    expect(writes, 1);
  });

  test('Matrix upload retries ambiguous PUT failure with fresh GET',
      () async {
    SharedPreferences.setMockInitialValues({});
    var reads = 0;
    var writes = 0;
    final controller = GithubDiagnosticControl.forTesting(
      tokenProvider: () async => 'TEST_PRIVATE_TOKEN',
      client: MockClient((request) async {
        if (request.method == 'GET') {
          reads++;
          return http.Response('{}', 404);
        }
        if (request.method == 'PUT') {
          writes++;
          if (writes == 1) throw http.ClientException('connection reset');
          return http.Response('{}', 201);
        }
        return http.Response('', 404);
      }),
    )..forceTestPlatform = true;
    addTearDown(controller.dispose);
    await controller.initialize();
    controller.enabled.value = true;
    await controller.publishMatrixFile(
        'matrix_retry_003', 'candidate_0_0', {'accepted': true});
    expect(reads, 2);
    expect(writes, 2);
  });

  test('Authentication failures do not retry matrix uploads', () async {
    SharedPreferences.setMockInitialValues({});
    var reads = 0;
    final controller = GithubDiagnosticControl.forTesting(
      tokenProvider: () async => 'TEST_PRIVATE_TOKEN',
      client: MockClient((request) async {
        reads++;
        return http.Response('{}', 401);
      }),
    )..forceTestPlatform = true;
    addTearDown(controller.dispose);
    await controller.initialize();
    controller.enabled.value = true;
    await expectLater(
        controller.publishMatrixFile(
            'matrix_retry_004', 'candidate_0_0', {'accepted': true}),
        throwsA(isA<StateError>()));
    expect(reads, 1);
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


  test('Failed receipt delivery is retried without replaying the action',
      () async {
    SharedPreferences.setMockInitialValues({});
    var actions = 0;
    var receiptWrites = 0;
    late GithubDiagnosticControl controller;
    controller = GithubDiagnosticControl.forTesting(
      tokenProvider: () async => 'TEST_PRIVATE_TOKEN',
      client: MockClient((request) async {
        if (request.method == 'GET' &&
            request.url.path.contains('/commands/')) {
          return http.Response(jsonEncode({
            'sha': 'cmd-sha',
            'content': base64Encode(utf8.encode(jsonEncode({
              'id': 'retry_receipt_001',
              'deviceId': controller.deviceId,
              'action': 'state',
              'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
              'args': <String, dynamic>{},
            }))),
          }), 200);
        }
        if (request.method == 'GET') return http.Response('{}', 404);
        if (request.method == 'PUT' &&
            request.url.path.contains('/receipts/')) {
          receiptWrites++;
          if (receiptWrites == 1) {
            return http.Response('rejected receipt', 400);
          }
          return http.Response('{}', 201);
        }
        if (request.method == 'PUT') return http.Response('{}', 201);
        return http.Response('{}', 404);
      }),
    )..forceTestPlatform = true;
    addTearDown(controller.dispose);
    await controller.initialize();
    controller.enabled.value = true;
    controller.onCommand = (action, args) async {
      actions++;
      return <String, Object?>{'accepted': true, 'detail': 'completed'};
    };
    await controller.pollNow();
    final prefs = await SharedPreferences.getInstance();
    expect(actions, 1);
    expect(receiptWrites, 1);
    final pending = prefs.getString(
        GithubDiagnosticControl.preferencePendingReceipt);
    expect(pending, isNotNull);
    expect((jsonDecode(pending!) as Map)['state'], 'completed');

    await controller.pollNow();
    expect(actions, 1);
    expect(receiptWrites, 2);
    expect(prefs.getString(
        GithubDiagnosticControl.preferencePendingReceipt), isNull);
  });

  test('Interrupted execution is reported uncertain rather than replayed',
      () async {
    SharedPreferences.setMockInitialValues({});
    var actions = 0;
    final delivered = <Map<String, dynamic>>[];
    late GithubDiagnosticControl controller;
    controller = GithubDiagnosticControl.forTesting(
      tokenProvider: () async => 'TEST_PRIVATE_TOKEN',
      client: MockClient((request) async {
        if (request.method == 'GET' &&
            request.url.path.contains('/commands/')) {
          return http.Response(jsonEncode({
            'sha': 'cmd-sha',
            'content': base64Encode(utf8.encode(jsonEncode({
              'id': 'interrupted_remote_001',
              'deviceId': controller.deviceId,
              'action': 'state',
              'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
              'args': <String, dynamic>{},
            }))),
          }), 200);
        }
        if (request.method == 'GET') return http.Response('{}', 404);
        if (request.method == 'PUT') {
          if (request.url.path.contains('/receipts/')) {
            final wrapper = jsonDecode(request.body) as Map;
            delivered.add(jsonDecode(utf8.decode(
                base64Decode(wrapper['content'] as String)))
                as Map<String, dynamic>);
          }
          return http.Response('{}', 201);
        }
        return http.Response('{}', 404);
      }),
    )..forceTestPlatform = true;
    addTearDown(controller.dispose);
    await controller.initialize();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        GithubDiagnosticControl.preferencePendingReceipt,
        jsonEncode(<String, Object?>{
          'schema': 2,
          'deviceId': controller.deviceId,
          'commandId': 'interrupted_remote_001',
          'action': 'state',
          'state': 'executing',
          'startedAtUtc': DateTime.now().toUtc().toIso8601String(),
        }));
    controller.enabled.value = true;
    controller.onCommand = (action, args) async {
      actions++;
      return <String, Object?>{'accepted': true};
    };
    await controller.pollNow();
    await controller.pollNow();
    expect(actions, 0);
    expect(delivered, hasLength(1));
    expect(delivered.single['state'], 'uncertain');
    expect((delivered.single['result'] as Map)['reason'],
        'execution_interrupted_outcome_unknown');
    expect(prefs.getString(
        GithubDiagnosticControl.preferencePendingReceipt), isNull);
  });

}
