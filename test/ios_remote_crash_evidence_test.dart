import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:playtorrio/services/remote/ios_remote_crash_evidence.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Previous unfinished foreground session is evidence, not proof',
      () async {
    SharedPreferences.setMockInitialValues({
      'ios_remote_last_foreground_session_active_v1': true,
    });
    final recorder = IosRemoteCrashEvidence();
    await recorder.initialize();
    final status = await recorder.status();
    expect(status['previousSessionUnclosed'], true);
    expect(status['unclosedDoesNotProveCrash'], true);
  });

  test('Exception evidence never persists messages or arbitrary secrets',
      () async {
    SharedPreferences.setMockInitialValues({});
    final recorder = IosRemoteCrashEvidence();
    await recorder.initialize();
    await recorder.record('command_failure', 'SomeSensitiveException(');
    final result = await recorder.status();
    final events = result['events'] as List;
    expect(events, hasLength(1));
    expect((events.single as Map)['errorClass'], 'UnknownError');
    expect(jsonEncode(result), isNot(contains('SomeSensitiveException')));
  });
}
