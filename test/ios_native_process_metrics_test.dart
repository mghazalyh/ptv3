import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:playtorrio/services/player/ios_native_process_metrics.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Native process metrics reports iOS-only availability', () async {
    final result = await IosNativeProcessMetrics.capture();
    if (Platform.isIOS) {
      expect(result['accepted'], isA<bool>());
    } else {
      expect(result['accepted'], false);
      expect(result['reason'], 'ios_only');
    }
  });
}
