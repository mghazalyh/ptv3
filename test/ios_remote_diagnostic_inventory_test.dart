import 'package:flutter_test/flutter_test.dart';
import 'package:playtorrio/models/addon/addon.dart';
import 'package:playtorrio/services/remote/ios_remote_diagnostic_inventory.dart';

void main() {
  InstalledAddon example({bool enabled = true}) => InstalledAddon(
    baseUrl: 'https://user:secret@addon.example/configured-token',
    manifest: AddonManifest.fromJson({
      'id': 'test.tv', 'name': 'Example TV', 'version': '1.0.0',
      'resources': ['catalog', 'stream', 'subtitles'],
      'types': ['movie', 'series', 'tv'],
      'catalogs': [{'id': 'home', 'type': 'tv'}],
    }),
    enabled: enabled,
  );

  test('Command inventory separates read-only and playback controls', () {
    final info = IosRemoteDiagnosticInventory.capabilities();
    expect(info['schema'], 2);
    expect(info['readOnly'], contains('test_status'));
    expect(info['boundedTests'], contains('probe_native_channel'));
    expect(info['playbackChanging'], contains('open_channel'));
  });

  test('Addon inventory never exposes authentication or private paths', () {
    final result = IosRemoteDiagnosticInventory.addons([
      example(), example(enabled: false),
    ]);
    final items = result['addons'] as List;
    expect(items, hasLength(2));
    expect((items.first as Map)['host'], 'addon.example');
    expect((items.first as Map)['streamActive'], true);
    expect((items.last as Map)['streamActive'], false);
    expect(result.toString(), isNot(contains('configured-token')));
    expect(result.toString(), isNot(contains('secret')));
    expect(result.toString(), isNot(contains('https://')));
  });

  test('Untrusted provider manifest data cannot leak private values', () {
    final addon = InstalledAddon(
      baseUrl: 'https://user:password@tv.example/private/path?token=hidden',
      manifest: AddonManifest.fromJson({
        'id': 'https://evil.example/private?id=identifierSecret',
        'name': 'Provider token=manifestSecret',
        'version': '1.0.0',
        'types': ['movie', 'series', 'https://evil.example/secret', 'tv'],
        'resources': [
          'stream',
          {'name': 'catalog?token=resourceSecret', 'idPrefixes': ['privateSecret']},
          'meta',
        ],
      }),
    );
    final item = (IosRemoteDiagnosticInventory.addons([addon])['addons']
        as List).single as Map;
    expect(item['host'], 'tv.example');
    expect(item['name'], '[redacted]');
    expect(item['id'], '[redacted]');
    expect(item['types'], ['movie', 'series', 'tv']);
    expect(item['resources'], ['stream', 'meta']);
    final exported = item.toString();
    for (final sensitive in [
      'identifierSecret', 'manifestSecret', 'resourceSecret',
      'privateSecret', 'password', 'hidden', 'evil.example',
    ]) {
      expect(exported, isNot(contains(sensitive)));
    }
  });

  test('Snapshot excludes media URLs and titles', () {
    final result = IosRemoteDiagnosticInventory.device(
      buildRun: '300', buildCommit: 'abc',
      foreground: true, diagnosticsEnabled: true, navigatorReady: true,
      playerActive: true, playerPlaying: true,
      matrix: {
        'channelsDone': 2, 'totalChannels': 50,
        'privateUrl': 'https://secret.example/stream',
      },
    );
    expect(result['playerPlaying'], true);
    expect(result.toString(), isNot(contains('secret.example')));
    expect((result['matrix'] as Map)['channelsDone'], 2);
  });

  test('Limits exported addon records', () {
    final result = IosRemoteDiagnosticInventory.addons(
      List.generate(40, (_) => example()),
    );
    expect(result['truncated'], true);
    expect((result['addons'] as List).length, 32);
  });
}
