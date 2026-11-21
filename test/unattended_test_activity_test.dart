import 'package:flutter_test/flutter_test.dart';
import 'package:playtorrio/services/remote/unattended_test_activity.dart';

void main() {
  test('Only active on-device matrix shows a test indicator', () {
    final active = UnattendedTestSnapshot.fromMatrix({
      'phase': 'running', 'runId': 'matrix_live',
      'channelsDone': 20, 'totalChannels': 150,
      'sourcesDone': 48, 'verifiedSources': 14,
      'uploadFailures': 6,
    });
    expect(active.isVisible, true);
    expect(active.progress, closeTo(20 / 150, 0.00001));
    expect(active.toJson()['sustainedPlaybackSessions'], 14);
    for (final phase in ['idle','completed','failed','cancelled']) {
      expect(UnattendedTestSnapshot.fromMatrix({
        'phase': phase, 'channelsDone': 150, 'totalChannels': 150,
      }).isVisible, false, reason: phase);
    }
  });

  test('A single native probe advertises progress and clears on completion', () {
    final activity = UnattendedTestActivity.instance;
    activity.beginNativeProbe('nltv:us:Test.us');
    expect(activity.snapshot.value.isVisible, true);
    expect(activity.snapshot.value.totalChannels, 0);
    activity.endNativeProbe();
    expect(activity.snapshot.value.isVisible, false);
  });

  test('Indicator can be hidden and shown while matrix continues', () {
    final activity = UnattendedTestActivity.instance;
    activity.updateMatrix({
      'phase': 'running', 'runId': 'matrix_toggle_1',
      'channelsDone': 2, 'totalChannels': 50,
    });
    expect(activity.snapshot.value.isVisible, isTrue);
    activity.setIndicatorEnabled(false);
    expect(activity.snapshot.value.isVisible, isFalse);
    expect(activity.snapshot.value.channelsDone, 2);
    activity.updateMatrix({
      'phase': 'running', 'runId': 'matrix_toggle_1',
      'channelsDone': 3, 'totalChannels': 50,
    });
    expect(activity.snapshot.value.isVisible, isFalse);
    expect(activity.snapshot.value.channelsDone, 3);
    activity.setIndicatorEnabled(true);
    expect(activity.snapshot.value.isVisible, isTrue);
    activity.updateMatrix({
      'phase': 'completed', 'runId': 'matrix_toggle_1',
      'channelsDone': 50, 'totalChannels': 50,
    });
    expect(activity.snapshot.value.isVisible, isFalse);
    activity.updateMatrix({
      'phase': 'running', 'runId': 'matrix_toggle_2',
      'channelsDone': 0, 'totalChannels': 50,
    });
    expect(activity.snapshot.value.isVisible, isTrue);
    activity.updateMatrix({'phase': 'idle'});
  });

  test('Malformed counts cannot produce false progress or crash', () {
    final parsed = UnattendedTestSnapshot.fromMatrix({
      'phase': 'running', 'channelsDone': -12,
      'totalChannels': '150', 'verifiedSources': -1,
      'uploadFailures': null,
    });
    expect(parsed.channelsDone, 0);
    expect(parsed.totalChannels, 0);
    expect(parsed.progress, isNull);
    expect(parsed.sustainedPlaybackSessions, 0);
    expect(parsed.uploadFailures, 0);
  });
}
