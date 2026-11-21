import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:media_kit/media_kit.dart';

import 'package:window_manager/window_manager.dart';

import './pages/home/home_page.dart';
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
import './services/remote/github_diagnostic_control.dart';
import './services/remote/github_stremio_addon_probe.dart';
import './services/player/live_tv/live_tv_experiment_policy.dart';
import './services/player/live_tv/live_tv_matrix_runner.dart';
import './services/stream/stream_service.dart';
import './services/metadata/metadata_service.dart';
import './models/movie/movie_detail.dart';
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
  final LiveTvMatrixRunner _liveMatrix = LiveTvMatrixRunner();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    LanRemoteService.instance.onNavigationCommand = _handleRemoteNavigation;
    if (Platform.isIOS) {
      GithubDiagnosticControl.instance.onCommand = _dispatchGithubDiagnostic;
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
    if (Platform.isIOS) GithubDiagnosticControl.instance.onCommand = null;
    // Receiver sockets close when the application is disposed.
    unawaited(LanRemoteService.instance.stopHosting());
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }


  /// Discover only real TV channels published by enabled, installed Stremio
  /// addons. No command-supplied URL or arbitrary host is ever fetched.
  Future<Map<String, Object?>> _discoverLiveChannels(
      Map<String, dynamic> args) async {
    final wantedHost = args['addonHost']?.toString().toLowerCase() ?? '';
    final pages = (args['pages'] is int ? args['pages'] as int : 3)
        .clamp(1, 6).toInt();
    final limit = (args['limit'] is int ? args['limit'] as int : 100)
        .clamp(50, 150).toInt();
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
    if (!found.containsKey(control) && found.isNotEmpty &&
        AddonManager.instance.activeStreamAddons.any((addon) =>
            addon.manifest.supportsRequest('stream', 'tv', control))) {
      if (found.length >= limit) found.remove(found.keys.last);
      found[control] = 'Cine Romántico';
    }
    return <String, Object?>{
      'accepted': found.isNotEmpty,
      'count': found.length,
      'catalogsChecked': catalogCount,
      'installedAddonHosts': usedHosts.toList(),
      'channels': found.entries.map((entry) => <String, String>{
        'id': entry.key, 'title': entry.value,
      }).toList(),
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
          final discovered = await _discoverLiveChannels(args);
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
          title: 'PlayTorrio',
          debugShowCheckedModeBanner: false,
          theme: AppThemeService.createThemeData(palette),
          scrollBehavior: const MaterialScrollBehavior().copyWith(
            overscroll: false,
          ),
          home: const HomePage(),
        );
      },
    );
  }
}

