import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:playtorrio/services/config/windows_settings_recovery.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory home;
  late File live;
  late File backup;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('ptv-settings-recovery-');
    live = File(p.join(home.path, 'com.example', 'playtorrio',
        'shared_preferences.json'));
    backup = File(p.join(home.path, 'PlayTorrio', 'settings-recovery',
        'shared_preferences.json'));
  });

  tearDown(() async {
    if (await home.exists()) await home.delete(recursive: true);
  });

  Future<void> store(File file, Map<String, Object> values) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(values), flush: true);
  }

  test('healthy existing profile is kept and a recovery copy is written',
      () async {
    await store(live, {'flutter.player_global_night_mode': true,
      'flutter.user_configured': 'keep-current'});
    final result = await WindowsSettingsRecovery.prepare(
        roamingRoot: home.path, forTesting: true);
    expect(result.recovered, isFalse);
    expect(result.state, 'existing-profile');
    expect(result.preferenceCount, 2);
    expect(jsonDecode(await backup.readAsString()),
        jsonDecode(await live.readAsString()));
  });

  test('missing current profile recovers old portable app identity',
      () async {
    await store(File(p.join(home.path, 'playtorrio',
        'shared_preferences.json')),
        {'flutter.player_global_extra_brightness': 55,
         'flutter.app_setting': 'old'});
    final result = await WindowsSettingsRecovery.prepare(
        roamingRoot: home.path, forTesting: true);
    expect(result.recovered, isTrue);
    expect(result.preferenceCount, 2);
    expect(jsonDecode(await live.readAsString()),
        containsPair('flutter.player_global_extra_brightness', 55));
    expect(await backup.exists(), isTrue);
  });

  test('never overwrites new user values with an older backup', () async {
    await store(live, {'flutter.pref': 'new'});
    await store(backup, {'flutter.pref': 'old', 'flutter.other': 'old'});
    final result = await WindowsSettingsRecovery.prepare(
        roamingRoot: home.path, forTesting: true);
    expect(result.recovered, isFalse);
    expect(jsonDecode(await live.readAsString()),
        containsPair('flutter.pref', 'new'));
    expect(jsonDecode(await backup.readAsString()),
        containsPair('flutter.pref', 'old'));
  });

  test('invalid and empty backups cannot erase the current profile', () async {
    await store(live, {'flutter.pref': 'keep'});
    await backup.parent.create(recursive: true);
    await backup.writeAsString('invalid json', flush: true);
    await WindowsSettingsRecovery.prepare(
        roamingRoot: home.path, forTesting: true);
    expect(jsonDecode(await live.readAsString()),
        containsPair('flutter.pref', 'keep'));
  });

  test('does not restore arbitrary JSON that is not Flutter preferences',
      () async {
    await store(backup, {'not-a-preference': 'do-not-import'});
    final result = await WindowsSettingsRecovery.prepare(
        roamingRoot: home.path, forTesting: true);
    expect(result.recovered, isFalse);
    expect(await live.exists(), isFalse);
  });
}
