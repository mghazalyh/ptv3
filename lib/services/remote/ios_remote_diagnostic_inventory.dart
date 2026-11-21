import '../../models/addon/addon.dart';

/// Read-only responses for the opt-in iOS Torriodb diagnostics transport.
/// Never expose addon configuration URLs, credentials, headers or streams.
abstract final class IosRemoteDiagnosticInventory {
  static const commandSchema = 2;
  static const maximumReportedAddons = 32;

  // Manifest fields are untrusted provider data. Send only safe inventory
  // labels and recognized protocol resource names to the remote diagnostics.
  static final RegExp _privateText = RegExp(
    r'(https?://|stremio://|magnet:|[/?#@&=%]|bearer|token|secret|password|credential)',
    caseSensitive: false,
  );
  static final RegExp _safeType = RegExp(r'^[a-z][a-z0-9_-]{0,23}$');
  static const _knownResources = <String>{
    'catalog', 'meta', 'stream', 'subtitles', 'addon_catalog',
  };

  static String _safeLabel(String value, int limit) {
    final clean = value.trim();
    if (clean.isEmpty || _privateText.hasMatch(clean) ||
        clean.runes.any((code) => code < 32 || code == 127)) {
      return '[redacted]';
    }
    return clean.length <= limit ? clean : clean.substring(0, limit);
  }

  static List<String> _safeTypes(List<String> types) => types
      .where((type) => _safeType.hasMatch(type) &&
          !_privateText.hasMatch(type))
      .take(10)
      .toList(growable: false);

  static List<String> _safeResources(List<String> resources) => resources
      .where(_knownResources.contains)
      .take(10)
      .toList(growable: false);

  static Map<String, Object?> capabilities() => <String, Object?>{
    'accepted': true,
    'schema': commandSchema,
    'transport': 'torriodb_device_scoped',
    'pollSeconds': 12,
    'readOnly': const [
      'diagnostic_capabilities', 'diagnostic_snapshot',
      'test_status', 'addon_inventory', 'state',
      'live_matrix_status', 'live_experiment_status',
      'discover_live_matrix', 'probe_addon',
    ],
    'boundedTests': const [
      'probe_native_channel', 'start_live_matrix_catalog',
      'start_live_matrix', 'cancel_live_matrix',
    ],
    'playbackChanging': const ['open_channel', 'remote', 'player'],
    'indicator': 'automatic_from_device_matrix_and_native_probe',
  };

  static Map<String, Object?> addons(Iterable<InstalledAddon> addons) {
    final all = addons.toList(growable: false);
    return <String, Object?>{
      'accepted': true,
      'installedCount': all.length,
      'truncated': all.length > maximumReportedAddons,
      'addons': all.take(maximumReportedAddons).map((addon) {
        final host = Uri.tryParse(addon.baseUrl)?.host ?? '';
        return <String, Object?>{
          'name': _safeLabel(addon.manifest.name, 80),
          'id': _safeLabel(addon.manifest.id, 100),
          'host': host,
          'enabled': addon.enabled,
          'streamActive': addon.isStreamsActive,
          'catalogActive': addon.isCatalogsActive,
          'subtitleActive': addon.isSubtitlesActive,
          'searchActive': addon.isSearchActive,
          'types': _safeTypes(addon.manifest.types),
          'resources': _safeResources(addon.manifest.resources),
          'catalogCount': addon.manifest.catalogs.length,
        };
      }).toList(),
    };
  }

  static Map<String, Object?> device({
    required String buildRun,
    required String buildCommit,
    required bool foreground,
    required bool diagnosticsEnabled,
    required bool navigatorReady,
    required bool playerActive,
    required bool playerPlaying,
    required Map<String, Object?> matrix,
  }) => <String, Object?>{
    'accepted': true,
    'platform': 'ios',
    'buildRun': buildRun,
    'buildCommit': buildCommit,
    'foreground': foreground,
    'diagnosticsEnabled': diagnosticsEnabled,
    'navigatorReady': navigatorReady,
    'playerActive': playerActive,
    'playerPlaying': playerPlaying,
    'matrix': {
      for (final key in const [
        'runId', 'phase', 'channelsDone', 'totalChannels',
        'sourcesDone', 'verifiedSources', 'requestedSourcesVerified',
        'failoverPlaybackSessions', 'uploadFailures'
      ])
        key: matrix[key],
    },
  };
}
