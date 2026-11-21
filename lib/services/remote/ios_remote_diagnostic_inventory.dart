import '../../models/addon/addon.dart';
import 'ios_remote_command_contract.dart';

/// Read-only responses for the opt-in iOS Torriodb diagnostics transport.
/// Never expose addon configuration URLs, credentials, headers or streams.
abstract final class IosRemoteDiagnosticInventory {
  static const commandSchema = 2;
  static const maximumReportedAddons = 32;

  static Map<String, Object?> capabilities() => <String, Object?>{
    'accepted': true,
    'schema': commandSchema,
    'receiptSchema': 2,
    'receiptDelivery': 'persisted_retry_until_uploaded',
    'interruptedExecution': 'uncertain_without_replay',
    'transport': 'torriodb_device_scoped',
    'remoteOperations': IosRemoteCommandContract.manifest(),
    'pollSeconds': 12,
    'readOnly': const [
      'diagnostic_capabilities', 'diagnostic_snapshot',
      'test_status', 'addon_inventory', 'state',
      'live_matrix_status', 'live_experiment_status',
      'discover_live_matrix', 'probe_addon',
      'diagnostic_journal_status', 'diagnostic_journal_tail',
      'device_inventory', 'diagnostic_process_metrics',
      'diagnostic_http_probe',
      'diagnostic_media_sources', 'diagnostic_plan_status',
      'command_contracts', 'media_discover', 'media_search_addons',
      'media_resolve', 'live_channels', 'live_health_rank',
      'live_scan_status', 'player_verify', 'app_inspect',
      'app_screenshot', 'crash_evidence', 'settings_inspect',
    ],
    'boundedTests': const [
      'probe_native_channel', 'live_scan', 'live_scan_cancel',
      'start_live_matrix_catalog',
      'start_live_matrix', 'cancel_live_matrix',
    ],
    'playbackChanging': const [
      'open_channel', 'remote', 'player', 'media_play_resolved',
      'live_channel_switch', 'player_recover',
    ],
    'appChanging': const ['app_navigate', 'settings_update'],
    'indicator': 'dismissible_and_remotely_toggleable',
    'uiOnly': const ['test_indicator'],
    'declarativePlans': const [
      'diagnostic_plan', 'diagnostic_plan_cancel',
      'diagnostic_plan_status',
    ],
    'artifactExports': const ['diagnostic_export'],
    'remoteMediaTesting': const [
      'diagnostic_media_sources', 'diagnostic_open_media',
      'diagnostic_open_reference',
    ],
    'planLimits': const {
      'maxSteps': 80,
      'maxExecutions': 300,
      'maxRepeatPerStep': 25,
      'maxWaitMsPerExecution': 60000,
      'requiresOptInForPlaybackCommands': true,
    },
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
