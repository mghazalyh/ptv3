import 'package:flutter_test/flutter_test.dart';
import 'package:playtorrio/services/remote/ios_remote_command_contract.dart';
import 'package:playtorrio/services/remote/ios_remote_diagnostic_inventory.dart';

void main() {
  test('Machine readable operations distinguish observation from control', () {
    final registry = IosRemoteCommandContract.manifest();
    final operations = registry['operations'] as Map;
    expect(registry['schema'], 1);
    expect(operations['media_discover']['readOnly'], true);
    expect(operations['media_play_resolved']['changesPlayback'], true);
    expect(operations['live_health_rank']['readOnly'], true);
    expect(operations['live_scan']['requiresIdleDevice'], true);
    expect(operations['app_screenshot']['readOnly'], true);
    expect(operations['settings_update']['changesSettings'], true);
    expect(IosRemoteDiagnosticInventory.capabilities()['remoteOperations'],
        registry);
  });
}
