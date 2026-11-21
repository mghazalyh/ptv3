/// Versioned, machine-readable contracts for the remote operations newly
/// exposed by PlayTorrio. Source code is still authoritative for validation.
/// Existing diagnostic actions retain their established contracts unchanged.
abstract final class IosRemoteCommandContract {
  static const schema = 1;

  static const operations = <String, Map<String, Object?>>{
    'media_discover': {
      'readOnly': true,
      'category': 'discovery',
      'required': <String>[],
      'optional': <String>[
        'type', 'query', 'fromYear', 'toYear', 'language', 'country',
        'genreId', 'sort', 'page', 'limit',
      ],
      'returns': 'TMDB titles and paging; not a stream availability claim',
    },
    'media_search_addons': {
      'readOnly': true,
      'category': 'discovery',
      'required': <String>['query'],
      'optional': <String>['type', 'limit'],
      'returns': 'deduplicated installed-addon media identifiers',
    },
    'media_resolve': {
      'readOnly': true,
      'category': 'discovery',
      'required': <String>['type', 'tmdbId', 'title'],
      'optional': <String>['year'],
      'returns': 'resolved playback resource identity',
    },
    'media_play_resolved': {
      'readOnly': false,
      'changesPlayback': true,
      'category': 'media',
      'required': <String>['type', 'tmdbId', 'title'],
      'optional': <String>['year', 'sourceIndex'],
      'returns': 'navigation accepted; verify separately with player_verify',
    },
    'live_channels': {
      'readOnly': true,
      'category': 'live_tv',
      'required': <String>[],
      'optional': <String>['query', 'addonHost', 'pages', 'limit'],
      'returns': 'matching installed-addon channel identities',
    },
    'live_channel_switch': {
      'readOnly': false,
      'changesPlayback': true,
      'category': 'live_tv',
      'required': <String>['query'],
      'optional': <String>['sourceIndex'],
      'returns': 'exactly one matching channel or ambiguity',
    },
    'live_health_rank': {
      'readOnly': true,
      'category': 'live_tv',
      'required': <String>[],
      'optional': <String>[
        'query', 'limit', 'minVerified', 'maxAgeHours',
      ],
      'returns': 'historical native evidence; not current availability',
    },
    'live_scan': {
      'readOnly': false,
      'category': 'testing',
      'requiresIdleDevice': true,
      'required': <String>['runId', 'channels'],
      'optional': <String>['verifyNative'],
      'returns': 'asynchronous scan execution state',
    },
    'live_visual_scan': {
      'readOnly': false,
      'category': 'live_tv_visual_inspection',
      'requiresIdleDevice': true,
      'required': <String>['runId', 'channels'],
      'optional': <String>['contentHint', 'framesPerChannel', 'maxSources'],
      'limits': 'up to 15 channels, 2 frames/channel, 3 sources/channel',
      'returns': 'run status and bounded private decoded-frame evidence paths',
      'neverClaims': 'broadcast classification is not performed on device',
    },
    'live_visual_scan_status': {
      'readOnly': true,
      'category': 'live_tv_visual_inspection',
      'required': <String>[],
      'optional': <String>[],
      'returns': 'scan state, sampled channels and private evidence filenames',
    },
    'live_visual_scan_cancel': {
      'readOnly': false,
      'category': 'live_tv_visual_inspection',
      'required': <String>[],
      'optional': <String>[],
      'returns': 'nonblocking cancellation request for a visual scan',
    },
    'live_scan_status': {
      'readOnly': true,
      'category': 'testing',
      'required': <String>[],
      'optional': <String>[],
      'returns': 'bounded scan progress and health observations',
    },
    'live_scan_cancel': {
      'readOnly': false,
      'category': 'testing',
      'required': <String>[],
      'optional': <String>[],
      'returns': 'cancel request acknowledged',
    },
    'player_verify': {
      'readOnly': true,
      'category': 'playback',
      'required': <String>[],
      'optional': <String>['sampleMs'],
      'returns': 'two measured samples and playback progression',
    },
    'player_recover': {
      'readOnly': false,
      'changesPlayback': true,
      'category': 'playback',
      'required': <String>[],
      'optional': <String>['strategy'],
      'returns': 'recovery attempt plus observed playback verification',
    },
    'app_inspect': {
      'readOnly': true,
      'category': 'application',
      'required': <String>[],
      'optional': <String>[],
      'returns': 'route, focus, lifecycle, matrix and player state',
    },
    'app_screenshot': {
      'readOnly': true,
      'category': 'application',
      'required': <String>[],
      'optional': <String>[],
      'returns': 'bounded app-owned Flutter screenshot capture metadata',
    },
    'app_navigate': {
      'readOnly': false,
      'category': 'application',
      'required': <String>['destination'],
      'optional': <String>[],
      'returns': 'supported semantic navigation result',
    },
    'crash_evidence': {
      'readOnly': true,
      'category': 'diagnostics',
      'required': <String>[],
      'optional': <String>[],
      'returns': 'bounded sanitized exception and previous-session hints',
    },
    'settings_inspect': {
      'readOnly': true,
      'category': 'settings',
      'required': <String>[],
      'optional': <String>[],
      'returns': 'safe allowlisted player display/audio preferences',
    },
    'settings_update': {
      'readOnly': false,
      'changesSettings': true,
      'category': 'settings',
      'required': <String>['setting', 'value'],
      'optional': <String>[],
      'returns': 'applied allowlisted preference; no arbitrary key access',
    },
  };

  static Map<String, Object?> manifest() => <String, Object?>{
    'schema': schema,
    'operationCount': operations.length,
    'operations': operations,
    'verificationPolicy': 'accepted_is_not_playback_verified',
    'receiptLifecycle': <String>[
      'executing', 'completed', 'failed', 'uncertain',
    ],
    'transport': 'existing_torriodb_device_scoped',
    'nativeTesting': 'foreground_and_device_idle_only',
    'broadcastInspection': 'actual_decoded_frames_not_metadata',
    'contentClassification': 'external_chatgpt_image_inspection_required',
    'visualEvidencePath':
        'playtorrio/control/ios/visual/<deviceId>/<runId>/frame_<n>_<n>.json',
  };
}
