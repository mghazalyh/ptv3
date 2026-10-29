import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:playtorrio/services/player/night_mode_diagnostics.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Captures MPV audio filter diagnostics, not unrelated media entries', () {
    expect(NightModeDiagnostics.shouldCaptureMpv(
        'af', 'Audio filter initialized failed!'), isTrue);
    expect(NightModeDiagnostics.shouldCaptureMpv(
        'ffmpeg', 'Error initializing acompressor using avfilter'), isTrue);
    expect(NightModeDiagnostics.shouldCaptureMpv(
        'cplayer', 'Playback error: Audio filter initialized failed!'), isTrue);
    expect(NightModeDiagnostics.shouldCaptureMpv(
        'demux', 'Opening media'), isFalse);
    expect(NightModeDiagnostics.shouldCaptureMpv(
        'cplayer', 'Subtitles loaded'), isFalse);
  });

  test('Redacts paths, metadata, links and credentials', () {
    final input = 'filter failed at https://sample.invalid/private-movie '
        'file=C:\\Users\\Sample\\Videos\\sample.mkv '
        'token=PLACEHOLDER '
        'path=/home/sample/example.mkv '
        'Audio filter initialized failed!';
    final result = NightModeDiagnostics.sanitize(input);
    expect(result, contains('Audio filter initialized failed'));
    for (final forbidden in [
      'sample.invalid', 'sample.mkv', 'PLACEHOLDER',
      'Sample', '/home/sample',
    ]) {
      expect(result, isNot(contains(forbidden)));
    }
    expect(result, contains('[REDACTED_'));
  });

  test('Logger writes and flushes native audio diagnostic context', () async {
    final dir = await Directory.systemTemp.createTemp('ptv-night-logs');
    addTearDown(() async => dir.delete(recursive: true));
    final logger = NightModeDiagnostics(directory: dir, enabled: true);
    await logger.start();
    await logger.record('night-toggle', 'requested=ON filter=acompressor');
    await logger.recordMpv(
      prefix: 'af',
      level: 'error',
      message: 'Audio filter initialized failed!',
    );
    await logger.recordMpv(
      prefix: 'video',
      level: 'info',
      message: 'irrelevant video',
    );
    await logger.flush();
    final file = File(logger.filePath);
    expect(await file.exists(), isTrue);
    final text = await file.readAsString();
    expect(text, contains('requested=ON'));
    expect(text, contains('Audio filter initialized failed!'));
    expect(text, contains('mpv/af/error'));
    expect(text, isNot(contains('irrelevant video')));
  });

  test('Logger keeps one previous file when size cap is exceeded', () async {
    final dir = await Directory.systemTemp.createTemp('ptv-night-rotation');
    addTearDown(() async => dir.delete(recursive: true));
    final logger = NightModeDiagnostics(directory: dir, enabled: true);
    await logger.start();
    await File(logger.filePath).writeAsString(
      'A' * (NightModeDiagnostics.maxBytes + 1),
    );
    await logger.record('night-toggle', 'request=ON');
    await logger.flush();
    expect(await File(logger.previousFilePath).exists(), isTrue);
    expect(await File(logger.filePath).readAsString(), contains('request=ON'));
    expect(await File(logger.filePath).length(),
        lessThan(NightModeDiagnostics.maxBytes));
    await File(logger.filePath).writeAsString(
      'B' * (NightModeDiagnostics.maxBytes + 1),
    );
    await logger.record('night-toggle', 'request=OFF');
    await logger.flush();
    final previous = await File(logger.previousFilePath).readAsString();
    expect(previous, startsWith('B'));
    expect(previous, isNot(contains('A' * 50)));
  });

  test('Disabled logger does not create a file', () async {
    final dir = await Directory.systemTemp.createTemp('ptv-night-disabled');
    addTearDown(() async => dir.delete(recursive: true));
    final logger = NightModeDiagnostics(directory: dir, enabled: false);
    await logger.start();
    await logger.record('night-toggle', 'ON');
    await logger.flush();
    expect(File(logger.filePath).existsSync(), false);
  });
}
