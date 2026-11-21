import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:media_kit/media_kit.dart';

import 'package:window_manager/window_manager.dart';

import './pages/home/home_page.dart';
import './pages/discover/discover_page.dart';
import './services/addon/addon_manager.dart';
import './services/my_list/github_library_cloud.dart';
import './services/config/torriodb_portable_sync.dart';
import './services/stream/watch_source_preferences.dart';
import './services/theme/app_theme_service.dart';
import './services/updater/app_updater_service.dart';
import './services/books/continue_reading_service.dart';
import './services/books/reader_settings.dart';
import './services/continue_watching/continue_watching_service.dart';
import './services/continue_watching/watched_history_service.dart';
import './services/theme/custom_background_service.dart';
import './services/theme/dock_settings.dart';
import './services/theme/glass_settings.dart';
import './services/audiobook/audiobook_settings.dart';
import './services/home/home_page_settings.dart';
import './services/home/home_section_order_service.dart';
import './services/iptv/iptv_controller.dart';
import './services/iptv/iptv_settings.dart';
import './services/manga/manga_settings.dart';
import './services/music/music_download_service.dart';
import './services/music/music_settings.dart';
import './services/music/qobuz_music_service.dart';
import './services/my_list/my_list_service.dart';
import './services/player/player_settings.dart';
import './services/download/download_service.dart';
import './services/cache/storage_cache_service.dart';
import './services/config/env_service.dart';
import './services/config/windows_settings_recovery.dart';
import './services/window/window_service.dart';
import './services/p2p/p2p_settings_service.dart';
import './services/discord/discord_rpc_service.dart';
import './services/player/night_mode_diagnostics.dart';
import './services/player/ios_audio_telemetry.dart';
import './services/remote/lan_remote_service.dart';
import './services/remote/lan_cast_request.dart';
import './services/remote/unattended_test_activity.dart';
import './services/remote/ios_remote_diagnostic_inventory.dart';
import './services/remote/ios_remote_command_contract.dart';
import './services/remote/ios_remote_media_discovery.dart';
import './services/remote/ios_remote_live_health_history.dart';
import './services/remote/ios_remote_live_scan.dart';
import './services/remote/ios_remote_app_observability.dart';
import './services/remote/ios_remote_safe_settings.dart';
import './services/remote/ios_remote_playback_verification.dart';
import './services/remote/ios_diagnostic_journal.dart';
import './services/remote/ios_network_diagnostic_probe.dart';
import './services/remote/ios_media_diagnostic_request.dart';
import './services/player/device_diagnostic_inventory.dart';
import './services/player/ios_native_process_metrics.dart';
import './models/movie/video.dart';
import './models/stream/stream_model.dart';
import './services/remote/ios_adhoc_diagnostic_coordinator.dart';
import './widgets/remote/unattended_test_indicator.dart';
import './services/remote/github_diagnostic_control.dart';
import './services/remote/github_stremio_addon_probe.dart';
import './services/player/live_tv/live_tv_experiment_policy.dart';
import './services/player/live_tv/live_tv_matrix_runner.dart';
import './services/player/live_tv/live_verified_source_preference.dart';
import './services/player/live_tv/live_native_channel_verifier.dart';
import './services/player/live_tv/live_unattended_native_probe_request.dart';
import './services/stream/stream_service.dart';
import './services/metadata/metadata_service.dart';
import './models/movie/movie.dart';
import './models/movie/movie_detail.dart';
import './pages/player/watch_screen.dart';
import './pages/player/player_screen.dart';
import './widgets/updater/update_dialog.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  // Prepare the stable Windows profile before any SharedPreferences or secure
  // settings service reads its state. Never overwrite a populated profile.
  if (Platform.isWindows) await WindowsSettingsRecovery.prepare();
  await NightModeDiagnostics.initializeDebugMode();
  if (Platform.isIOS) await IosAudioTelemetry.instance.initialize();
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();
    await WindowService.instance.initialize();
  }
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  await EnvService.initialize();
  await GitHubLibraryCloud.instance.initialize();
  if (Platform.isIOS) {
    await GithubDiagnosticControl.instance.initialize();
    await LiveTvExperimentStore.instance.initialize();
  }
  await DockSettings.initialize();
  await WatchSourcePreferencesService.initialize();
  await TorriodbPortableSync.instance.refresh(force: true);
  await HomeSectionOrderService.initialize();
  await PlayerSettings.initialize();
  if (Platform.isWindows && NightModeDiagnostics.instance.isActive) {
    final audit = WindowsSettingsRecovery.lastAudit;
    if (audit != null) {
      unawaited(NightModeDiagnostics.instance.record('storage-profile',
          'state=${audit.state} preferenceCount=${audit.preferenceCount}'));
    }
  }
  await Future.wait([
    AddonManager.instance.initialize(),
    AppThemeService.initialize(),
    AudiobookSettings.initialize(),
    ContinueWatchingService.initialize(),
    WatchedHistoryService.initialize(),
    ContinueReadingService.initialize(),
    ReaderSettings.initialize(),
    CustomBackgroundService.initialize(),
    GlassSettings.initialize(),
    HomePageSettings.initialize(),
    IptvController.instance.init(),
    IptvSettings.initialize(),
    MangaSettings.initialize(),
    MusicSettings.initialize(),
    MusicDownloadService.instance.init(),
    QobuzMusicService.instance.initialize(),
    MyListService.initialize(),
    P2pSettingsService.initialize(),
    DownloadService.instance.initialize(),
    DiscordRpcService.instance.initialize(),
  ]);
  runApp(const PlayTorrioApp());
  unawaited(StorageCacheService.instance.pruneOldTemporaryCache());
}

class PlayTorrioApp extends StatefulWidget {
  const PlayTorrioApp({super.key});

  @override
  State<PlayTorrioApp> createState() => _PlayTorrioAppState();
}

class _PlayTorrioAppState extends State<PlayTorrioApp>
    with WidgetsBindingObserver {
  static bool _hasCheckedInitialUpdate = false;
  static bool _isShowingUpdateDialog = false;
  Timer? _homeSyncTimer;
  DateTime? _lastUpdateCheckAt;
  AppLifecycleState _lifecycleState = AppLifecycleState.resumed;
  final LiveTvMatrixRunner _liveMatrix = LiveTvMatrixRunner(
    onCandidateFinished: (candidate) {
      unawaited(IosDiagnosticJournal.instance.record(
          'live.matrix.candidate', candidate));
      unawaited(IosRemoteLiveHealthHistory.instance.recordCandidate(candidate));
    },
    onStatusChanged: (status) {
      UnattendedTestActivity.instance.updateMatrix(status);
      unawaited(IosDiagnosticJournal.instance.record(
          'live.matrix.status', status));
    },
  );

  void _onRemoteDiagnosticsEnabled() {
    IosDiagnosticJournal.instance.enabled =
        GithubDiagnosticControl.instance.enabled.value;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    LanRemoteService.instance.onNavigationCommand = _handleRemoteNavigation;
    LanRemoteService.instance.onCastRequest = _handleLanCastRequest;
    if (Platform.isIOS) {
      GithubDiagnosticControl.instance.onCommand = _dispatchGithubDiagnostic;
      GithubDiagnosticControl.instance.enabled.addListener(
          _onRemoteDiagnosticsEnabled);
      _onRemoteDiagnosticsEnabled();
      GithubDiagnosticControl.instance.start();
    }
    // Pick up changes made on another device without reloading the Home page.
    _homeSyncTimer = Timer.periodic(const Duration(minutes: 3), (_) {
      if (mounted && _lifecycleState == AppLifecycleState.resumed) {
        unawaited(TorriodbPortableSync.instance.refresh(force: true));
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_hasCheckedInitialUpdate) {
        _hasCheckedInitialUpdate = true;
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (mounted) _checkForUpdates();
        });
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
    if (state == AppLifecycleState.resumed) {
      // The old ten-minute throttle delayed cross-device updates on resume.
      unawaited(TorriodbPortableSync.instance.refresh(force: true));
      if (Platform.isIOS) {
        unawaited(GithubDiagnosticControl.instance.pollNow());
      }
      if (Platform.isWindows && _hasCheckedInitialUpdate) {
        final last = _lastUpdateCheckAt;
        if (last == null ||
            DateTime.now().difference(last) >= const Duration(minutes: 5)) {
          unawaited(_checkForUpdates());
        }
      }
    }
  }

  @override
  void dispose() {
    _homeSyncTimer?.cancel();
    LanRemoteService.instance.onNavigationCommand = null;
    LanRemoteService.instance.onCastRequest = null;
    if (Platform.isIOS) {
      GithubDiagnosticControl.instance.enabled.removeListener(
          _onRemoteDiagnosticsEnabled);
      GithubDiagnosticControl.instance.onCommand = null;
    }
    // Receiver sockets close when the application is disposed.
    unawaited(LanRemoteService.instance.stopHosting());
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }


  /// Discover only real TV channels published by enabled, installed Stremio
  /// addons. No command-supplied URL or arbitrary host is ever fetched.
  Future<Map<String, Object?>> _discoverLiveChannels(
      Map<String, dynamic> args) async {
    const allowed = <String>{'query', 'addonHost', 'pages', 'limit'};
    if (args.keys.any((key) => !allowed.contains(key)) ||
        args['query'] != null && args['query'] is! String ||
        args['addonHost'] != null && args['addonHost'] is! String ||
        args['pages'] != null && args['pages'] is! int ||
        args['limit'] != null && args['limit'] is! int) {
      return <String, Object?>{
        'accepted': false, 'reason': 'invalid_channel_search',
      };
    }
    final wantedHost = args['addonHost']?.toString().toLowerCase() ?? '';
    final query = args['query']?.toString().trim().toLowerCase() ?? '';
    if (query.length > 100 || wantedHost.length > 120 ||
        wantedHost.isNotEmpty &&
          !RegExp(r'^[a-z0-9.-]+$').hasMatch(wantedHost)) {
      return <String, Object?>{
        'accepted': false, 'reason': 'invalid_channel_query',
      };
    }
    final pages = (args['pages'] is int ? args['pages'] as int : 3)
        .clamp(1, 6).toInt();
    final limit = (args['limit'] is int ? args['limit'] as int : 100)
        .clamp(1, 150).toInt();
    final found = <String, String>{};
    final usedHosts = <String>{};
    var catalogCount = 0;
    for (final addon in AddonManager.instance.activeCatalogAddons) {
      final host = Uri.tryParse(addon.baseUrl)?.host.toLowerCase() ?? '';
      if (wantedHost.isNotEmpty && wantedHost != host) continue;
      final tvCatalogs = addon.manifest.catalogs.where((catalog) =>
          catalog.type == 'tv' && catalog.isHomeEligible);
      for (final catalog in tvCatalogs) {
        if (found.length >= limit) break;
        catalogCount++;
        for (var page = 0; page < (catalog.supportsSkip ? pages : 1);
            page++) {
          if (found.length >= limit) break;
          try {
            final entries = await MetadataService.fetchCatalog(
              baseUrl: addon.baseUrl, type: 'tv',
              catalogId: catalog.id,
              skip: page == 0 ? null : page * 100,
              forceRefresh: true,
            ).timeout(const Duration(seconds: 18));
            if (entries.isEmpty) break;
            usedHosts.add(host);
            for (final entry in entries) {
              final id = entry.id.trim();
              final title = entry.name.trim();
              if (id.length < 4 || id.length > 180 ||
                  title.isEmpty || title.length > 120 ||
                  !(id.startsWith('nltv:') || id.startsWith('iptv:')) ||
                  !addon.manifest.supportsRequest('stream', 'tv', id)) {
                continue;
              }
              if (query.isNotEmpty &&
                  !title.toLowerCase().contains(query) &&
                  !id.toLowerCase().contains(query)) continue;
              found.putIfAbsent(id, () => title);
              if (found.length >= limit) break;
            }
          } catch (error) {
            debugPrint('[LiveMatrix] Installed catalog probe: ' +
                error.runtimeType.toString());
            break;
          }
        }
      }
    }
    // The known-good Roku backup should be present as a regression control.
    const control = 'nltv:us:CineRomantico.us';
    if (query.isEmpty && !found.containsKey(control) && found.isNotEmpty &&
        AddonManager.instance.activeStreamAddons.any((addon) =>
            addon.manifest.supportsRequest('stream', 'tv', control))) {
      if (found.length >= limit) found.remove(found.keys.last);
      found[control] = 'Cine Romántico';
    }
    return <String, Object?>{
      'accepted': found.isNotEmpty,
      'count': found.length,
      'query': query,
      'catalogsChecked': catalogCount,
      'installedAddonHosts': usedHosts.toList(),
      'channels': found.entries.map((entry) => <String, String>{
        'id': entry.key, 'title': entry.value,
      }).toList(),
    };
  }

  Future<Map<String, Object?>> _diagnosticMediaRequest(
      Map<String, dynamic> args, {required bool open}) async {
    try {
      if (open && _liveMatrix.status()['phase'] == 'running') {
        return <String, Object?>{
          'accepted': false, 'reason': 'matrix_in_progress'};
      }
      final media = IosMediaDiagnosticRequest.parse(args);
      final sources = await StreamService.fetchStreams(
        type: media.type, id: media.streamId, title: media.title,
        year: media.year, season: media.season, episode: media.episode,
      ).timeout(const Duration(seconds: 30),
          onTimeout: (sink) => sink.close()).take(media.maxSources).toList();
      final results = sources.asMap().entries.map((entry) {
        final source = entry.value;
        return <String, Object?>{
          'index': entry.key,
          'addon': source.addonName,
          'name': source.name,
          'title': source.title,
          'url': source.url,
          'infoHash': source.infoHash,
          'fileIdx': source.fileIdx,
          'headers': source.headers,
          'quality': source.quality,
          'codec': source.codec,
          'isHDR': source.isHDR,
        };
      }).toList();
      unawaited(IosDiagnosticJournal.instance.record(
          'media.sources_resolved', <String, Object?>{
        ...media.toJson(),
        'count': sources.length,
        'selected': media.sourceIndex,
        'providers': sources.map((source) => source.addonName).toList(),
        'sources': results,
      }));
      if (!open) {
        // Keep command receipts bounded; an exact source may be inspected via
        // sourceIndex after this discovery, or the full trace via the journal.
        return <String, Object?>{
          'accepted': true, ...media.toJson(), 'sourceCount': sources.length,
          'sources': results.skip(media.sourceIndex).take(12).toList(),
          'returnedCount': min(12,
              max(0, results.length - media.sourceIndex)),
        };
      }
      if (media.sourceIndex >= sources.length) {
        return <String, Object?>{
          'accepted': false, 'reason': 'invalid_source_index',
          'sourceCount': sources.length};
      }
      final navigator = navigatorKey.currentState;
      if (navigator == null || !mounted) {
        return <String, Object?>{
          'accepted': false, 'reason': 'navigator_unavailable'};
      }
      final episode = media.type == 'series'
          ? Video(id: media.streamId, title: media.title,
              season: media.season, episode: media.episode)
          : null;
      final detail = MovieDetail(
        id: media.id, type: media.type, name: media.title,
        year: media.year?.toString(),
        videos: episode == null ? const [] : [episode],
        behaviorHints: media.type == 'tv'
            ? const <String, dynamic>{'isLive': true}
            : const <String, dynamic>{},
      );
      navigator.popUntil((route) => route.isFirst);
      navigator.push(MaterialPageRoute(builder: (_) => PlayerScreen(
        source: sources[media.sourceIndex],
        availableSources: sources,
        title: media.title,
        detail: detail,
        episode: episode,
      )));
      return <String, Object?>{
        'accepted': true,
        'sourceCount': sources.length,
        'selectedIndex': media.sourceIndex,
        'selectedAddon': sources[media.sourceIndex].addonName,
        'resourceId': media.streamId,
      };
    } catch (error) {
      return <String, Object?>{
        'accepted': false, 'reason': 'media_diagnostic_failed',
        'errorClass': error.runtimeType.toString(),
        'error': error.toString(),
      };
    }
  }

  Future<Map<String, Object?>> _openReferenceMedia(
      Map<String, dynamic> args) async {
    if (_liveMatrix.status()['phase'] == 'running') {
      return <String, Object?>{
        'accepted': false, 'reason': 'matrix_in_progress'};
    }
    if (args.keys.any((key) => !const <String>{
        'url', 'title', 'headers', 'infoHash', 'fileIdx',
      }.contains(key))) {
      return <String, Object?>{
        'accepted': false, 'reason': 'invalid_reference_options'};
    }
    final url = args['url'];
    final infoHash = args['infoHash'];
    final title = args['title'] ?? 'Diagnostic reference media';
    final rawHeaders = args['headers'];
    if (url is! String && infoHash is! String ||
        url is String && url.length > 4096 ||
        infoHash is String &&
            (infoHash.isEmpty || infoHash.length > 120) ||
        title is! String || title.isEmpty || title.length > 200 ||
        rawHeaders != null && rawHeaders is! Map) {
      return <String, Object?>{
        'accepted': false, 'reason': 'invalid_reference_media'};
    }
    if (url is String) {
      final uri = Uri.tryParse(url);
      if (uri == null || !const {'https', 'http'}.contains(uri.scheme) ||
          uri.host.isEmpty) {
        return <String, Object?>{
          'accepted': false, 'reason': 'invalid_reference_url'};
      }
    }
    final headers = <String, String>{};
    if (rawHeaders is Map) {
      if (rawHeaders.length > 20) {
        return <String, Object?>{
          'accepted': false, 'reason': 'too_many_headers'};
      }
      for (final item in rawHeaders.entries) {
        if (item.key is! String || item.value is! String) {
          return <String, Object?>{
            'accepted': false, 'reason': 'invalid_reference_headers'};
        }
        headers[item.key as String] = item.value as String;
      }
    }
    final navigator = navigatorKey.currentState;
    if (navigator == null || !mounted) {
      return <String, Object?>{
        'accepted': false, 'reason': 'navigator_unavailable'};
    }
    final source = StreamSource(
      name: 'Remote diagnostic source',
      url: url is String ? url : null,
      infoHash: infoHash is String ? infoHash : null,
      fileIdx: args['fileIdx'] is int ? args['fileIdx'] as int : null,
      addonName: 'PlayTorrio Diagnostic',
      headers: headers,
    );
    unawaited(IosDiagnosticJournal.instance.record(
      'media.reference_open', <String, Object?>{
        'url': source.url, 'infoHash': source.infoHash,
        'headers': headers, 'title': title,
      }));
    navigator.popUntil((route) => route.isFirst);
    navigator.push(MaterialPageRoute(builder: (_) => PlayerScreen(
      source: source,
      availableSources: [source],
      title: title,
      detail: MovieDetail(
        id: 'diagnostic:reference', type: 'movie', name: title),
    )));
    return <String, Object?>{'accepted': true, 'title': title};
  }

  /// Publish a few exact journal byte ranges per command and report a
  /// restartable nextOffset. No changes are made to the on-device matrix.
  Future<Map<String, Object?>> _exportDiagnostics(
      Map<String, dynamic> args) async {
    final runId = args['runId'];
    final rawOffset = args['offset'] ?? 0;
    final rawChunks = args['maxChunks'] ?? 4;
    final segment = args['segment'] ?? 'current';
    if (runId is! String ||
        !RegExp(r'^[A-Za-z0-9_-]{8,50}$').hasMatch(runId) ||
        rawOffset is! int || rawOffset < 0 ||
        rawChunks is! int || rawChunks < 1 || rawChunks > 8 ||
        segment is! String ||
        !const <String>{'current', 'previous', 'capture'}.contains(segment)) {
      return <String, Object?>{
        'accepted': false, 'reason': 'invalid_export_request',
      };
    }
    var offset = rawOffset;
    var published = 0;
    var complete = false;
    for (var n = 0; n < rawChunks; n++) {
      final chunk = await IosDiagnosticJournal.instance.readChunk(
        segment: segment, offset: offset,
      );
      if (chunk['accepted'] != true) {
        return <String, Object?>{
          ...chunk, 'nextOffset': offset, 'publishedChunks': published,
        };
      }
      try {
        await GithubDiagnosticControl.instance.publishJournalFile(
          runId, 'chunk_${segment}_${offset.toString().padLeft(8, '0')}',
          chunk,
        );
      } catch (error) {
        return <String, Object?>{
          'accepted': false, 'reason': 'artifact_upload_failed',
          'errorClass': error.runtimeType.toString(),
          'nextOffset': offset, 'publishedChunks': published,
        };
      }
      published++;
      offset = chunk['nextOffset'] as int;
      complete = chunk['complete'] == true;
      if (complete) break;
    }
    return <String, Object?>{
      'accepted': true, 'runId': runId,
      'segment': segment, 'publishedChunks': published,
      'nextOffset': offset, 'complete': complete,
    };
  }

  bool _remoteDeviceIdle() {
    if (!Platform.isIOS || !mounted ||
        _lifecycleState != AppLifecycleState.resumed ||
        _liveMatrix.status()['phase'] == 'running') return false;
    final navigator = navigatorKey.currentState;
    if (navigator == null || navigator.canPop()) return false;
    try {
      final player = LanRemoteService.instance.playerStatus?.call();
      return player == null || player.isEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, Object?>> _verifyRemotePlayback(
      Map<String, dynamic> args) async {
    if (args.keys.any((key) => key != 'sampleMs') ||
        args['sampleMs'] != null && args['sampleMs'] is! int) {
      return <String, Object?>{
        'accepted': false, 'reason': 'invalid_playback_verification',
      };
    }
    final sample = (args['sampleMs'] is int
        ? args['sampleMs'] as int : 3000).clamp(1000, 10000).toInt();
    final handler = GithubDiagnosticControl.instance.onPlayerCommand;
    if (handler == null) return <String, Object?>{
      'accepted': false, 'reason': 'no_active_player',
    };
    if (_lifecycleState != AppLifecycleState.resumed) {
      return <String, Object?>{
        'accepted': false, 'reason': 'app_not_foreground',
      };
    }
    final before = await handler('state', <String, dynamic>{});
    if (before['accepted'] != true) return before;
    await Future<void>.delayed(Duration(milliseconds: sample));
    if (!mounted || _lifecycleState != AppLifecycleState.resumed) {
      return <String, Object?>{
        'accepted': false, 'reason': 'app_left_foreground',
      };
    }
    final after = await handler('state', <String, dynamic>{});
    if (after['accepted'] != true) return after;
    return IosRemotePlaybackVerification.compare(
      before, after, sampleMs: sample,
    );
  }

  Future<Map<String, Object?>> _recoverRemotePlayback(
      Map<String, dynamic> args) async {
    if (_liveMatrix.status()['phase'] == 'running') return <String, Object?>{
      'accepted': false, 'reason': 'matrix_in_progress',
    };
    const allowed = <String>{'strategy'};
    final strategy = args['strategy'] ?? 'auto';
    if (args.keys.any((key) => !allowed.contains(key)) ||
        !const {'auto', 'restart', 'resume', 'retry_live'}.contains(strategy)) {
      return <String, Object?>{
        'accepted': false, 'reason': 'invalid_recovery_strategy',
      };
    }
    final handler = GithubDiagnosticControl.instance.onPlayerCommand;
    if (handler == null) return <String, Object?>{
      'accepted': false, 'reason': 'no_active_player',
    };
    final before = await handler('state', <String, dynamic>{});
    if (before['accepted'] != true) return before;
    final live = before['isLive'] == true;
    if (!live && strategy == 'retry_live') return <String, Object?>{
      'accepted': false, 'reason': 'not_live',
    };
    Map<String, Object?> attempted;
    var method = 'play';
    if (live) {
      method = 'retry_live';
      attempted = await handler('retry_live', <String, dynamic>{});
    } else if (strategy == 'restart') {
      method = 'restart_media';
      attempted = await handler('restart_media', <String, dynamic>{});
      final position = before['positionMs'];
      if (attempted['accepted'] == true &&
          position is num && position > 1000) {
        await Future<void>.delayed(const Duration(milliseconds: 900));
        await handler('seek_ms', <String, dynamic>{
          'positionMs': position.toInt(),
        });
      }
    } else {
      attempted = await handler('play', <String, dynamic>{});
    }
    if (attempted['accepted'] != true) return <String, Object?>{
      'accepted': false,
      'reason': 'recovery_action_failed',
      'method': method,
      'attempt': attempted,
    };
    final verification = await _verifyRemotePlayback(
        <String, dynamic>{'sampleMs': 4000});
    return <String, Object?>{
      'accepted': true,
      'method': method,
      'actionExecuted': true,
      'recoveryVerified': verification['verified'] == true,
      'verification': verification,
      'previousPositionMs': before['positionMs'],
    };
  }

  /// Execute cloud commands with the same in-app controls as the paired LAN
  /// remote, plus channel discovery and native playback diagnostic actions.
  /// The owner enables unattended access once; no per-command prompt appears.
  Future<Map<String, Object?>> _dispatchGithubDiagnostic(
      String action, Map<String, dynamic> args) async {
    try {
      final navigator = navigatorKey.currentState;
      switch (action) {
        case 'diagnostic_capabilities':
          return IosRemoteDiagnosticInventory.capabilities();
        case 'command_contracts':
          return IosRemoteCommandContract.manifest();
        case 'media_discover':
          return await IosRemoteMediaDiscovery.discover(args);
        case 'media_search_addons':
          return await IosRemoteMediaDiscovery.searchAddons(args);
        case 'media_resolve':
          return await IosRemoteMediaDiscovery.resolve(args);
        case 'media_play_resolved':
          if (_liveMatrix.status()['phase'] == 'running') {
            return <String, Object?>{
              'accepted': false, 'reason': 'matrix_in_progress',
            };
          }
          if (args.keys.any((key) => !const <String>{
              'type', 'tmdbId', 'title', 'year', 'sourceIndex',
              'season', 'episode',
            }.contains(key))) return <String, Object?>{
              'accepted': false, 'reason': 'invalid_media_play_request',
            };
          final resolved = await IosRemoteMediaDiscovery.resolve(
            <String, dynamic>{
              for (final key in const ['type', 'tmdbId', 'title', 'year'])
                if (args.containsKey(key)) key: args[key],
            });
          if (resolved['accepted'] != true) return resolved;
          return _diagnosticMediaRequest(<String, dynamic>{
            'type': resolved['type'],
            'id': resolved['id'],
            'title': resolved['title'],
            if (resolved['year'] != null) 'year': resolved['year'],
            if (args['sourceIndex'] != null)
              'sourceIndex': args['sourceIndex'],
            if (args['season'] != null) 'season': args['season'],
            if (args['episode'] != null) 'episode': args['episode'],
          }, open: true);
        case 'live_channels':
          return _discoverLiveChannels(args);
        case 'live_health_rank':
          return IosRemoteLiveHealthHistory.instance.rank(args);
        case 'live_channel_switch':
          if (_liveMatrix.status()['phase'] == 'running') {
            return <String, Object?>{
              'accepted': false, 'reason': 'matrix_in_progress',
            };
          }
          final query = args['query'];
          if (args.keys.any((key) =>
                  key != 'query' && key != 'sourceIndex') ||
              query is! String || query.trim().length < 2 ||
              query.length > 100) {
            return <String, Object?>{
              'accepted': false, 'reason': 'invalid_channel_search',
            };
          }
          final matches = await _discoverLiveChannels(
              <String, dynamic>{'query': query, 'limit': 150});
          final channels = matches['channels'];
          if (channels is! List || channels.isEmpty) {
            return <String, Object?>{
              'accepted': false, 'reason': 'channel_not_found',
            };
          }
          if (channels.length != 1) {
            return <String, Object?>{
              'accepted': false, 'reason': 'ambiguous_channel',
              'matches': channels.take(15).toList(),
              'count': channels.length,
            };
          }
          final exact = channels.single as Map;
          return _dispatchGithubDiagnostic('open_channel',
              <String, dynamic>{
                'channelId': exact['id'],
                'title': exact['title'],
                if (args['sourceIndex'] != null)
                  'sourceIndex': args['sourceIndex'],
              });
        case 'live_scan':
          return IosRemoteLiveScan.instance.start(
            args, deviceIdle: _remoteDeviceIdle,
          );
        case 'live_scan_status':
          return IosRemoteLiveScan.instance.status();
        case 'live_scan_cancel':
          return IosRemoteLiveScan.instance.cancel();
        case 'player_verify':
          return _verifyRemotePlayback(args);
        case 'player_recover':
          return _recoverRemotePlayback(args);
        case 'app_inspect':
          return IosRemoteAppObservability.instance.inspect(
            foreground: _lifecycleState == AppLifecycleState.resumed,
            navigatorReady: navigator != null,
            playerActive: LanRemoteService.instance.playerStatus?.call()
                .isNotEmpty == true,
            matrixRunning: _liveMatrix.status()['phase'] == 'running',
          );
        case 'app_screenshot':
          return IosRemoteAppObservability.instance.capture();
        case 'app_navigate':
          if (_liveMatrix.status()['phase'] == 'running') {
            return <String, Object?>{
              'accepted': false, 'reason': 'matrix_in_progress',
            };
          }
          final destination = args['destination'];
          if (navigator == null ||
              !const {'home', 'back', 'search'}.contains(destination) ||
              args.keys.any((key) =>
                  key != 'destination' && key != 'query')) {
            return <String, Object?>{
              'accepted': false, 'reason': 'invalid_navigation',
            };
          }
          if (destination == 'home') {
            navigator.popUntil((route) => route.isFirst);
          } else if (destination == 'back') {
            if (navigator.canPop()) navigator.pop();
          } else {
            final query = args['query'];
            if (query is! String || query.trim().length < 2 ||
                query.length > 120) {
              return <String, Object?>{
                'accepted': false, 'reason': 'invalid_search_query',
              };
            }
            navigator.push(MaterialPageRoute(
              settings: const RouteSettings(name: '/remote/search'),
              builder: (_) => DiscoverPage(
                query: query.trim(), isGenre: false,
              ),
            ));
          }
          return <String, Object?>{
            'accepted': true, 'destination': destination,
          };
        case 'settings_inspect':
          return IosRemoteSafeSettings.inspect();
        case 'settings_update':
          return IosRemoteSafeSettings.update(args);
        case 'addon_inventory':
          return IosRemoteDiagnosticInventory.addons(
            AddonManager.instance.addons);
        case 'diagnostic_plan':
          return await IosAdhocDiagnosticCoordinator.instance.start(
            args,
            matrixRunning: () =>
                _liveMatrix.status()['phase'] == 'running',
            dispatch: (action, parameters) =>
                _dispatchGithubDiagnostic(action, parameters),
            onStep: (step) {
              unawaited(IosDiagnosticJournal.instance.record(
                  'diagnostic.plan_step', step));
            },
            onFinished: (outcome) {
              unawaited(IosDiagnosticJournal.instance.record(
                  'diagnostic.plan_finished', outcome));
            },
          );
        case 'diagnostic_plan_status':
          return IosAdhocDiagnosticCoordinator.instance.status();
        case 'diagnostic_plan_cancel':
          return IosAdhocDiagnosticCoordinator.instance.cancel();
        case 'test_indicator':
          if (args.length != 1 || args['visible'] is! bool) {
            return <String, Object?>{
              'accepted': false, 'reason': 'invalid_indicator_setting',
            };
          }
          UnattendedTestActivity.instance
              .setIndicatorEnabled(args['visible'] as bool);
          return <String, Object?>{
            'accepted': true,
            'onDevice': UnattendedTestActivity.instance.snapshot.value.toJson(),
          };
        case 'diagnostic_media_sources':
          return await _diagnosticMediaRequest(args, open: false);
        case 'diagnostic_open_media':
          return await _diagnosticMediaRequest(args, open: true);
        case 'diagnostic_open_reference':
          return await _openReferenceMedia(args);
        case 'diagnostic_http_probe':
          final result = await IosNetworkDiagnosticProbe.run(args);
          unawaited(IosDiagnosticJournal.instance.record(
              'http.probe', result));
          return result;
        case 'diagnostic_journal_status':
          return IosDiagnosticJournal.instance.status();
        case 'diagnostic_journal_tail':
          final count = args['count'];
          final segment = args['segment'];
          return IosDiagnosticJournal.instance.tail(
            count: count is int ? count : 10,
            segment: segment is String ? segment : 'current',
          );
        case 'diagnostic_export':
          return _exportDiagnostics(args);
        case 'diagnostic_process_metrics':
          final metrics = await IosNativeProcessMetrics.capture();
          unawaited(IosDiagnosticJournal.instance.record(
              'device.process_metrics', metrics));
          return metrics;
        case 'device_inventory':
          final inventory = await DeviceDiagnosticInventory.instance.capture();
          unawaited(IosDiagnosticJournal.instance.record(
              'device.inventory', inventory));
          return <String, Object?>{
            'accepted': true, 'inventory': inventory,
          };
        case 'test_status':
          return <String, Object?>{
            'accepted': true,
            'onDevice': UnattendedTestActivity.instance.snapshot.value.toJson(),
            'matrix': _liveMatrix.status(),
          };
        case 'diagnostic_snapshot':
          final player = LanRemoteService.instance.playerStatus?.call() ??
              const <String, Object?>{};
          return IosRemoteDiagnosticInventory.device(
            buildRun: IosAudioTelemetry.buildRun,
            buildCommit: IosAudioTelemetry.buildCommit,
            foreground: _lifecycleState == AppLifecycleState.resumed,
            diagnosticsEnabled: GithubDiagnosticControl.instance.enabled.value,
            navigatorReady: navigator != null,
            playerActive: player.isNotEmpty,
            playerPlaying: player['playing'] == true,
            matrix: _liveMatrix.status(),
          );
        case 'live_experiment_status':
          return LiveTvExperimentStore.instance.status();
        case 'apply_live_experiment':
          return await LiveTvExperimentStore.instance.apply(args);
        case 'rollback_live_experiment':
          return await LiveTvExperimentStore.instance.rollback();
        case 'live_matrix_status':
          return _liveMatrix.status();
        case 'cancel_live_matrix':
          return _liveMatrix.cancel();
        case 'discover_live_matrix':
          return await _discoverLiveChannels(args);
        case 'start_live_matrix_catalog':
          final discovered = await _discoverLiveChannels(
              <String, dynamic>{
                for (final key in const <String>[
                  'query', 'addonHost', 'pages', 'limit',
                ])
                  if (args.containsKey(key)) key: args[key],
              });
          if ((discovered['count'] as int? ?? 0) < 50) {
            return <String, Object?>{
              'accepted': false,
              'reason': 'insufficient_installed_tv_catalog',
              'channelCount': discovered['count'],
            };
          }
          return _dispatchGithubDiagnostic('start_live_matrix',
              <String, dynamic>{
                'runId': args['runId'],
                'channels': discovered['channels'],
                if (args.containsKey('seed')) 'seed': args['seed'],
                if (args.containsKey('sampleSeconds'))
                  'sampleSeconds': args['sampleSeconds'],
                if (args.containsKey('sustainSeconds'))
                  'sustainSeconds': args['sustainSeconds'],
                if (args.containsKey('maxSources'))
                  'maxSources': args['maxSources'],
                if (args.containsKey('repeats'))
                  'repeats': args['repeats'],
              });
        case 'start_live_matrix':
          return await _liveMatrix.start(args,
            open: (id, title, sourceIndex) =>
                _dispatchGithubDiagnostic('open_channel', <String, dynamic>{
                  'channelId': id,
                  'title': title,
                  'sourceIndex': sourceIndex,
                }),
            inspect: () async {
              final handler = GithubDiagnosticControl.instance.onPlayerCommand;
              if (handler == null) {
                return <String, Object?>{'accepted': false,
                    'reason': 'no_active_player'};
              }
              return handler('probe_live', <String, dynamic>{});
            },
            publish: (runId, key, payload) =>
                GithubDiagnosticControl.instance
                    .publishMatrixFile(runId, key, payload),
          );
        case 'state':
          return <String, Object?>{
            'player': LanRemoteService.instance.playerStatus?.call() ??
                <String, Object?>{},
            'routeReady': navigator != null,
          };
        case 'capture_telemetry':
          final uploaded = await IosAudioTelemetry.instance.upload(
              reason: 'manual');
          return <String, Object?>{'uploaded': uploaded};
        case 'remote':
          final key = args['command']?.toString() ?? '';
          final cmd = LanRemoteProtocol.parseCommand(key);
          if (cmd == null) {
            return <String, Object?>{
              'accepted': false, 'reason': 'unknown_remote_action'};
          }
          final handled = LanRemoteService.instance.onPlayerCommand
              ?.call(cmd) ?? false;
          if (!handled) _handleRemoteNavigation(cmd);
          return <String, Object?>{
            'accepted': true, 'handledByPlayer': handled};
        case 'player':
          final name = args['command']?.toString() ?? '';
          if (name.isEmpty) {
            return <String, Object?>{
              'accepted': false, 'reason': 'missing_player_action'};
          }
          final handler = GithubDiagnosticControl.instance.onPlayerCommand;
          if (handler == null) {
            return <String, Object?>{
              'accepted': false, 'reason': 'no_active_player'};
          }
          return await handler(name, args);
        case 'probe_native_channel':
          return await _probeNativeChannel(args);
        case 'probe_addon':
          // Resolve only an installed Stremio TV addon. Never permit a
          // remote command to supply an arbitrary URL or hostname to fetch.
          final channelId = args['channelId']?.toString().trim() ?? '';
          final wantedHost = args['addonHost']?.toString().trim()
              .toLowerCase() ?? '';
          final wantedName = args['addonName']?.toString().trim()
              .toLowerCase() ?? '';
          if (channelId.length < 4 || channelId.length > 180 ||
              !(channelId.startsWith('nltv:') ||
                channelId.startsWith('iptv:'))) {
            return <String, Object?>{
              'accepted': false, 'reason': 'invalid_channel_id'};
          }
          final addons = AddonManager.instance.activeStreamAddons
              .where((addon) =>
                  addon.manifest.supportsRequest('stream', 'tv', channelId))
              .toList();
          final matches = addons.where((addon) {
            final host = Uri.tryParse(addon.baseUrl)?.host.toLowerCase() ?? '';
            return (wantedHost.isEmpty || host == wantedHost) &&
                (wantedName.isEmpty ||
                    addon.manifest.name.toLowerCase() == wantedName);
          }).toList();
          if (matches.isEmpty) {
            return <String, Object?>{
              'accepted': false,
              'reason': 'matching_installed_tv_addon_not_found',
              'availableAddonHosts': addons.map((addon) =>
                  Uri.tryParse(addon.baseUrl)?.host ?? '')
                  .where((host) => host.isNotEmpty)
                  .take(12).toList(),
            };
          }
          final addon = matches.first;
          return await GithubStremioAddonProbe.check(
            baseUrl: addon.baseUrl,
            addonName: addon.manifest.name,
            channelId: channelId,
          );
        case 'open_channel':
          final channelId = args['channelId']?.toString().trim() ?? '';
          final title = args['title']?.toString().trim() ?? channelId;
          if (channelId.length < 4 || channelId.length > 180 ||
              title.isEmpty || title.length > 160 ||
              !(channelId.startsWith('nltv:') ||
                channelId.startsWith('iptv:'))) {
            return <String, Object?>{
              'accepted': false, 'reason': 'invalid_channel_id'};
          }
          final candidates = await StreamService.fetchStreams(
            type: 'tv', id: channelId, title: title,
          ).timeout(const Duration(seconds: 20),
              onTimeout: (sink) => sink.close()).toList();
          if (candidates.isEmpty) {
            return <String, Object?>{
              'accepted': false, 'reason': 'no_channel_streams'};
          }
          final requested = args['sourceIndex'];
          final index = requested is int ? requested : 0;
          if (index < 0 || index >= candidates.length) {
            return <String, Object?>{
              'accepted': false, 'reason': 'invalid_source_index',
              'sourceCount': candidates.length};
          }
          if (navigator == null || !mounted) {
            return <String, Object?>{
              'accepted': false, 'reason': 'navigator_unavailable'};
          }
          navigator.popUntil((route) => route.isFirst);
          navigator.push(MaterialPageRoute(builder: (_) => PlayerScreen(
            source: candidates[index],
            availableSources: candidates,
            title: title,
            detail: MovieDetail(
              id: channelId, type: 'tv', name: title,
              behaviorHints: const <String, dynamic>{'isLive': true},
            ),
          )));
          return <String, Object?>{
            'accepted': true, 'channelTitle': title,
            'sourceCount': candidates.length, 'selectedIndex': index,
            'sourceHost': Uri.tryParse(candidates[index].url ?? '')?.host};
        case 'batch':
          final entries = args['commands'];
          if (entries is! List || entries.isEmpty || entries.length > 20) {
            return <String, Object?>{
              'accepted': false, 'reason': 'invalid_batch'};
          }
          final results = <Map<String, Object?>>[];
          for (final value in entries) {
            if (value is! Map) continue;
            final nested = Map<String, dynamic>.from(value);
            final child = nested['action']?.toString() ?? '';
            if (child == 'batch' || child.isEmpty) continue;
            final rawArgs = nested['args'];
            results.add(await _dispatchGithubDiagnostic(child,
                rawArgs is Map
                    ? Map<String, dynamic>.from(rawArgs)
                    : <String, dynamic>{}));
          }
          return <String, Object?>{
            'accepted': true, 'results': results};
        default:
          return <String, Object?>{
            'accepted': false, 'reason': 'unknown_app_action'};
      }
    } catch (error) {
      debugPrint('[GithubDiagnosticControl] Dispatch: ${error.runtimeType}');
      return <String, Object?>{
        'accepted': false, 'errorClass': error.runtimeType.toString()};
    }
  }

  /// An unattended one-source native iOS decoder test, without changing
  /// the navigator, the active Player, source preferences or local settings.
  /// Never run alongside the foreground Live TV matrix or a visible route.
  Future<Map<String, Object?>> _probeNativeChannel(
      Map<String, dynamic> args) async {
    final request = LiveUnattendedNativeProbeRequest.parse(args);
    if (request == null) {
      return <String, Object?>{
        'accepted': false, 'reason': 'invalid_native_probe_request',
      };
    }

    bool idle() {
      if (!Platform.isIOS || !mounted ||
          _lifecycleState != AppLifecycleState.resumed ||
          _liveMatrix.status()['phase'] == 'running') return false;
      final navigator = navigatorKey.currentState;
      if (navigator == null || navigator.canPop()) return false;
      try {
        final player = LanRemoteService.instance.playerStatus?.call();
        if (player != null && player.isNotEmpty) return false;
      } catch (_) {
        return false;
      }
      return true;
    }

    // Return immediately without starting even a hidden MPV Player if the
    // user is watching, viewing See All or the running matrix owns playback.
    if (!idle()) {
      return <String, Object?>{
        'accepted': false, 'reason': 'device_busy_or_not_foreground',
      };
    }

    try {
      final matches = AddonManager.instance.activeStreamAddons.where((addon) =>
          Uri.tryParse(addon.baseUrl)?.host.toLowerCase() ==
              request.addonHost &&
          addon.manifest.supportsRequest('stream', 'tv', request.channelId))
          .toList();
      if (matches.length != 1) {
        return <String, Object?>{
          'accepted': false,
          'reason': 'exact_installed_addon_not_found',
        };
      }
      final sourceCandidates = await StreamService.fetchLiveStreamsFromAddon(
          matches.single, request.channelId)
          .timeout(const Duration(seconds: 20));
      if (!idle()) {
        return <String, Object?>{
          'accepted': false, 'reason': 'device_became_busy',
        };
      }
      if (request.sourceIndex >= sourceCandidates.length) {
        return <String, Object?>{
          'accepted': false,
          'reason': 'source_index_unavailable',
          'sourceCount': sourceCandidates.length,
        };
      }
      final selected = sourceCandidates[request.sourceIndex];
      UnattendedTestActivity.instance.beginNativeProbe(request.channelId);
      late final LiveNativeSourceResult native;
      try {
        native = await LiveNativeChannelVerifier.probe(
          channelId: request.channelId,
          source: selected,
          isCancelled: () => !idle(),
        );
      } finally {
        UnattendedTestActivity.instance.endNativeProbe();
      }
      // Upload only decoder facts, source host and outcomes. Never export
      // signed URLs, raw media errors, subtitles, headers or tokens.
      return <String, Object?>{
        'accepted': !native.cancelled,
        'reason': native.cancelled ? 'probe_cancelled' : 'completed',
        'channelId': request.channelId,
        'addonHost': request.addonHost,
        'sourceIndex': request.sourceIndex,
        'sourceCount': sourceCandidates.length,
        'sourceHost': Uri.tryParse(selected.url ?? '')?.host,
        'renderedVideo': native.renderedVideo,
        'nativeVerified': native.sustainedStart,
        'timelineAdvanceMs': native.timelineAdvanceMs,
        'buffering': native.buffering,
        'videoWidth': native.videoWidth,
        'videoHeight': native.videoHeight,
        'trackCount': native.trackCount,
        'startupMs': native.startupMs,
      };
    } catch (error) {
      debugPrint('[NativeProbe] Failed: ${error.runtimeType}');
      return <String, Object?>{
        'accepted': false,
        'reason': 'native_probe_unavailable',
        'errorClass': error.runtimeType.toString(),
      };
    }
  }

  /// Paired iPhone handoff supplies *identity*, never a resolved stream URL.
  /// Re-resolve through the iPad's own installed Stremio addons and source
  /// preferences, so the sender cannot redirect playback to an arbitrary URL.
  Future<Map<String, Object?>> _handleLanCastRequest(
      LanCastRequest request) async {
    if (!Platform.isIOS || !mounted ||
        _lifecycleState != AppLifecycleState.resumed) {
      return <String, Object?>{
        'accepted': false, 'reason': 'ipad_not_foreground',
      };
    }
    final navigator = navigatorKey.currentState;
    if (navigator == null) {
      return <String, Object?>{
        'accepted': false, 'reason': 'navigator_unavailable',
      };
    }
    try {
      if (request.type == 'tv') {
        final valid = AddonManager.instance.activeStreamAddons.any((addon) =>
            addon.manifest.supportsRequest(
                'stream', 'tv', request.mediaId));
        if (!valid) {
          return <String, Object?>{
            'accepted': false, 'reason': 'tv_addon_not_installed',
          };
        }
        final sources = await StreamService.fetchStreams(
          type: 'tv', id: request.mediaId, title: request.title,
        ).take(36).toList().timeout(const Duration(seconds: 22));
        final playable = LiveVerifiedSourcePreference.prioritize(
          request.mediaId,
          sources.where(StreamService.isEligibleLiveStreamSource),
        );
        if (playable.isEmpty) {
          return <String, Object?>{
            'accepted': false, 'reason': 'no_direct_live_sources',
          };
        }
        if (!mounted) return {'accepted': false, 'reason': 'not_mounted'};
        navigator.popUntil((route) => route.isFirst);
        navigator.push(MaterialPageRoute<void>(builder: (_) =>
            PlayerScreen(
              source: playable.first,
              availableSources: playable,
              title: request.title,
              detail: MovieDetail(
                id: request.mediaId,
                name: request.title,
                type: 'tv',
                behaviorHints: const <String, dynamic>{'isLive': true},
              ),
            )));
        return <String, Object?>{
          'accepted': true, 'launched': true, 'type': 'tv',
        };
      }

      final metaAddons = AddonManager.instance.activeAddons.where((addon) =>
          addon.manifest.supportsRequest(
              'meta', request.type, request.mediaId)).toList();
      final baseUrl = metaAddons.isNotEmpty
          ? metaAddons.first.baseUrl : 'https://v3-cinemeta.strem.io';
      final resolved = await MetadataService.resolveCatalogMeta(
        baseUrl: baseUrl,
        type: request.type,
        id: request.mediaId,
        title: request.title,
        sourceSupportsMeta: metaAddons.any(
            (addon) => addon.baseUrl == baseUrl),
        compatibleMetaProviders: metaAddons
            .map((addon) => addon.baseUrl).toList(),
      ).timeout(const Duration(seconds: 18));
      final detail = resolved?.detail ?? MetadataService.previewForCatalog(
        Movie(
          id: request.mediaId, type: request.type, name: request.title,
          addonBaseUrl: baseUrl,
        ),
      );
      final isEpisode = request.type == 'series' || request.type == 'anime';
      final episodes = detail.videos;
      final episode = isEpisode ? request.resolveEpisode(episodes) : null;
      if (isEpisode && episode == null) {
        return <String, Object?>{
          'accepted': false, 'reason': 'episode_not_in_verified_metadata',
        };
      }
      final streamId = episode?.id ?? detail.id;
      final sources = await StreamService.fetchStreams(
        type: request.type, id: streamId, title: detail.name,
        year: int.tryParse(detail.year ?? ''),
        season: episode?.season, episode: episode?.episode,
      ).take(100).toList().timeout(const Duration(seconds: 22));
      final profile = WatchSourcePreferencesService.current.value
          .forEpisode(episode != null);
      final eligible = WatchSourceEngine.process(
        sources, profile,
        verified: const <String, bool>{},
        title: detail.name,
        year: int.tryParse(detail.year ?? ''),
        season: episode?.season,
        episode: episode?.episode,
      );
      if (!mounted) return {'accepted': false, 'reason': 'not_mounted'};
      navigator.popUntil((route) => route.isFirst);
      if (eligible.isNotEmpty) {
        navigator.push(MaterialPageRoute<void>(builder: (_) =>
            PlayerScreen(
              source: eligible.first,
              availableSources: eligible,
              title: detail.name,
              detail: detail,
              episode: episode,
            )));
        return <String, Object?>{
          'accepted': true, 'launched': true,
          'type': request.type,
          'episodeId': episode?.id,
        };
      }
      // Honor cached-only/source-language preferences. Never silently
      // play an unverified or disallowed source; show the normal chooser.
      navigator.push(MaterialPageRoute<void>(builder: (_) =>
          WatchScreen(
            detail: detail,
            type: request.type,
            selectedEpisode: episode,
          )));
      return <String, Object?>{
        'accepted': true, 'launched': false,
        'sourceSelectionRequired': true,
      };
    } catch (error) {
      debugPrint('[LAN Cast] Media handoff failed: ${error.runtimeType}');
      return <String, Object?>{
        'accepted': false, 'reason': 'media_resolution_failed',
      };
    }
  }

  /// Route remote commands through Flutter's native focus and activation
  /// actions, so the same controls work for local taps and the iPhone remote.
  void _handleRemoteNavigation(LanRemoteCommand command) {
    if (!mounted || !Platform.isIOS) return;
    final navigator = navigatorKey.currentState;
    final context = navigator?.context;
    if (navigator == null || context == null) return;
    try {
      switch (command) {
        case LanRemoteCommand.back:
          if (navigator.canPop()) navigator.pop();
          return;
        case LanRemoteCommand.home:
          navigator.popUntil((route) => route.isFirst);
          return;
        case LanRemoteCommand.select:
          final node = FocusManager.instance.primaryFocus;
          final focusedContext = node?.context;
          if (focusedContext == null) {
            FocusScope.of(context).nextFocus();
            return;
          }
          if (focusedContext.widget is EditableText) return;
          if (Actions.maybeFind<ActivateIntent>(focusedContext) != null) {
            Actions.invoke(focusedContext, const ActivateIntent());
          } else if (Actions.maybeFind<ButtonActivateIntent>(
              focusedContext) != null) {
            Actions.invoke(focusedContext, const ButtonActivateIntent());
          }
          return;
        case LanRemoteCommand.up:
        case LanRemoteCommand.down:
        case LanRemoteCommand.left:
        case LanRemoteCommand.right:
          final current = FocusManager.instance.primaryFocus;
          if (current == null || current is FocusScopeNode ||
              current == FocusManager.instance.rootScope) {
            FocusScope.of(context).nextFocus();
          } else {
            final direction = switch (command) {
              LanRemoteCommand.up => TraversalDirection.up,
              LanRemoteCommand.down => TraversalDirection.down,
              LanRemoteCommand.left => TraversalDirection.left,
              _ => TraversalDirection.right,
            };
            final moved = current.focusInDirection(direction);
            if (!moved) {
              if (direction == TraversalDirection.right ||
                  direction == TraversalDirection.down) {
                current.nextFocus();
              } else {
                current.previousFocus();
              }
            }
          }
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final focusedContext =
                FocusManager.instance.primaryFocus?.context;
            if (focusedContext != null && focusedContext.mounted) {
              unawaited(Scrollable.ensureVisible(
                focusedContext,
                duration: const Duration(milliseconds: 180),
                alignment: 0.2,
              ));
            }
          });
          return;
        case LanRemoteCommand.playPause:
        case LanRemoteCommand.seekBack:
        case LanRemoteCommand.seekForward:
          // Playback commands are consumed by PlayerScreen while it is active.
          return;
      }
    } catch (error) {
      debugPrint('[LAN Remote] Navigation action failed: $error');
    }
  }

  Future<void> _checkForUpdates() async {
    if (_isShowingUpdateDialog) return;
    _lastUpdateCheckAt = DateTime.now();
    try {
      final updater = AppUpdaterService();
      final updateInfo = await updater.checkForUpdates();
      if (updateInfo == null) return;

      BuildContext? context = navigatorKey.currentContext;
      for (int i = 0; i < 6 && (context == null || !context.mounted); i++) {
        await Future.delayed(const Duration(milliseconds: 500));
        context = navigatorKey.currentContext;
      }

      if (context != null && context.mounted && !_isShowingUpdateDialog) {
        _isShowingUpdateDialog = true;
        await showDialog(
          context: context,
          barrierDismissible: true,
          builder: (context) => UpdateDialog(updateInfo: updateInfo),
        );
        _isShowingUpdateDialog = false;
      }
    } catch (e) {
      _isShowingUpdateDialog = false;
      debugPrint('Error checking for app updates: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppThemePalette>(
      valueListenable: AppThemeService.currentPalette,
      builder: (context, palette, _) {
        return MaterialApp(
          navigatorKey: navigatorKey,
          navigatorObservers: <NavigatorObserver>[
            IosRemoteAppObservability.instance.routes,
          ],
          title: 'PlayTorrio',
          debugShowCheckedModeBanner: false,
          theme: AppThemeService.createThemeData(palette),
          scrollBehavior: const MaterialScrollBehavior().copyWith(
            overscroll: false,
          ),
          builder: (context, child) => RepaintBoundary(
            key: IosRemoteAppObservability.instance.captureKey,
            child: Stack(
              fit: StackFit.expand,
              children: [
                child ?? const SizedBox.shrink(),
                if (Platform.isIOS)
                  Positioned(top: 0, left: 0, right: 0,
                    child: UnattendedTestIndicator(
                      activity: UnattendedTestActivity.instance.snapshot,
                      onDismiss: () => UnattendedTestActivity.instance
                          .setIndicatorEnabled(false))),
              ],
            ),
          ),
          home: const HomePage(),
        );
      },
    );
  }
}

