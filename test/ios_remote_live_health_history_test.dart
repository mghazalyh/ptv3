import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:playtorrio/services/remote/ios_remote_live_health_history.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Native matrix evidence is ranked without exposing stream URLs',
      () async {
    SharedPreferences.setMockInitialValues({});
    final history = IosRemoteLiveHealthHistory();
    Future<void> record(String id, String title, bool verified) =>
        history.recordCandidate(<String, Object?>{
          'runId': 'matrix_native_123',
          'channelId': id, 'title': title,
          'sustainedPlayback': verified,
          'requestedSourceVerified': verified,
          'requestedSourceIndex': 1,
          'url': 'https://secret.example/stream?token=SENSITIVE',
        });
    await record('nltv:us:SportsOne.us', 'Sports One', true);
    await record('nltv:us:SportsOne.us', 'Sports One', true);
    await record('nltv:us:SportsTwo.us', 'Sports Two', false);
    final result = await history.rank({
      'query': 'sports', 'limit': 10, 'minVerified': 1,
    });
    expect(result['accepted'], true);
    final items = result['items'] as List;
    expect(items, hasLength(1));
    expect((items.first as Map)['verified'], 2);
    expect((items.first as Map)['lastVerifiedSourceIndex'], 1);
    expect(result['notRealTimeAvailability'], true);
    final prefs = await SharedPreferences.getInstance();
    final encoded = prefs.getString(
        IosRemoteLiveHealthHistory.preferenceKey)!;
    expect(jsonEncode(result), isNot(contains('SENSITIVE')));
    expect(encoded, isNot(contains('secret.example')));
  });

  test('Malformed candidate never creates verified evidence', () async {
    SharedPreferences.setMockInitialValues({});
    final history = IosRemoteLiveHealthHistory();
    await history.recordCandidate({
      'channelId': 'garbage', 'title': 'Bad',
      'sustainedPlayback': true,
    });
    final result = await history.rank({});
    expect(result['matches'], 0);
  });
}
