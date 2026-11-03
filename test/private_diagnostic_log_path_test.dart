import 'package:flutter_test/flutter_test.dart';
import 'package:playtorrio/services/player/private_diagnostic_log_path.dart';

void main() {
  test('groups iOS private reports in UTC year/month/day folders', () {
    final result = PrivateDiagnosticLogPath.forTimestamp(
      prefix: 'playtorrio/diagnostics/ios/night-mode',
      timestamp: DateTime.utc(2026, 11, 3, 18, 5, 38, 576516),
      sequence: 59,
    );
    expect(result,
        'playtorrio/diagnostics/ios/night-mode/2026/11/03/'
        '2026-11-03T18-05-38-576516Z-59.json');
  });

  test('preserves UTC day even when Singapore is already next day', () {
    final singapore = DateTime.parse('2026-11-04T02:05:38+08:00');
    final result = PrivateDiagnosticLogPath.forTimestamp(
      prefix: 'playtorrio/diagnostics/windows/player',
      timestamp: singapore,
      sequence: 2,
    );
    expect(result, contains('/2026/11/03/'));
    expect(result, endsWith('-2.json'));
  });

  test('rejects invalid diagnostic path and sequence', () {
    expect(
      () => PrivateDiagnosticLogPath.forTimestamp(
        prefix: '', timestamp: DateTime.utc(2026), sequence: 1),
      throwsArgumentError,
    );
    expect(
      () => PrivateDiagnosticLogPath.forTimestamp(
        prefix: 'private', timestamp: DateTime.utc(2026), sequence: 0),
      throwsArgumentError,
    );
  });
}
