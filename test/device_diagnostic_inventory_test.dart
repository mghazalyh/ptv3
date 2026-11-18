import 'package:flutter_test/flutter_test.dart';
import 'package:playtorrio/services/player/device_diagnostic_inventory.dart';

void main() {
  test('machine inventory is captured once and reused during its cache window',
      () async {
    var calls = 0;
    final inventory = DeviceDiagnosticInventory.forTesting(() async {
      calls++;
      return <String, Object?>{
        'schema': 1,
        'platform': 'windows',
        'installId': '0123456789abcdef0123456789abcdef',
        'windowsHardware': <String, Object?>{
          'processor': [{'Name': 'Example CPU'}],
        },
      };
    });
    final first = await inventory.capture();
    final second = await inventory.capture();
    expect(calls, 1);
    expect(second['installId'], '0123456789abcdef0123456789abcdef');
    expect(first['windowsHardware'], isA<Map>());
    inventory.invalidateCache();
    await inventory.capture();
    expect(calls, 2);
  });

  test('machine inspection failures produce structured error metadata',
      () async {
    final inventory = DeviceDiagnosticInventory.forTesting(() async {
      throw const FormatException('No inventory provider');
    });
    final result = await inventory.capture();
    expect(result['collectionError'], 'FormatException');
  });

  test('a repeated snapshot cannot overwrite cached top-level fields',
      () async {
    final inventory = DeviceDiagnosticInventory.forTesting(() async =>
        <String, Object?>{'schema': 1, 'platform': 'ios'});
    final result = await inventory.capture();
    result['platform'] = 'tampered';
    expect((await inventory.capture())['platform'], 'ios');
  });
}
