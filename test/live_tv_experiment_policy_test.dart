import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:playtorrio/services/player/live_tv/live_tv_experiment_policy.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LiveTvExperimentStore store;
  late DateTime now;
  late Map<String, dynamic> sample;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = LiveTvExperimentStore.instance;
    await store.rollback();
    now = DateTime.now().toUtc();
    sample = <String, dynamic>{
      'schema': 1,
      'id': 'trial_nfl_001',
      'channelId': 'nltv:us:NFLChannel.us',
      'expiresAtUtc': now.add(const Duration(hours: 2)).toIso8601String(),
      'relayMode': 'prefer',
      'failoverEnabled': false,
      'relayAfterAttempts': 0,
      'startupGraceSeconds': 8,
      'stallSeconds': 8,
      'feedSeconds': 5,
      'cacheSeconds': 20,
    };
  });

  test('Runtime policy is scoped to live TV and survives reload', () async {
    final result = await store.apply(sample);
    expect(result['accepted'], true);
    expect(store.forChannel('nltv:us:NFLChannel.us')?.relayMode, 'prefer');
    expect(store.forChannel('nltv:us:SYFY.us'), isNull);
    expect(store.forChannel('tt123456'), isNull);
    await store.initialize();
    expect(store.forChannel('nltv:us:NFLChannel.us')?.cacheSeconds, 20);
    expect((await store.rollback())['active'], false);
    expect(store.forChannel('nltv:us:NFLChannel.us'), isNull);
  });

  test('Rejects bad fields, expiry, ranges and non TV IDs', () async {
    final variants = <Map<String, dynamic>>[
      {...sample, 'execute': 'print("unsafe")'},
      {...sample, 'relayMode': 'eval'},
      {...sample, 'channelId': 'tt123'},
      {...sample, 'cacheSeconds': -1},
      {...sample, 'failoverEnabled': 'false'},
      {...sample, 'expiresAtUtc': now.add(const Duration(days: 2)).toIso8601String()},
      {...sample, 'expiresAtUtc': now.subtract(const Duration(minutes: 1)).toIso8601String()},
      {...sample, 'relayAfterAttempts': 999},
    ];
    for (final invalid in variants) {
      expect((await store.apply(invalid))['accepted'], false);
      expect(store.forChannel('nltv:us:NFLChannel.us'), isNull);
    }
  });

  test('Regression rollback requires prior verified video', () async {
    expect((await store.apply(sample))['accepted'], true);
    expect(await store.rollbackOnRegression(
        channelId: 'nltv:us:NFLChannel.us',
        hadConfirmedVideo: false, failedAttempts: 20), false);
    expect(store.status()['active'], true);
    expect(await store.rollbackOnRegression(
        channelId: 'nltv:us:SYFY.us',
        hadConfirmedVideo: true, failedAttempts: 10), false);
    expect(await store.rollbackOnRegression(
        channelId: 'nltv:us:NFLChannel.us',
        hadConfirmedVideo: true, failedAttempts: 3), true);
    expect(store.status()['lastRollback'], 'verified_playback_regression');
  });

  test('24 hour expiry is an absolute upper bound', () {
    expect(() => LiveTvExperimentPolicy.parse(
        {...sample, 'expiresAtUtc': now.add(
            const Duration(days: 3)).toIso8601String()}, now: now),
        throwsFormatException);
    final p = LiveTvExperimentPolicy.parse(sample, now: now);
    expect(p.appliesTo('nltv:us:NFLChannel.us', now), true);
    expect(p.appliesTo('nltv:us:NFLChannel.us',
        now.add(const Duration(days: 1))), false);
  });
}
