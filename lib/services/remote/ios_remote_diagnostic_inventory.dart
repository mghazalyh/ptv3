import '../../models/addon/addon.dart';

/// Read-only responses for the opt-in iOS Torriodb diagnostics transport.
/// Never expose addon configuration URLs, credentials, headers or streams.
abstract final class IosRemoteDiagnosticInventory {
  static const commandSchema = 2;
  static const maximumReportedAddons = 32;

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
          'name': addon.manifest.name.length > 80
              ? addon.manifest.name.substring(0, 80)
              : addon.manifest.name,
          'id': addon.manifest.id.length > 100
              ? addon.manifest.id.substring(0, 100)
              : addon.manifest.id,
          'host': host,
          'enabled': addon.enabled,
          'streamActive': addon.isStreamsActive,
          'catalogActive': addon.isCatalogsActive,
          'subtitleActive': addon.isSubtitlesActive,
          'searchActive': addon.isSearchActive,
          'types': addon.manifest.types.take(10).toList(),
          'resources': addon.manifest.resources.take(10).toList(),
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
        'failoverPlaybackSessions', 'uploadFailures',
        'candidateReportsUploaded', 'candidateReportUploadFailures'
      ])
        key: matrix[key],
    },
  };
}
