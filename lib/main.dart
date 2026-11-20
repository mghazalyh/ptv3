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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    LanRemoteService.instance.onNavigationCommand = _handleRemoteNavigation;
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
    // Receiver sockets close when the application is disposed.
    unawaited(LanRemoteService.instance.stopHosting());
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
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

