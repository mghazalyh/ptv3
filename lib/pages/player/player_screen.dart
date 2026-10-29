import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart' as mk;
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';

import 'package:playtorrio/models/movie/video.dart';
import 'package:playtorrio/models/movie/movie_detail.dart';
import 'package:playtorrio/models/subtitle/subtitle_model.dart';
import 'package:playtorrio/services/subtitles/subtitle_service.dart';
import 'package:playtorrio/services/subtitles/subtitle_parser.dart';

import '../../models/stream/stream_model.dart';
import '../../services/continue_watching/continue_watching_service.dart';
import '../../services/continue_watching/watched_history_service.dart';
import '../../services/debrid/debrid_service.dart';
import '../../services/p2p/p2p_settings_service.dart';
import '../../services/stream/torrent_stream_service.dart';
import '../../services/theme/glass_settings.dart';
import '../../services/trakt/trakt_service.dart';
import '../../services/simkl/simkl_service.dart';
import '../../services/player/player_settings.dart';
import '../../services/player/audio_language_priority.dart';
import '../../services/player/playback_autoselection.dart';
import '../../services/player/ios_speech_transcriber.dart';
import '../../services/player/speech_subtitle_alignment.dart';
import '../../services/player/paused_http_recovery.dart';
import '../../services/player/automatic_skip_policy.dart';
import '../../services/player/playback_diagnostics_probe.dart';
import '../../services/metadata/metadata_service.dart';
import '../../services/stream/stream_service.dart';
import '../../services/discord/discord_rpc_service.dart';

import '../../widgets/player/player_glass.dart';
import '../../widgets/player/player_top_bar.dart';
import '../../widgets/player/player_transport.dart';
import '../../widgets/player/player_speed_menu.dart';
import '../../services/window/window_service.dart';
import '../../models/player/skip_segment_model.dart';
import '../../services/player/skip_segments_service.dart';
import '../../widgets/player/player_aspect_menu.dart';
import '../../widgets/player/player_audio_menu.dart';
import '../../widgets/player/player_subtitle_menu.dart';
import '../../widgets/player/player_sub_style_modal.dart';
import '../../widgets/player/player_skip_button.dart';
import '../../widgets/player/player_diagnostics_overlay.dart';
import '../../widgets/player/player_episodes_panel.dart';
import '../../widgets/player/player_sources_panel.dart';
import '../../widgets/player/player_volume_control.dart';
import '../../widgets/player/sub_sync_bar.dart';
import '../../widgets/player/text_sync_overlay.dart';
import '../../models/download/download_task_model.dart';
import '../../services/download/download_service.dart';
import '../../utils/download/download_path_helper.dart';
import '../../utils/navigation/media_details_navigation.dart';

class PlayerScreen extends StatefulWidget {
  final StreamSource source;
  final String title;
  final String? backdropUrl;
  final String? logoUrl;
  final MovieDetail? detail;
  final Video? episode;
  final Duration? initialPosition;

  const PlayerScreen({
    super.key,
    required this.source,
    required this.title,
    this.backdropUrl,
    this.logoUrl,
    this.detail,
    this.episode,
    this.initialPosition,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen>
    with SingleTickerProviderStateMixin {
  late final Player _player = Player(configuration: PlayerSettings.getMediaKitPlayerConfiguration());
  late final mk.VideoController _videoController = mk.VideoController(
    _player,
    configuration: PlayerSettings.getVideoControllerConfiguration(),
  );
  final List<StreamSubscription> _subscriptions = [];

  final ValueNotifier<Duration> _positionNotifier = ValueNotifier<Duration>(Duration.zero);
  final ValueNotifier<Duration?> _bufferNotifier = ValueNotifier<Duration?>(null);

  bool _isLoading = true;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration? _buffered;
  bool _wasBuffering = false;
  String _statusMessage = 'Initializing...';
  bool _showControls = true;
  bool _isHoveringUI = false;
  Timer? _hideTimer;
  Timer? _progressSaveTimer;
  DateTime? _lastPointerTimerReset;
  late AnimationController _logoAnimController;

  // Active Menu / Popover
  String? _activeMenu; // 'subtitle' | 'audio' | 'speed' | 'aspect' | 'style' | null
  bool _showSubSyncBar = false;
  bool _showTextSyncOverlay = false;

  // Read-only playback diagnostics. Never poll player properties while hidden.
  bool _showDiagnostics = false;
  bool _diagnosticsReading = false;
  int _diagnosticsRevision = 0;
  Timer? _diagnosticsTimer;
  Map<String, String> _diagnosticsProperties = {};

  // Playback & Audio State
  double _volume = 1.0;
  double _lastVolumeBeforeMute = 1.0;
  bool _isMuted = false;
  bool _showVolumeHud = false;
  Timer? _volumeHudTimer;
  double _playbackRate = 1.0;
  BoxFit _videoFit = BoxFit.contain;
  List<PlayerAudioTrack> _audioTracks = [];
  int _selectedAudioTrackIndex = 0;
  bool _audioManuallySelected = false;
  bool _audioAutoSelectionPending = false;
  bool _nativeAudioProbeRunning = false;
  int _audioMediaEpoch = 0;
  double _audioDelaySec = 0.0;
  bool _showAudioHud = false;
  String _audioHudText = '';
  Timer? _audioHudTimer;

  // Subtitle State
  List<SubtitleLanguageGroup> _subtitleGroups = [];
  List<PlayerEmbeddedSubtitle> _embeddedSubtitles = [];
  int? _selectedEmbeddedSubtitleIndex;
  SubtitleVariant? _currentSubtitleVariant;
  bool _isSubtitleEnabled = false;
  String? _currentSubtitlePath;
  List<SubCue> _currentCues = [];
  SubFormat _currentSubFormat = SubFormat.srt;
  double _subtitleDelayMs = 0;
  double _subtitleScale = 1.0;
  bool _subtitleManuallySelected = false;
  bool _subtitleAutoPending = false;
  bool _autoSyncBusy = false;
  String? _speechMediaUrl; // Active playable media; never logged or persisted.
  Map<String, String>? _speechMediaHeaders; // Same header set as the mpv movie player.
  bool _nextEpisodeBusy = false;
  List<Video> _episodeCatalog = const [];
  bool _episodeCatalogComplete = false;
  int _lastAutoplayEpoch = -1;

  // Skip Segments State (IntroDB)
  List<MediaSkipSegment> _skipSegments = [];
  MediaSkipSegment? _activeSkipSegment;
  bool _showSkipButton = false;
  final Set<String> _dismissedSegmentKeys = {};
  int _skipMediaEpoch = 0;

  // Episodes & Sources Side Panels State
  late StreamSource _currentSource;
  Video? _currentEpisode;
  late String _currentTitle;
  bool _showEpisodesPanel = false;
  bool _showSourcesPanel = false;
  Video? _sourcesEpisode;
  String? _sourcesErrorMessage;
  final Map<String, List<StreamSource>> _cachedSourcesByEpisode = {};
  String? _httpVodUrl;
  Map<String, String>? _httpVodHeaders;
  DateTime? _httpPausedAt;
  DateTime? _httpResumedAt;
  bool _httpReconnecting = false;
  int _httpReconnectAttempts = 0;
  int _streamGeneration = 0;

  @override
  void initState() {
    super.initState();
    _currentSource = widget.source;
    _currentEpisode = widget.episode;
    _currentTitle = widget.title;
    _episodeCatalog = widget.detail?.videos ?? const <Video>[];
    if (_currentEpisode != null && _episodeCatalog.length < 4) {
      unawaited(_fetchEpisodeCatalog());
    }

    WakelockPlus.enable();
    _logoAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    PlayerSettings.changeNotifier.addListener(_onPlayerSettingsChanged);

    _subscriptions.addAll([
      _player.stream.playing.listen((playing) {
        if (mounted) {
          final justPaused = _isPlaying && !playing;
          final justResumed = !_isPlaying && playing;
          if (justPaused && !_httpReconnecting && !_player.state.buffering) {
            _httpPausedAt ??= DateTime.now();
          }
          if (justResumed && !_httpReconnecting) {
            _httpResumedAt = DateTime.now();
            _httpPausedAt = null;
          }
          setState(() => _isPlaying = playing);
          _updateDiscordRpc(isPaused: !playing);
          if (justPaused && !_httpReconnecting && !_player.state.buffering) {
            _saveAndSyncLastPosition();
          }
        }
      }),
      _player.stream.position.listen((pos) {
        _position = pos;
        _positionNotifier.value = pos;
        // A full minute of healthy playback restores future recovery budget.
        if (!_httpReconnecting && _httpResumedAt != null &&
            _player.state.playing &&
            DateTime.now().difference(_httpResumedAt!) >=
                const Duration(seconds: 60)) {
          _httpReconnectAttempts = 0;
          _httpResumedAt = null;
        }
        _onPlaybackTick(pos);
      }),
      _player.stream.duration.listen((dur) {
        if (mounted) {
          setState(() => _duration = dur);
          _updateDiscordRpc();
        }
      }),
      _player.stream.buffer.listen((buf) {
        _buffered = buf;
        _bufferNotifier.value = buf;
      }),
      _player.stream.buffering.listen((isBuffering) {
        if (_wasBuffering && !isBuffering && PlayerSettings.autoResyncOnStall.value) {
          try {
            if (PlayerSettings.hardwareAudioClock.value) {
              final np = _player.platform as dynamic;
              np.setProperty('video-sync', 'audio');
            }
          } catch (_) {}
        }
        _wasBuffering = isBuffering;
      }),
      _player.stream.tracks.listen((tracks) {
        _updateMediaTracks(tracks);
      }),
      _player.stream.track.listen((track) {
        if (!mounted) return;
        final aid = track.audio.id;
        final idx = int.tryParse(aid);
        if (idx != null && _selectedAudioTrackIndex != idx) {
          setState(() => _selectedAudioTrackIndex = idx);
        }
      }),
      _player.stream.error.listen((error) {
        _onControllerError(error);
      }),
      _player.stream.completed.listen((completed) {
        if (completed && mounted && !_isLoading) {
          _savePlaybackProgress();
          if (_lastAutoplayEpoch != _audioMediaEpoch) {
            _lastAutoplayEpoch = _audioMediaEpoch;
            unawaited(_goToNextEpisode());
          }
        }
      }),
    ]);

    _initStream();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  Future<void> _initStream() async {
    ++_streamGeneration;
    ++_diagnosticsRevision;
    _diagnosticsProperties = {};
    ++_skipMediaEpoch;
    _httpVodUrl = null;
    _httpVodHeaders = null;
    _speechMediaUrl = null;
    _speechMediaHeaders = null;
    _httpPausedAt = null;
    _httpResumedAt = null;
    _httpReconnectAttempts = 0;
    final audioEpoch = ++_audioMediaEpoch;
    _audioManuallySelected = false;
    _audioAutoSelectionPending = false;
    _audioTracks = [];
    _selectedAudioTrackIndex = 0;
    // Never carry stale subtitle tracks or download results into another episode.
    _subtitleManuallySelected = false;
    _subtitleAutoPending = false;
    _isSubtitleEnabled = false;
    _currentSubtitleVariant = null;
    _selectedEmbeddedSubtitleIndex = null;
    _currentSubtitlePath = null;
    _embeddedSubtitles = [];
    _currentCues = [];
    _subtitleDelayMs = 0.0; // Do not leak speech alignment into the next episode.
    String? streamUrl;

    print('[PlayerScreen] Initializing playback:');
    print('[PlayerScreen]   Title: $_currentTitle');
    print('[PlayerScreen]   Source Name: ${_currentSource.name}');
    print('[PlayerScreen]   Addon Name: ${_currentSource.addonName}');
    print('[PlayerScreen]   Source Title: ${_currentSource.title}');
    print('[PlayerScreen]   Raw URL: ${_currentSource.url}');

    try {
      final rawUrl = _currentSource.url;

      // Handle offline downloaded file playback directly
      if (rawUrl != null && (File(rawUrl).existsSync() || _currentSource.name == 'Downloaded')) {
        _speechMediaUrl = rawUrl;
        print('[PlayerScreen] Initializing offline local file playback.');
        await PlayerSettings.applyPreOpenProperties(_player);
        await _player.open(Media(rawUrl), play: true);
        await _applyLiveDelay(0.0);
        await PlayerSettings.applyPostOpenProperties(_player);
        _setSubtitleScale(_subtitleScale);
        _applyVolume(_isMuted ? 0.0 : _volume);
        if (mounted) setState(() => _isLoading = false);
        _updateMediaTracks(_player.state.tracks);
        _scheduleAudioProbes(audioEpoch);
        _preferEnglishAudioTrack();
        unawaited(_fetchSkipSegments());
        unawaited(_fetchInitialSubtitles());
        return;
      }

      final infoHash = _currentSource.infoHash;
      final isMagnetUrl = rawUrl != null && rawUrl.startsWith('magnet:');
      // Torrentio + TorBox returns direct HTTP links. Always prefer a usable
      // direct URL over an optional infoHash, which is just source metadata.
      final hasDirectHttpUrl = rawUrl != null &&
          (rawUrl.startsWith('https://') || rawUrl.startsWith('http://'));
      final isTorrent = !hasDirectHttpUrl &&
          ((infoHash != null && infoHash.isNotEmpty) || isMagnetUrl);

      if (isTorrent) {
        String magnet;
        if (isMagnetUrl) {
          magnet = rawUrl;
        } else {
          magnet = 'magnet:?xt=urn:btih:$infoHash';
          if (_currentSource.sources != null) {
            for (final source in _currentSource.sources!) {
              if (source.startsWith('tracker:')) {
                final trackerUrl = source.replaceFirst('tracker:', '');
                magnet += '&tr=${Uri.encodeComponent(trackerUrl)}';
              }
            }
          }
        }

        final useDebrid = await DebridService().isDebridActiveForStreams();
        if (useDebrid) {
          final activeService = await DebridService().getSelectedService();
          if (!mounted) return;
          setState(() => _statusMessage = 'Using $activeService for files...');

          final seasonNum = _currentEpisode?.season;
          final episodeNum = _currentEpisode?.episode;

          final debridFiles = await DebridService().resolveMagnet(
            magnet: magnet,
            fileIndex: _currentSource.fileIdx,
            filename: _currentTitle,
            season: seasonNum,
            episode: episodeNum,
          );

          if (debridFiles.isEmpty || debridFiles.first.downloadUrl.isEmpty) {
            throw Exception('$activeService returned no direct stream links.');
          }

          streamUrl = debridFiles.first.downloadUrl;
          print('[PlayerScreen] Debrid resolved stream URL: $streamUrl');
        } else {
          // Do not silently start local P2P when the user disabled the
          // built-in source. This does not affect Torrentio/TorBox HTTP URLs.
          if (!P2pSettingsService.isP2pEnabled.value) {
            throw StateError(
              'P2P is disabled. Choose a direct TorBox streaming link '
              'or enable a debrid provider for magnet-only streams.',
            );
          }
          if (!mounted) return;
          setState(() => _statusMessage = 'Gathering metadata & peers...');

          streamUrl = await TorrentStreamService().streamTorrent(
            magnet,
            fileIdx: _currentSource.fileIdx,
          );
        }
      } else if (rawUrl != null && rawUrl.isNotEmpty) {
        streamUrl = rawUrl;
      } else {
        throw Exception('No valid stream source found.');
      }

      if (streamUrl == null) throw Exception('Stream URL is null');

      final sanitizedUrlStr = streamUrl.contains('::')
          ? streamUrl.replaceAll('::', '%3A%3A')
          : streamUrl;

      // Automatically resolve complete CDN headers (Referer, Origin, User-Agent)
      final playerHeaders = PlayerSettings.resolveStreamHeaders(
        sanitizedUrlStr,
        _currentSource.headers,
      );

      // Also merge any proxyHeaders from behaviorHints if present
      final proxyReqHeaders = _currentSource.behaviorHints?['proxyHeaders']?['request'];
      if (proxyReqHeaders is Map) {
        playerHeaders.addAll(Map<String, String>.from(proxyReqHeaders));
      }

      final cleanUri = Uri.parse(sanitizedUrlStr);
      _speechMediaUrl = cleanUri.toString();
      print('[PlayerScreen] Opening direct network stream URL: $cleanUri (headers: ${playerHeaders.keys})');

      if (!mounted) return;
      final epLabel = _currentEpisode != null
          ? 'S${_currentEpisode!.season ?? 1}:E${_currentEpisode!.episode ?? 1} - ${_currentEpisode!.title.isNotEmpty ? _currentEpisode!.title : "Episode ${_currentEpisode!.episode ?? 1}"}'
          : (widget.detail?.name ?? _currentTitle);
      setState(() => _statusMessage = 'Buffering $epLabel...');

      final lowerClean = sanitizedUrlStr.toLowerCase();
      final bool isLive = _currentSource.behaviorHints?['isLive'] == true ||
          _currentSource.addonName.toLowerCase() == 'iptv' ||
          _currentSource.name?.toLowerCase() == 'iptv' ||
          lowerClean.contains('/live/') ||
          lowerClean.contains('/hls/live');

      final bool isTorrentStream = !hasDirectHttpUrl && (isTorrent ||
          sanitizedUrlStr.contains(':8090') ||
          sanitizedUrlStr.contains('/stream?link=') ||
          sanitizedUrlStr.contains('/stream?'));

      _speechMediaHeaders = isTorrentStream
          ? null
          : Map<String, String>.from(playerHeaders);
      await PlayerSettings.applyPreOpenProperties(_player, isLive: isLive, isTorrent: isTorrentStream);

      // Set native MPV properties for referer and user-agent directly on the player for web streams
      if (!isTorrentStream) {
        try {
          final dynamic platform = _player.platform;
          if (platform != null) {
            final referer = playerHeaders['Referer'] ?? playerHeaders['referer'];
            if (referer != null && referer.isNotEmpty) {
              await platform.setProperty('referrer', referer);
            }
            final ua = playerHeaders['User-Agent'] ?? playerHeaders['user-agent'];
            if (ua != null && ua.isNotEmpty) {
              await platform.setProperty('user-agent', ua);
            }
          }
        } catch (e) {
          print('[PlayerScreen] Warning setting native header properties: $e');
        }
      }

      // Save direct on-demand HTTP details for a stale-socket reopen.
      // Local files, IPTV/live and local P2P are not eligible.
      if (hasDirectHttpUrl && !isTorrentStream && !isLive) {
        _httpVodUrl = cleanUri.toString();
        _httpVodHeaders = Map<String, String>.from(playerHeaders);
      }
      await _player.open(
        Media(
          cleanUri.toString(),
          httpHeaders: isTorrentStream ? null : playerHeaders,
          start: identical(_currentEpisode, widget.episode)
              ? widget.initialPosition : null,
        ),
        play: true,
      );

      await _applyLiveDelay(0.0);
      await PlayerSettings.applyPostOpenProperties(_player);

      _setSubtitleScale(_subtitleScale);
      _applyVolume(_isMuted ? 0.0 : _volume);

      print('[PlayerScreen SUCCESS] Player opened media successfully for $streamUrl');

      _updateMediaTracks(_player.state.tracks);
      _scheduleAudioProbes(audioEpoch);

      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });

      _player.play();
      _preferEnglishAudioTrack();
      unawaited(_autoEnableEnglishEmbedded(audioEpoch));
      _startHideControlsTimer();

      // Defer background services until after playback starts
      Future.microtask(() {
        if (!mounted) return;
        _fetchSkipSegments();
        _fetchInitialSubtitles();

        final detail = widget.detail;
        if (detail != null) {
          final targetId = detail.id.startsWith('tt') ? detail.id : (detail.tmdbId ?? detail.id);
          if (targetId.isNotEmpty) {
            final s = _currentEpisode?.season;
            final e = _currentEpisode?.episode;
            final initPos = widget.initialPosition?.inSeconds ?? 0;
            final dur = _player.state.duration.inSeconds;
            final progress = (dur > 0 ? (initPos / dur) * 100.0 : 0.0).clamp(0.0, 100.0);

            TraktService.instance.isAuthenticated().then((authed) {
              if (authed) {
                TraktService.instance.scrobbleStart(targetId, progress, season: s, episode: e);
              }
            });
            SimklService.instance.isAuthenticated().then((authed) {
              if (authed) {
                SimklService.instance.scrobbleStart(targetId, progress, season: s, episode: e);
              }
            });
          }
        }
      });

      _progressSaveTimer?.cancel();
      _progressSaveTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        _savePlaybackProgress();
      });
    } catch (e, stackTrace) {
      print('[PlayerScreen ERROR] Failed to initialize stream URL: "$streamUrl"');
      print('[PlayerScreen ERROR] Exception: $e');
      print('[PlayerScreen ERROR] StackTrace:\n$stackTrace');

      if (!mounted) return;

      // If we have an episode context (TV show), reopen the sources panel with error notice!
      if (_currentEpisode != null && widget.detail?.videos.isNotEmpty == true) {
        setState(() {
          _isLoading = false;
          _showSourcesPanel = true;
          _sourcesEpisode = _currentEpisode;
          _sourcesErrorMessage = 'Source failed to play. Please select another source below.';
        });
        return;
      }

      String displayMessage = 'Error: $e';
      if (e is PlatformException &&
          (e.message?.contains('invalid or unsupported media') ?? false)) {
        displayMessage =
            'Media Open Error: Stream server quota exceeded or invalid media format.\nPlease select another stream.';
      }

      setState(() {
        _statusMessage = displayMessage;
      });
    }
  }

  void _updateMediaTracks(Tracks tracks) {
    if (!mounted) return;
    final audioList = tracks.audio;
    final audioTracks = <PlayerAudioTrack>[];
    for (int i = 0; i < audioList.length; i++) {
      final t = audioList[i];
      if (t.id == 'no' || t.id == 'auto') continue;
      final lang = t.language;
      final title = t.title ?? (lang != null ? lang.toUpperCase() : 'Track ${i + 1}');
      final idx = int.tryParse(t.id);
      if (idx == null || idx <= 0) continue;
      audioTracks.add(PlayerAudioTrack(
        index: idx,
        title: title,
        language: lang,
        channels: int.tryParse(t.channels?.toString() ?? ''),
      ));
    }

    final subList = tracks.subtitle;
    final embeddedSubs = <PlayerEmbeddedSubtitle>[];
    for (int i = 0; i < subList.length; i++) {
      final t = subList[i];
      if (t.id == 'no' || t.id == 'auto') continue;
      final lang = t.language;
      final title = t.title ?? (lang != null ? lang.toUpperCase() : 'Track ${i + 1}');
      final idx = int.tryParse(t.id) ?? (i + 1);
      embeddedSubs.add(PlayerEmbeddedSubtitle(
        index: idx,
        title: title,
        language: lang,
      ));
    }

    // media_kit's tracks stream may temporarily omit audio streams on iOS.
    // Preserve the fuller MPV-native list until the next video is opened.
    final bestTracks = audioTracks.length >= _audioTracks.length
        ? audioTracks
        : List<PlayerAudioTrack>.from(_audioTracks);
    bestTracks.sort((a, b) {
      final englishA = AudioLanguagePriority.isEnglish(
          language: a.language, title: a.title) ? 0 : 1;
      final englishB = AudioLanguagePriority.isEnglish(
          language: b.language, title: b.title) ? 0 : 1;
      return englishA.compareTo(englishB);
    });
    final active = int.tryParse(_player.state.track.audio.id);
    setState(() {
      _audioTracks = bestTracks;
      _embeddedSubtitles = embeddedSubs;
      if (active != null && active > 0) _selectedAudioTrackIndex = active;
    });
    _preferEnglishAudioTrack();
    if (!_isLoading) unawaited(_autoEnableEnglishEmbedded(_audioMediaEpoch));
  }

  void _preferEnglishAudioTrack() {
    if (!mounted || _isLoading || _audioManuallySelected ||
        _audioAutoSelectionPending) {
      return;
    }
    final english = _audioTracks.where((track) =>
        AudioLanguagePriority.isEnglish(
          language: track.language, title: track.title,
        )).firstOrNull;
    if (english == null || english.index == _selectedAudioTrackIndex) return;
    _audioAutoSelectionPending = true;
    unawaited(_selectAudioTrack(english.index, manual: false).whenComplete(() {
      _audioAutoSelectionPending = false;
    }));
  }

  Future<void> _selectAudioTrack(int index, {required bool manual}) async {
    if (manual) _audioManuallySelected = true;
    final epoch = _audioMediaEpoch;
    try {
      final matching = _player.state.tracks.audio.where(
        (track) => track.id == index.toString(),
      ).firstOrNull;
      final dynamic native = _player.platform;
      var switched = false;
      if (matching != null) {
        try {
          await _player.setAudioTrack(matching);
          switched = true;
        } catch (error) {
          debugPrint('[PlayerAudio] media_kit switch failed, trying MPV: $error');
        }
      }
      if (!switched) {
        await native.setProperty('aid', index.toString());
      } else {
        // Verify selected MPV track where supported; correct stale wrapper
        // state by setting MPV's actual numeric stream ID directly.
        try {
          final reported = await native.getProperty('aid');
          final active = int.tryParse(reported?.toString() ?? '');
          if (active != null && active != index) {
            await native.setProperty('aid', index.toString());
          }
        } catch (error) {
          debugPrint('[PlayerAudio] MPV verification unavailable: $error');
        }
      }
      if (!mounted || epoch != _audioMediaEpoch) return;
      setState(() => _selectedAudioTrackIndex = index);
      debugPrint('[PlayerAudio] Audio track selected: $index (manual=$manual)');
      if (manual) {
        final selected = _audioTracks.where((t) => t.index == index).firstOrNull;
        _showAudioHudToast(selected?.title ?? 'Audio track $index');
      }
    } catch (error, stack) {
      debugPrint('[PlayerAudio] Cannot switch audio track $index: $error\\n$stack');
      if (manual && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('This stream did not allow audio track switching.'),
        ));
      }
    }
  }

  void _scheduleAudioProbes(int epoch) {
    // Torrentio debrid streams can expose audio metadata after media open.
    for (final delay in <Duration>[
      const Duration(milliseconds: 600),
      const Duration(seconds: 2),
      const Duration(seconds: 5),
    ]) {
      Future.delayed(delay, () {
        if (mounted && epoch == _audioMediaEpoch) {
          unawaited(_refreshNativeAudioTracks(epoch));
        }
      });
    }
  }

  Future<void> _refreshNativeAudioTracks(int epoch) async {
    if (_nativeAudioProbeRunning || !mounted || epoch != _audioMediaEpoch) return;
    _nativeAudioProbeRunning = true;
    try {
      final dynamic native = _player.platform;
      final countValue = await native.getProperty('track-list/count');
      final count = int.tryParse(countValue?.toString() ?? '') ?? 0;
      if (count <= 0 || count > 120) return;
      final found = <PlayerAudioTrack>[];
      for (var i = 0; i < count; i++) {
        final type = await native.getProperty('track-list/$i/type');
        if (type?.toString() != 'audio') continue;
        final id = await native.getProperty('track-list/$i/id');
        final numericId = int.tryParse(id?.toString() ?? '');
        if (numericId == null || numericId <= 0) continue;
        final language = (await native.getProperty('track-list/$i/lang'))
            ?.toString();
        final title = (await native.getProperty('track-list/$i/title'))
            ?.toString();
        found.add(PlayerAudioTrack(
          index: numericId,
          title: title != null && title.trim().isNotEmpty
              ? title : (language != null && language.isNotEmpty
                  ? language.toUpperCase() : 'Audio track $numericId'),
          language: language,
        ));
      }
      if (!mounted || epoch != _audioMediaEpoch) return;
      if (found.length >= _audioTracks.length ||
          (found.any((t) => AudioLanguagePriority.isEnglish(
                  language: t.language, title: t.title)) &&
              !_audioTracks.any((t) => AudioLanguagePriority.isEnglish(
                  language: t.language, title: t.title)))) {
        found.sort((a, b) {
          final ea = AudioLanguagePriority.isEnglish(
            language: a.language, title: a.title) ? 0 : 1;
          final eb = AudioLanguagePriority.isEnglish(
            language: b.language, title: b.title) ? 0 : 1;
          return ea.compareTo(eb);
        });
        setState(() => _audioTracks = found);
        debugPrint('[PlayerAudio] MPV exposed ${found.length} audio tracks');
      }
      _preferEnglishAudioTrack();
    } catch (error) {
      // Older native player builds may not expose this method. Use the
      // media_kit track stream and MPV alang preference as the fallback.
      debugPrint('[PlayerAudio] Native track inspection unavailable: $error');
    } finally {
      _nativeAudioProbeRunning = false;
    }
  }

  static String cleanMediaTitle(String raw) {
    var name = raw;
    name = name.replaceAll(RegExp(r'\.(mkv|mp4|avi|webm|ts|mov|m4v|srt|vtt)$', caseSensitive: false), '');
    name = name.replaceAll(RegExp(r'[._]'), ' ');
    name = name.replaceAll(RegExp(r'\b(2160p|1080p|720p|480p|4k|uhd|ds4k|webrip|web-dl|bluray|brrip|h264|x264|h265|x265|hevc|10bit|ddp5\.1|dd5\.1|atmos|aac|ac3|dts|flac|remux|hdr|dv|proper|repack|hdtv)\b', caseSensitive: false), ' ');
    name = name.replaceAll(RegExp(r'-[a-zA-Z0-9]+$'), '');
    return name.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  Future<void> _autoEnableEnglishEmbedded(int epoch) async {
    if (!mounted || _isLoading || epoch != _audioMediaEpoch ||
        _subtitleManuallySelected || _isSubtitleEnabled ||
        _subtitleAutoPending) return;
    final preferred = PlaybackAutoselection.preferredEmbedded(_embeddedSubtitles);
    if (preferred == null) return;
    _subtitleAutoPending = true;
    try {
      await _player.setSubtitleTrack(SubtitleTrack(
        preferred.index.toString(), preferred.title, preferred.language,
      ));
      if (!mounted || epoch != _audioMediaEpoch || _subtitleManuallySelected) {
        return;
      }
      setState(() {
        _selectedEmbeddedSubtitleIndex = preferred.index;
        _currentSubtitleVariant = SubtitleVariant(
          providerName: 'Embedded',
          language: preferred.language ?? 'English',
          title: preferred.title,
          downloadUrl: '',
          format: 'ass',
        );
        _isSubtitleEnabled = true;
        _currentSubtitlePath = null;
        _currentCues = [];
      });
      debugPrint('[PlayerSubtitles] Selected embedded English: ${preferred.title}');
      _setSubtitleScale(_subtitleScale);
      unawaited(PlayerSettings.applySubtitleStyling(_player));
    } catch (error) {
      debugPrint('[PlayerSubtitles] Embedded English track unavailable: $error');
    } finally {
      _subtitleAutoPending = false;
    }
  }

  Future<void> _fetchInitialSubtitles() async {
    final epoch = _audioMediaEpoch;
    // Wait briefly for mpv to enumerate embedded tracks on slow TorBox files.
    await Future<void>.delayed(const Duration(milliseconds: 850));
    if (!mounted || epoch != _audioMediaEpoch) return;
    await _autoEnableEnglishEmbedded(epoch);
    try {
      int? searchYear;
      if (widget.detail?.year != null && widget.detail!.year!.isNotEmpty) {
        final yMatch = RegExp(r'\b(19\d\d|20\d\d)\b').firstMatch(widget.detail!.year!);
        if (yMatch != null) searchYear = int.tryParse(yMatch.group(1)!);
      }
      final rawName = widget.detail?.name ?? widget.title;
      if (searchYear == null) {
        final yMatch = RegExp(r'\b(19\d\d|20\d\d)\b').firstMatch(rawName);
        if (yMatch != null) searchYear = int.tryParse(yMatch.group(1)!);
      }
      final showName = cleanMediaTitle(rawName);
      final groups = await SubtitleService().fetchAllSubtitles(
        showName,
        imdbId: widget.detail?.id,
        season: _currentEpisode?.season,
        episode: _currentEpisode?.episode,
        year: searchYear,
      );
      if (!mounted || epoch != _audioMediaEpoch) return;
      setState(() => _subtitleGroups = groups);
      if (_subtitleManuallySelected || _isSubtitleEnabled) return;

      // Prefer labeled English forced/embedded subtitles. If missing, download
      // English subtitles from OpenSubtitles or another configured provider.
      await _autoEnableEnglishEmbedded(epoch);
      if (_isSubtitleEnabled || _subtitleManuallySelected) return;
      for (final variant in PlaybackAutoselection.preferredExternal(groups)) {
        if (!mounted || epoch != _audioMediaEpoch ||
            _subtitleManuallySelected || _isSubtitleEnabled) break;
        final loaded = await _loadSubtitle(variant,
            automatic: true, expectedEpoch: epoch);
        if (loaded) break;
      }
    } catch (error) {
      debugPrint('[PlayerSubtitles] English subtitle lookup failed: $error');
    }
  }

  void _startHideControlsTimer() {
    _hideTimer?.cancel();
    if (_showDiagnostics) return;
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted &&
          _isPlaying &&
          !_isHoveringUI &&
          _activeMenu == null &&
          !_showSubSyncBar &&
          !_showTextSyncOverlay) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    if (_showTextSyncOverlay || _activeMenu != null || _showDiagnostics) return;
    setState(() => _showControls = !_showControls);
    if (_showControls) _startHideControlsTimer();
  }

  void _handlePointerActivity() {
    if (_isLoading) return;
    if (!_showControls) setState(() => _showControls = true);

    final now = DateTime.now();
    if (_lastPointerTimerReset == null ||
        now.difference(_lastPointerTimerReset!) >= const Duration(milliseconds: 250)) {
      _lastPointerTimerReset = now;
      _startHideControlsTimer();
    }
  }

  String _diagnosticsSourceKind() {
    final url = _currentSource.url ?? '';
    if (_currentSource.name?.toLowerCase() == 'downloaded' ||
        url.startsWith('file:') || url.startsWith('/')) {
      return 'Local file';
    }
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return 'HTTP stream';
    }
    if (url.startsWith('magnet:') ||
        _currentSource.infoHash?.isNotEmpty == true) {
      return 'Torrent / P2P';
    }
    return 'Other';
  }

  void _toggleDiagnostics() {
    if (_isLoading || !mounted) return;
    final next = !_showDiagnostics;
    _diagnosticsTimer?.cancel();
    ++_diagnosticsRevision;
    setState(() {
      _showDiagnostics = next;
      if (next) {
        _showControls = true;
        _activeMenu = null;
        _diagnosticsProperties = {};
      }
    });
    if (next) {
      _hideTimer?.cancel();
      unawaited(_readDiagnostics());
      _diagnosticsTimer = Timer.periodic(const Duration(seconds: 2),
          (_) => unawaited(_readDiagnostics()));
    } else {
      _startHideControlsTimer();
    }
  }

  Future<void> _readDiagnostics() async {
    if (!mounted || !_showDiagnostics || _isLoading ||
        _diagnosticsReading) return;
    _diagnosticsReading = true;
    final generation = _streamGeneration;
    final revision = _diagnosticsRevision;
    try {
      final dynamic native = _player.platform;
      final properties = await PlaybackDiagnosticsProbe.sample(
        (name) async => await native.getProperty(name),
      );
      if (!mounted || !_showDiagnostics || _isLoading ||
          generation != _streamGeneration ||
          revision != _diagnosticsRevision) return;
      setState(() => _diagnosticsProperties = properties);
    } finally {
      _diagnosticsReading = false;
    }
  }

  void _toggleMenu(String menuName) {
    if (menuName == 'audio') {
      unawaited(_refreshNativeAudioTracks(_audioMediaEpoch));
    }
    setState(() {
      if (_activeMenu == menuName) {
        _activeMenu = null;
        _startHideControlsTimer();
      } else {
        _activeMenu = menuName;
        _showSubSyncBar = false;
        _showTextSyncOverlay = false;
        _hideTimer?.cancel();
      }
    });
  }

  void _selectEmbeddedSubtitle(PlayerEmbeddedSubtitle embedded) {
    _subtitleManuallySelected = true;
    setState(() {
      _selectedEmbeddedSubtitleIndex = embedded.index;
      _currentSubtitleVariant = SubtitleVariant(
        providerName: 'Embedded',
        language: embedded.language ?? 'Embedded',
        title: embedded.title,
        downloadUrl: '',
        format: 'ass',
      );
      _isSubtitleEnabled = true;
      _currentSubtitlePath = null;
      _currentCues = [];
    });

    _player.setSubtitleTrack(SubtitleTrack(embedded.index.toString(), embedded.title, embedded.language));
    _setSubtitleScale(_subtitleScale);
    PlayerSettings.applySubtitleStyling(_player);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Switched to embedded subtitle: ${embedded.title}'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _disableSubtitles() {
    _subtitleManuallySelected = true;
    setState(() {
      _isSubtitleEnabled = false;
      _currentSubtitleVariant = null;
      _selectedEmbeddedSubtitleIndex = null;
      _currentSubtitlePath = null;
      _currentCues = [];
    });
    _player.setSubtitleTrack(SubtitleTrack.no());
  }

  // On iOS, compare recognized actual dialogue with external subtitle cues.
  // Never invent a timing offset if two independent phrases cannot agree.
  Future<void> _autoSyncSubtitles() async {
    if (_autoSyncBusy || _isLoading) return;
    final epoch = _audioMediaEpoch;
    setState(() => _autoSyncBusy = true);
    try {
      if (Platform.isIOS) {
        await _autoSyncToSpokenAudio(epoch);
      } else {
        await _autoSyncByReleaseName(epoch);
      }
    } on PlatformException catch (error) {
      if (mounted && epoch == _audioMediaEpoch) {
        _showAutoSyncMessage(error.message ??
            'Speech recognition unavailable. Subtitle timing was not changed.');
      }
    } on TimeoutException {
      if (mounted && epoch == _audioMediaEpoch) {
        _showAutoSyncMessage('Speech recognition timed out. Timing was not changed.');
      }
    } catch (error) {
      debugPrint('[PlayerSpeechSync] Alignment failed: ${error.runtimeType}');
      if (mounted && epoch == _audioMediaEpoch) {
        _showAutoSyncMessage(
          'Audio sync was not possible for this media. Try an MP4/HLS source or manual subtitle sync.');
      }
    } finally {
      if (mounted) setState(() => _autoSyncBusy = false);
    }
  }

  void _showAutoSyncMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      duration: const Duration(seconds: 5),
    ));
  }

  Future<void> _autoSyncToSpokenAudio(int epoch) async {
    var cues = _currentCues;
    if (_currentSubtitlePath == null || cues.length < 2) {
      // Embedded subtitles do not expose timed text through media_kit.
      // Find external English text rather than guessing based on track names.
      final candidates = PlaybackAutoselection.preferredExternal(
        _subtitleGroups, mediaTitle: _currentSource.name ?? '',
      );
      var loaded = false;
      for (final variant in candidates.take(3)) {
        if (!mounted || epoch != _audioMediaEpoch) return;
        if (await _loadSubtitle(variant, automatic: false, expectedEpoch: epoch)) {
          loaded = true;
          break;
        }
      }
      if (!loaded || _currentCues.length < 2) {
        _showAutoSyncMessage(
          'Select or download an external English subtitle first; speech sync needs subtitle text.');
        return;
      }
      cues = _currentCues;
    }
    final mediaUrl = _speechMediaUrl;
    if (mediaUrl == null || mediaUrl.isEmpty) {
      _showAutoSyncMessage('Audio for this stream is not available to the iOS speech recognizer.');
      return;
    }
    final subtitlePath = _currentSubtitlePath;
    final positionSeconds = _position.inMilliseconds / 1000.0;
    final durationSeconds = _duration.inMilliseconds / 1000.0;
    if (durationSeconds < 15) {
      _showAutoSyncMessage('Speech sync needs a seekable movie or episode, not a live stream.');
      return;
    }
    final maxStart = (durationSeconds - IosSpeechTranscriber.maxSampleSeconds)
        .clamp(0.0, durationSeconds);
    final sampleStart = (positionSeconds - 20).clamp(0.0, maxStart).toDouble();
    final sampleLength =
        (durationSeconds - sampleStart)
            .clamp(15.0, IosSpeechTranscriber.maxSampleSeconds)
            .toDouble();
    _showAutoSyncMessage('Checking English speech recognition for this iPad...');
    List<SpeechTimedWord> words;
    try {
      words = await IosSpeechTranscriber.transcribe(
        mediaUrl: mediaUrl,
        startSeconds: sampleStart,
        durationSeconds: sampleLength,
        httpHeaders: _speechMediaHeaders,
        audioTrackId: _selectedAudioTrackIndex,
        onPlaybackDecoderFallback: () {
          if (mounted && epoch == _audioMediaEpoch) {
            _showAutoSyncMessage(
              'Decoding this stream\'s audio with the movie player. '
              'This can take up to a minute; playback will continue.',
            );
          }
        },
      );
    } on PlatformException catch (error) {
      if (error.code != 'network_required' &&
          error.code != 'offline_recognition_failed') rethrow;
      if (!mounted || epoch != _audioMediaEpoch ||
          subtitlePath != _currentSubtitlePath ||
          mediaUrl != _speechMediaUrl) return;
      final approved = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Use Apple online Speech Recognition?'),
          content: const Text(
            'This iPad cannot recognize English speech entirely offline. '
            'To align subtitles, Apple can process up to 55 seconds of this '
            'movie\'s audio on its speech servers. Internet is required. '
            'The microphone is not used.\n\n'
            'Nothing will be sent unless you choose Allow. '
            'This permission is for this Auto Sync attempt only.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Not now'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Allow Apple service'),
            ),
          ],
        ),
      );
      if (!mounted || epoch != _audioMediaEpoch ||
          subtitlePath != _currentSubtitlePath ||
          mediaUrl != _speechMediaUrl) return;
      if (approved != true) {
        _showAutoSyncMessage(
          'Speech sync cancelled. No audio was sent to Apple; subtitle timing unchanged.',
        );
        return;
      }
      _showAutoSyncMessage('Sending a short movie-audio excerpt to Apple for this attempt...');
      words = await IosSpeechTranscriber.transcribe(
        mediaUrl: mediaUrl,
        startSeconds: sampleStart,
        durationSeconds: sampleLength,
        allowAppleNetworkRecognition: true,
        httpHeaders: _speechMediaHeaders,
        audioTrackId: _selectedAudioTrackIndex,
        onPlaybackDecoderFallback: () {
          if (mounted && epoch == _audioMediaEpoch) {
            _showAutoSyncMessage(
              'Decoding this stream\'s audio with the movie player. '
              'This can take up to a minute; playback will continue.',
            );
          }
        },
      );
    }
    if (!mounted || epoch != _audioMediaEpoch ||
        subtitlePath != _currentSubtitlePath ||
        mediaUrl != _speechMediaUrl) return;
    final estimate = SpeechSubtitleAlignment.estimate(
      cues: cues,
      speech: words,
      sampleStartSeconds: sampleStart,
      sampleEndSeconds: sampleStart + sampleLength,
    );
    if (estimate == null) {
      _showAutoSyncMessage(
        'Could not match enough spoken dialogue to subtitle lines. Timing left unchanged; try another scene.');
      return;
    }
    if (!mounted || epoch != _audioMediaEpoch ||
        subtitlePath != _currentSubtitlePath) return;
    final applied = await _applyLiveDelay(estimate.delaySeconds);
    if (applied && mounted && epoch == _audioMediaEpoch) {
      setState(() {});
      final offset = estimate.delaySeconds;
      final direction = offset < 0 ? 'earlier' : 'later';
      _showAutoSyncMessage(
        'Aligned subtitles to spoken audio: ${offset.abs().toStringAsFixed(1)}s $direction '
        'using ${estimate.supportingCues} matching dialogue lines.');
    } else if (mounted && epoch == _audioMediaEpoch) {
      _showAutoSyncMessage('Could not update subtitle timing in the player.');
    }
  }

  Future<void> _autoSyncByReleaseName(int epoch) async {
    final ranked = PlaybackAutoselection.preferredExternal(
      _subtitleGroups, mediaTitle: _currentSource.name ?? '',
    );
    final alternatives = ranked.where((v) =>
        v.downloadUrl != _currentSubtitleVariant?.downloadUrl).take(6);
    bool loaded = false;
    for (final variant in alternatives) {
      if (!mounted || epoch != _audioMediaEpoch) return;
      loaded = await _loadSubtitle(variant, automatic: false,
          expectedEpoch: epoch);
      if (loaded) break;
    }
    if (mounted && epoch == _audioMediaEpoch) {
      _showAutoSyncMessage(loaded
          ? 'Loaded a better release-matched subtitle. Check its timing.'
          : 'No alternative English subtitle found. Use manual sync for timing.');
    }
  }

  Future<bool> _loadSubtitle(
    SubtitleVariant variant, {
    bool automatic = false,
    int? expectedEpoch,
  }) async {
    final epoch = expectedEpoch ?? _audioMediaEpoch;
    if (!automatic) _subtitleManuallySelected = true;
    if (!automatic && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Downloading ${variant.language} subtitle...'),
        duration: const Duration(seconds: 2),
      ));
    }
    String? path;
    try {
      path = await SubtitleService().downloadSubtitle(variant);
    } catch (error) {
      debugPrint('[PlayerSubtitles] Download error: $error');
    }
    if (!mounted || epoch != _audioMediaEpoch ||
        (automatic && (_subtitleManuallySelected || _isSubtitleEnabled))) {
      return false;
    }
    if (path == null || !await File(path).exists()) {
      if (!automatic && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to download subtitle')),
        );
      }
      return false;
    }
    try {
      final bytes = await File(path).readAsBytes();
      final content = SubtitleParser.decodeBytesWithFallback(bytes);
      final result = SubtitleParser.parse(content);
      if (!mounted || epoch != _audioMediaEpoch ||
          (automatic && (_subtitleManuallySelected || _isSubtitleEnabled))) {
        return false;
      }
      await _player.setSubtitleTrack(SubtitleTrack.uri(
          _resolveSubtitleUri(path), title: variant.language));
      if (!mounted || epoch != _audioMediaEpoch) return false;
      setState(() {
        _currentSubtitleVariant = variant;
        _selectedEmbeddedSubtitleIndex = null;
        _isSubtitleEnabled = true;
        _currentSubtitlePath = path;
        _currentCues = result.cues;
        _currentSubFormat = result.format;
      });
      _setSubtitleScale(_subtitleScale);
      unawaited(PlayerSettings.applySubtitleStyling(_player));
      if (_subtitleDelayMs != 0) {
        await _applyLiveDelay(_subtitleDelayMs / 1000.0);
      }
      if (!automatic && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${variant.language} subtitle loaded (${_currentCues.length} lines)'),
          duration: const Duration(seconds: 2),
        ));
      }
      debugPrint('[PlayerSubtitles] English external subtitles enabled from ${variant.providerName}');
      return true;
    } catch (error) {
      debugPrint('[PlayerSubtitles] Subtitle activation failed: $error');
      return false;
    }
  }

  String _resolveSubtitleUri(String pathOrUrl) {
    if (pathOrUrl.startsWith('http://') || pathOrUrl.startsWith('https://')) {
      return pathOrUrl;
    }
    try {
      final file = File(pathOrUrl);
      if (file.existsSync()) {
        final canonicalPath = file.resolveSymbolicLinksSync();
        return Uri.file(canonicalPath).toString();
      }
    } catch (_) {}

    final uri = Uri.tryParse(pathOrUrl);
    if (uri != null && uri.hasScheme && !(Platform.isWindows && RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(pathOrUrl))) {
      return pathOrUrl;
    }
    return Uri.file(pathOrUrl).toString();
  }

  void _setSubtitleScale(double scale) {
    final clamped = scale.clamp(0.5, 3.0);
    setState(() => _subtitleScale = clamped);
    PlayerSettings.setSubScale(clamped, player: _player);
  }

  Future<bool> _applyLiveDelay(double delaySec) async {
    if (!delaySec.isFinite || delaySec.abs() > 150) return false;
    final np = _player.platform as dynamic;
    try {
      await np.setProperty('sub-delay', delaySec.toString());
      _subtitleDelayMs = delaySec * 1000.0;
      return true;
    } catch (e) {
      debugPrint('[PlayerScreen] applyLiveDelay failed: ${e.runtimeType}');
      return false;
    }
  }

  Future<void> _saveTextSyncedCues(List<SubCue> syncedCues, double offsetSec) async {
    _currentCues = syncedCues;
    _subtitleDelayMs = 0.0; // Reset live delay since timestamps are now permanently baked into cues
    if (_currentSubtitlePath != null) {
      final content = _currentSubFormat == SubFormat.vtt
          ? SubtitleParser.toVtt(syncedCues)
          : SubtitleParser.toSrt(syncedCues);
      final ext = _currentSubFormat == SubFormat.vtt ? 'vtt' : 'srt';
      final cleanBase = _currentSubtitlePath!.replaceAll(
        RegExp(r'(_delayed.*|_synced.*)?\.(srt|vtt)$', caseSensitive: false),
        '',
      );
      final newPath = '${cleanBase}_synced_${DateTime.now().millisecondsSinceEpoch}.$ext';
      await File(newPath).writeAsString(content, flush: true);
      _currentSubtitlePath = newPath;
      final resolvedUri = _resolveSubtitleUri(newPath);
      _player.setSubtitleTrack(SubtitleTrack.uri(resolvedUri));
      _setSubtitleScale(_subtitleScale);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Subtitle timing synchronized and saved!')),
        );
      }
    }
  }

  void _onControllerError(dynamic err) {
    if (!mounted) return;
    final errorMsg = err.toString();
    print('[PlayerScreen ERROR] Player error: $errorMsg');

    if (!_isLoading && !_httpReconnecting &&
        PausedHttpRecovery.canRetryError(
          errorMsg, _httpVodUrl != null, _httpResumedAt,
          DateTime.now(), _httpReconnectAttempts)) {
      unawaited(_reconnectPausedHttp());
      return;
    }

    // Ignore non-fatal subtitle track loading errors so video playback is not interrupted
    final lower = errorMsg.toLowerCase();
    if (lower.contains('can not open external file') ||
        lower.contains('subtitle') ||
        lower.contains('sub-add') ||
        lower.contains('.srt') ||
        lower.contains('.vtt') ||
        lower.contains('.ass')) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not load subtitle: $errorMsg'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    if (_currentEpisode != null && widget.detail?.videos.isNotEmpty == true) {
      setState(() {
        _isLoading = false;
        _showSourcesPanel = true;
        _sourcesEpisode = _currentEpisode;
        _sourcesErrorMessage = 'Playback error: $errorMsg. Please select another source below.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = 'Playback error: $errorMsg';
    });
  }

  void _applyVolume(double vol, {bool showHud = false}) {
    final clamped = ((vol * 100).round() / 100.0).clamp(0.0, PlayerVolumeControl.maxVolume);
    setState(() {
      _volume = clamped;
      _isMuted = clamped == 0;
      if (showHud) _showVolumeHud = true;
    });

    if (showHud) {
      _volumeHudTimer?.cancel();
      _volumeHudTimer = Timer(const Duration(milliseconds: 1300), () {
        if (mounted) setState(() => _showVolumeHud = false);
      });
    }

    _player.setVolume(clamped * 100.0);
  }

  void _toggleMute({bool showHud = false}) {
    if (_volume > 0 && !_isMuted) {
      _lastVolumeBeforeMute = _volume;
      setState(() {
        _isMuted = true;
        if (showHud) _showVolumeHud = true;
      });
      _player.setVolume(0.0);
    } else {
      final restore = _lastVolumeBeforeMute > 0 ? _lastVolumeBeforeMute : 1.0;
      setState(() {
        _volume = restore;
        _isMuted = false;
        if (showHud) _showVolumeHud = true;
      });
      _player.setVolume(restore * 100.0);
    }

    if (showHud) {
      _volumeHudTimer?.cancel();
      _volumeHudTimer = Timer(const Duration(milliseconds: 1300), () {
        if (mounted) setState(() => _showVolumeHud = false);
      });
    }
  }

  void _togglePlayPause() {
    if (_httpReconnecting || _isLoading) return;
    if (_player.state.playing) {
      _httpPausedAt = DateTime.now();
      unawaited(_player.pause());
    } else {
      final now = DateTime.now();
      final longPause = PausedHttpRecovery.needsReopen(
          _httpVodUrl != null, _httpPausedAt, now);
      _httpResumedAt = now;
      _httpPausedAt = null;
      if (longPause && _httpReconnectAttempts < PausedHttpRecovery.maxAttempts) {
        unawaited(_reconnectPausedHttp());
      } else {
        unawaited(_player.play());
      }
    }
    _startHideControlsTimer();
  }

  /// Open a fresh HTTP connection at the current position. This avoids
  /// reusing an expired TCP socket held across an extended iPadOS pause.
  /// Do not call _initStream(): it would reset the episode/resume context.
  Future<void> _reconnectPausedHttp() async {
    if (!mounted || _httpReconnecting || _httpVodUrl == null ||
        _httpReconnectAttempts >= PausedHttpRecovery.maxAttempts) return;
    final generation = _streamGeneration;
    final url = _httpVodUrl!;
    final headers = Map<String, String>.from(_httpVodHeaders ?? {});
    final resumeAt = PausedHttpRecovery.safePosition(
        _player.state.position, _player.state.duration);
    final manualAudio = _audioManuallySelected ? _selectedAudioTrackIndex : null;
    _httpReconnecting = true;
    setState(() {
      _isLoading = true;
      _statusMessage = 'Reconnecting stream at saved position...';
      _showSourcesPanel = false;
    });
    try {
      while (mounted && generation == _streamGeneration &&
          _httpReconnectAttempts < PausedHttpRecovery.maxAttempts) {
        _httpReconnectAttempts++;
        try {
          await _player.open(
            Media(url, httpHeaders: headers,
              start: resumeAt > Duration.zero ? resumeAt : null),
            play: true,
          ).timeout(const Duration(seconds: 35));
          if (!mounted || generation != _streamGeneration) return;
          await PlayerSettings.applyPostOpenProperties(_player);
          await _player.setRate(_playbackRate);
          await _player.setVolume((_isMuted ? 0.0 : _volume) * 100.0);
          if (!mounted || generation != _streamGeneration) return;
          final epoch = ++_audioMediaEpoch;
          _audioTracks = [];
          _selectedAudioTrackIndex = manualAudio ?? 0;
          _audioAutoSelectionPending = false;
          _audioManuallySelected = manualAudio != null;
          setState(() {
            _isLoading = false;
            _statusMessage = 'Stream reconnected';
            _sourcesErrorMessage = null;
          });
          _updateMediaTracks(_player.state.tracks);
          _scheduleAudioProbes(epoch);
          if (manualAudio != null && manualAudio > 0) {
            unawaited(_selectAudioTrack(manualAudio, manual: false));
          } else {
            _preferEnglishAudioTrack();
          }
          _httpResumedAt = DateTime.now();
          _startHideControlsTimer();
          return;
        } catch (error) {
          debugPrint('[PlayerScreen] HTTP resume reconnect failed ('
              + error.runtimeType.toString() + ')');
          if (_httpReconnectAttempts < PausedHttpRecovery.maxAttempts &&
              mounted && generation == _streamGeneration) {
            await Future<void>.delayed(const Duration(milliseconds: 1500));
          }
        }
      }
      if (!mounted || generation != _streamGeneration) return;
      setState(() {
        _isLoading = false;
        _statusMessage = 'Stream connection expired. Select another source.';
        if (_currentEpisode != null) {
          _showSourcesPanel = true;
          _sourcesEpisode = _currentEpisode;
          _sourcesErrorMessage = 'Could not restore the connection. '
              'Please choose another source.';
        }
      });
    } finally {
      _httpReconnecting = false;
    }
  }

  void _seekRelative(Duration offset) {
    final cur = _player.state.position;
    final dur = _player.state.duration;
    final target = cur + offset;
    final clamped = target < Duration.zero
        ? Duration.zero
        : (dur > Duration.zero && target > dur ? dur : target);
    _player.seek(clamped);
    _startHideControlsTimer();
  }

  void _toggleEpisodesPanel() {
    setState(() {
      _showEpisodesPanel = !_showEpisodesPanel;
      if (_showEpisodesPanel) {
        _showSourcesPanel = false;
        _activeMenu = null;
        _showSubSyncBar = false;
        _showTextSyncOverlay = false;
        _showControls = true;
      }
    });
  }

  void _onEpisodeChosen(Video episode) {
    setState(() {
      _showEpisodesPanel = false;
      _showSourcesPanel = true;
      _sourcesEpisode = episode;
      _sourcesErrorMessage = null;
      _activeMenu = null;
      _showControls = true;
    });
  }

  void _onBackToEpisodes() {
    setState(() {
      _showSourcesPanel = false;
      _showEpisodesPanel = true;
      _sourcesErrorMessage = null;
    });
  }

  /// Continue Watching often passes minimal show metadata without videos.
  /// Fetch Cinemeta's full episode catalog to provide reliable next-season
  /// transitions; retain a numbered fallback if metadata is unavailable.
  Future<void> _fetchEpisodeCatalog() async {
    final detail = widget.detail;
    if (detail == null || !detail.id.startsWith('tt') ||
        _currentEpisode == null) return;
    try {
      final meta = await MetadataService.fetchMeta(
        baseUrl: 'https://v3-cinemeta.strem.io',
        type: 'series',
        imdbId: detail.id,
      ).timeout(const Duration(seconds: 8));
      if (!mounted || meta == null || meta.videos.isEmpty) return;
      setState(() {
        _episodeCatalog = meta.videos;
        _episodeCatalogComplete = true;
      });
    } catch (error) {
      debugPrint('[PlayerAutoplay] Episode catalog unavailable: $error');
    }
  }

  Video? get _nextEpisode => PlaybackAutoselection.nextEpisodeCandidate(
      knownEpisodes: _episodeCatalog,
      current: _currentEpisode,
      showId: widget.detail?.id ?? '',
      catalogComplete: _episodeCatalogComplete);

  Future<void> _goToNextEpisode() async {
    final next = _nextEpisode;
    if (next == null || _nextEpisodeBusy || !mounted) return;
    final epoch = _audioMediaEpoch;
    setState(() {
      _nextEpisodeBusy = true;
      _statusMessage = 'Finding next episode S${next.season}E${next.episode}...';
      _showControls = true;
    });
    try {
      final detail = widget.detail;
      final type = detail?.type ?? 'series';
      final id = next.id.isNotEmpty
          ? next.id
          : '${detail?.id ?? ''}:${next.season ?? 1}:${next.episode ?? 1}';
      final title = detail?.name ?? widget.title;
      final year = int.tryParse(detail?.year ?? '');
      final cached = _cachedSourcesByEpisode[
        '${next.season ?? 1}:${next.episode ?? 1}'] ?? next.streams;
      StreamSource? found = PlaybackAutoselection.preferredSource(
          cached, _currentSource);
      if (found == null) {
        try {
          // Continue with the previously used addon (Torrentio/TorBox etc).
          found = await StreamService.fetchStreamsForTargetAddon(
            targetAddonName: _currentSource.addonName,
            type: type,
            id: id,
            title: title,
            year: year,
            season: next.season,
            episode: next.episode,
          ).where((s) => (s.url?.isNotEmpty ?? false) ||
              (s.infoHash?.isNotEmpty ?? false))
              .first.timeout(const Duration(seconds: 11));
        } catch (error) {
          debugPrint('[PlayerAutoplay] Preferred addon had no stream: $error');
        }
      }
      if (found == null) {
        try {
          // When the previous source is unavailable, use the first playable
          // provider result rather than interrupting the binge session.
          found = await StreamService.fetchStreams(
            type: type,
            id: id,
            title: title,
            year: year,
            season: next.season,
            episode: next.episode,
          ).where((s) => (s.url?.isNotEmpty ?? false) ||
              (s.infoHash?.isNotEmpty ?? false))
              .first.timeout(const Duration(seconds: 13));
        } catch (error) {
          debugPrint('[PlayerAutoplay] General source lookup failed: $error');
        }
      }
      if (!mounted || epoch != _audioMediaEpoch) return;
      if (found != null) {
        debugPrint('[PlayerAutoplay] Continuing S${next.season}E${next.episode} via ${found.addonName}');
        await _switchStream(found, next);
      } else {
        // Never silently stop on an empty scrape: offer manual sources.
        setState(() {
          _showSourcesPanel = true;
          _showEpisodesPanel = false;
          _sourcesEpisode = next;
          _sourcesErrorMessage = 'No automatic source found. Choose a source for the next episode.';
        });
      }
    } finally {
      if (mounted) setState(() => _nextEpisodeBusy = false);
    }
  }

  void _playNewSource(StreamSource newSource, Video episode) {
    setState(() {
      _showSourcesPanel = false;
      _showEpisodesPanel = false;
      _sourcesErrorMessage = null;
    });
    unawaited(_switchStream(newSource, episode));
  }

  Future<void> _switchStream(StreamSource newSource, Video newEpisode) async {
    _progressSaveTimer?.cancel();
    _savePlaybackProgress();

    setState(() {
      _currentSource = newSource;
      _currentEpisode = newEpisode;
      final showName = widget.detail?.name ?? widget.title;
      final epNum = newEpisode.episode ?? 1;
      final sNum = newEpisode.season ?? 1;
      _currentTitle = '$showName - S${sNum}E$epNum ${newEpisode.title}';
      _isLoading = true;
      _statusMessage = 'Buffering S$sNum:E$epNum - ${newEpisode.title.isNotEmpty ? newEpisode.title : "Episode $epNum"}...';
      _showEpisodesPanel = false;
      _showSourcesPanel = false;
      _activeMenu = null;
      _showSubSyncBar = false;
      _showTextSyncOverlay = false;
      _showSkipButton = false;
      _activeSkipSegment = null;
      _skipSegments = [];
      _dismissedSegmentKeys.clear();
      _subtitleGroups = [];
      _currentSubtitlePath = null;
      _currentCues = [];
      _currentSubtitleVariant = null;
      _isSubtitleEnabled = false;
      _selectedEmbeddedSubtitleIndex = null;
    });

    // Cleanup previous torrent engine if was P2P
    TorrentStreamService().cleanup();

    await _initStream();
  }

  Future<void> _fetchSkipSegments() async {
    final epoch = _skipMediaEpoch;
    final episode = _currentEpisode;
    final detail = widget.detail;
    // Never apply show-level timings to an arbitrary episode.
    if (episode != null && (episode.season == null || episode.episode == null)) {
      return;
    }
    try {
      final skipData = await SkipSegmentsService.instance.fetchSkipSegments(
        tmdbId: detail?.tmdbId,
        imdbId: (detail != null && detail.id.startsWith('tt')) ? detail.id : null,
        title: detail?.name ?? widget.title,
        year: int.tryParse(detail?.year ?? ''),
        type: episode != null ? 'tv' : (detail?.type ?? 'movie'),
        season: episode?.season,
        episode: episode?.episode,
        durationMs: _player.state.duration.inMilliseconds,
      );
      if (!mounted || epoch != _skipMediaEpoch || skipData == null) return;
      if (episode != null &&
          ((skipData.season != null && skipData.season != episode.season) ||
           (skipData.episode != null && skipData.episode != episode.episode))) {
        debugPrint('[PlayerScreen] Ignoring mismatched episode skip data');
        return;
      }
      // Reject credits metadata that places end credits at the beginning of an
      // episode. Never allow such data to seek to EOF or advance playback.
      final mediaDuration = _player.state.duration;
      final safeSegments = skipData.segments.where((segment) {
        if (segment.type.trim().toLowerCase() != 'credits') return true;
        final start = segment.startMs;
        final durationMs = mediaDuration.inMilliseconds;
        final valid = start != null && durationMs > 0 &&
            start >= durationMs ~/ 2 && start < durationMs &&
            (segment.endMs == null ||
                (segment.endMs! > start && segment.endMs! <= durationMs + 2000));
        if (!valid) {
          debugPrint('[PlayerScreen] Discarding invalid early credits metadata');
        }
        return valid;
      }).toList();
      setState(() => _skipSegments = safeSegments);
      // Metadata can arrive after playback has already entered the intro.
      _onPlaybackTick(_player.state.position);
    } catch (e) {
      debugPrint('[PlayerScreen] Error loading skip segments: $e');
    }
  }

  void _onPlaybackTick(Duration pos) {
    if (!mounted || _skipSegments.isEmpty) return;

    final dur = _player.state.duration;

    MediaSkipSegment? matched;
    for (final seg in _skipSegments) {
      if (seg.contains(pos, dur)) {
        matched = seg;
        break;
      }
    }

    if (matched != null) {
      if (!_dismissedSegmentKeys.contains(matched.uniqueKey)) {
        if (_activeSkipSegment?.uniqueKey != matched.uniqueKey) {
          setState(() {
            _activeSkipSegment = matched;
            _showSkipButton = true;
          });
        }
      }
    } else {
      if (_activeSkipSegment != null) {
        setState(() {
          _activeSkipSegment = null;
          _showSkipButton = false;
        });
      }
    }
  }

  void _handleSkipSegment(MediaSkipSegment seg) {
    if (!mounted || _activeSkipSegment?.uniqueKey != seg.uniqueKey) return;
    _dismissedSegmentKeys.add(seg.uniqueKey);
    final target = AutomaticSkipPolicy.destination(
        seg, _player.state.duration);
    if (target != null) {
      // Keep seeks inside known media duration. A seek to the end of credits
      // can trigger the existing next-episode completion path.
      final duration = _player.state.duration;
      final padded = target + const Duration(milliseconds: 300);
      _player.seek(duration > Duration.zero && padded > duration
          ? duration : padded);
    }
    setState(() {
      _showSkipButton = false;
      _activeSkipSegment = null;
    });
  }

  void _handleAutomaticSkipSegment(MediaSkipSegment seg) {
    if (!_isPlaying ||
        !seg.contains(_player.state.position, _player.state.duration) ||
        !AutomaticSkipPolicy.eligible(
            isSeriesEpisode: _currentEpisode != null,
            segment: seg,
            mediaDuration: _player.state.duration)) return;
    _handleSkipSegment(seg);
  }

  void _handleDismissSkipSegment(MediaSkipSegment seg) {
    if (!mounted || _activeSkipSegment?.uniqueKey != seg.uniqueKey) return;
    _dismissedSegmentKeys.add(seg.uniqueKey);
    setState(() {
      _showSkipButton = false;
      _activeSkipSegment = null;
    });
  }

  /// Open the show's actual information page from a resumed playback session.
  /// Keep this player mounted: navigating back returns to the same episode
  /// and position without having to fetch a torrent/stream again.
  Future<void> _openShowDetails() async {
    final detail = widget.detail;
    if (detail == null || detail.id.trim().isEmpty || !mounted) return;
    final wasPlaying = _player.state.playing;
    final wasFullscreen = WindowService.instance.isFullscreen;
    _savePlaybackProgress();
    _hideTimer?.cancel();
    if (wasPlaying) await _player.pause();
    if (wasFullscreen) await WindowService.instance.exitFullscreen();
    if (!mounted) return;

    try {
      await MediaDetailsNavigation.open(
        context,
        id: detail.id,
        title: detail.name,
        type: detail.type,
        poster: detail.poster,
        backdrop: detail.background ?? widget.backdropUrl,
        year: detail.year,
        addonName: _currentSource.addonName,
        episode: _currentEpisode?.episode,
      );
    } finally {
      if (mounted) {
        if (wasFullscreen && !WindowService.instance.isFullscreen) {
          await WindowService.instance.toggleFullscreen();
        }
        if (wasPlaying && !_isLoading) await _player.play();
        if (mounted) {
          setState(() => _showControls = true);
          _startHideControlsTimer();
        }
      }
    }
  }

  void _savePlaybackProgress() {
    if (widget.detail == null) return;

    final pos = _player.state.position.inSeconds;
    final dur = _player.state.duration.inSeconds;
    if (dur <= 0) return;

    ContinueWatchingService.saveProgress(
      detail: widget.detail!,
      episode: _currentEpisode,
      source: _currentSource,
      positionSeconds: pos,
      totalDurationSeconds: dur,
    );
  }

  /// Use a captured player snapshot and finish local journal writes before
  /// uploading progress/history on pause or player exit.
  void _saveAndSyncLastPosition() {
    final detail = widget.detail;
    final position = _player.state.position.inSeconds;
    final duration = _player.state.duration.inSeconds;
    final source = _currentSource;
    final episode = _currentEpisode;
    unawaited(() async {
      if (detail != null && duration >= 120 && position >= 5) {
        await ContinueWatchingService.saveProgress(
          detail: detail, episode: episode, source: source,
          positionSeconds: position, totalDurationSeconds: duration,
        );
      }
      await ContinueWatchingService.syncGitHubProgress(force: true);
      await WatchedHistoryService.syncGitHubHistory(force: true);
    }());
  }

  void _updateDiscordRpc({bool? isPaused}) {
    final paused = isPaused ?? !_isPlaying;
    final detail = widget.detail;
    final episode = _currentEpisode;
    final title = detail?.name ?? _currentTitle;
    final poster = widget.backdropUrl ?? detail?.poster ?? detail?.background;

    final type = (detail?.type ?? '').toLowerCase();
    final isAnime = type == 'anime' || (detail == null && _currentTitle.toLowerCase().contains('episode') && episode != null);
    final isSeries = type == 'series' || type == 'tv' || (!isAnime && episode != null);

    if (isAnime) {
      DiscordRpcService.instance.setWatchingAnime(
        title: title,
        season: episode?.season,
        episode: episode?.episode,
        episodeTitle: episode?.title,
        posterUrl: poster,
        position: _position,
        duration: _duration,
        isPaused: paused,
      );
    } else if (isSeries) {
      DiscordRpcService.instance.setWatchingSeries(
        title: title,
        season: episode?.season,
        episode: episode?.episode,
        episodeTitle: episode?.title,
        posterUrl: poster,
        position: _position,
        duration: _duration,
        isPaused: paused,
      );
    } else {
      DiscordRpcService.instance.setWatchingMovie(
        title: title,
        year: detail?.year,
        posterUrl: poster,
        position: _position,
        duration: _duration,
        isPaused: paused,
      );
    }
  }

  @override
  void dispose() {
    ++_streamGeneration;
    _audioMediaEpoch++;
    ++_diagnosticsRevision;
    _diagnosticsTimer?.cancel();
    for (final s in _subscriptions) {
      s.cancel();
    }
    _progressSaveTimer?.cancel();
    _volumeHudTimer?.cancel();
    _audioHudTimer?.cancel();
    _saveAndSyncLastPosition();
    WakelockPlus.disable();
    _hideTimer?.cancel();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    PlayerSettings.changeNotifier.removeListener(_onPlayerSettingsChanged);
    _positionNotifier.dispose();
    _bufferNotifier.dispose();
    _player.dispose();
    _logoAnimController.dispose();
    TorrentStreamService().cleanup();
    WindowService.instance.exitFullscreen();
    DiscordRpcService.instance.clearToIdle();
    super.dispose();
  }

  void _onPlayerSettingsChanged() {
    PlayerSettings.applyToPlayer(_player);
  }

  DateTime? _lastScreenTapTime;

  void _handleScreenTap() {
    final now = DateTime.now();
    if (_lastScreenTapTime != null &&
        now.difference(_lastScreenTapTime!) < const Duration(milliseconds: 280)) {
      _lastScreenTapTime = null;
      WindowService.instance.toggleFullscreen();
    } else {
      _lastScreenTapTime = now;
      _toggleControls();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        WindowService.instance.exitFullscreen();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Focus(
          autofocus: true,
          onKeyEvent: (node, event) {
            // Never intercept key events when typing or searching in text inputs or overlay
            if (_showTextSyncOverlay) {
              return KeyEventResult.ignored;
            }
            final primaryFocus = FocusManager.instance.primaryFocus;
            if (primaryFocus != null && primaryFocus.context != null) {
              final focusedWidget = primaryFocus.context!.widget;
              if (focusedWidget is EditableText) {
                return KeyEventResult.ignored;
              }
            }

            if (event is KeyDownEvent) {
              if (event.logicalKey == LogicalKeyboardKey.arrowUp ||
                  event.logicalKey == LogicalKeyboardKey.audioVolumeUp) {
                _applyVolume((_volume + 0.05).clamp(0.0, PlayerVolumeControl.maxVolume), showHud: true);
                return KeyEventResult.handled;
              } else if (event.logicalKey == LogicalKeyboardKey.arrowDown ||
                  event.logicalKey == LogicalKeyboardKey.audioVolumeDown) {
                _applyVolume((_volume - 0.05).clamp(0.0, PlayerVolumeControl.maxVolume), showHud: true);
                return KeyEventResult.handled;
              } else if (event.logicalKey == LogicalKeyboardKey.keyM) {
                _toggleMute(showHud: true);
                return KeyEventResult.handled;
              } else if (event.logicalKey == LogicalKeyboardKey.space ||
                  event.logicalKey == LogicalKeyboardKey.keyK) {
                _togglePlayPause();
                return KeyEventResult.handled;
              } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
                  event.logicalKey == LogicalKeyboardKey.keyJ) {
                _seekRelative(const Duration(seconds: -10));
                return KeyEventResult.handled;
              } else if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
                  event.logicalKey == LogicalKeyboardKey.keyL) {
                _seekRelative(const Duration(seconds: 10));
                return KeyEventResult.handled;
              } else if (event.logicalKey == LogicalKeyboardKey.keyF) {
                WindowService.instance.toggleFullscreen();
                return KeyEventResult.handled;
              }
            }
            return KeyEventResult.ignored;
          },
          child: Listener(
            onPointerSignal: (pointerSignal) {
              if (pointerSignal is PointerScrollEvent) {
                final delta = pointerSignal.scrollDelta.dy < 0 ? 0.05 : -0.05;
                final next = (_volume + delta).clamp(0.0, PlayerVolumeControl.maxVolume);
                _applyVolume((next * 100).round() / 100.0, showHud: true);
              }
            },
            child: MouseRegion(
              cursor: (_showControls || _isLoading || _activeMenu != null)
                  ? SystemMouseCursors.basic
                  : SystemMouseCursors.none,
              onHover: (_) => _handlePointerActivity(),
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _handleScreenTap,
                child: _buildPlayerBody(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBackgroundStack() {
    return Stack(
      children: [
        // Loading Backdrop
        if (_isLoading && widget.backdropUrl != null)
          Positioned.fill(
            child: Opacity(
              opacity: 0.4,
              child: Image.network(widget.backdropUrl!, fit: BoxFit.cover),
            ),
          ),

        // Video Player
        Center(
          child: _isLoading
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (widget.logoUrl != null)
                      AnimatedBuilder(
                        animation: _logoAnimController,
                        builder: (context, child) {
                          final val = _logoAnimController.value;
                          return Opacity(
                            opacity: 0.3 + (val * 0.7),
                            child: Transform.scale(
                              scale: 0.95 + (val * 0.1),
                              child: child,
                            ),
                          );
                        },
                        child: Image.network(
                          widget.logoUrl!,
                          height: 100,
                          fit: BoxFit.contain,
                        ),
                      )
                    else
                      const CircularProgressIndicator(color: PlayerTheme.accent),
                    const SizedBox(height: 32),
                    Text(
                      _statusMessage,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 16,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                )
              : SizedBox.expand(
                  child: ValueListenableBuilder<int>(
                    valueListenable: PlayerSettings.changeNotifier,
                    builder: (context, _, __) {
                      return mk.Video(
                        controller: _videoController,
                        fit: _videoFit,
                        controls: mk.NoVideoControls,
                        subtitleViewConfiguration: PlayerSettings.getSubtitleViewConfiguration(),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Future<void> _handleDownloadMedia() async {
    final mediaId = widget.detail?.id ?? _currentTitle;
    final season = _currentEpisode?.season;
    final episode = _currentEpisode?.episode;

    final existing = DownloadService.instance.tasksNotifier.value.where((t) {
      if (t.mediaId == mediaId && t.season == season && t.episode == episode) {
        return true;
      }
      return false;
    }).firstOrNull;

    if (existing != null) {
      if (existing.status == DownloadStatus.downloading) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Download already in progress in background.')),
        );
        return;
      } else if (existing.status == DownloadStatus.completed) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This media is already downloaded.')),
        );
        return;
      }
    }

    try {
      String? customDir;
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        customDir = await DownloadPathHelper.pickDownloadsDirectory();
        if (customDir == null) {
          // User canceled folder selection
          return;
        }
      }

      await DownloadService.instance.startDownload(
        title: widget.detail?.name ?? _currentTitle,
        mediaId: mediaId,
        type: widget.detail?.type ?? (widget.detail?.videos.isNotEmpty == true ? 'series' : 'movie'),
        season: season,
        episode: episode,
        episodeTitle: _currentEpisode?.title,
        posterUrl: widget.detail?.poster,
        backdropUrl: widget.detail?.background,
        year: widget.detail?.year,
        source: _currentSource,
        customDownloadDir: customDir,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Download started in background. Track progress in Downloads tab.'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download failed to start: $e')),
        );
      }
    }
  }

  Widget _buildControlsOverlay() {
    final buffered = _buffered;

    final episodeTitle = _currentEpisode?.title;
    final episodeSubtitle = _currentEpisode != null
        ? 'S${_currentEpisode!.season ?? 1}:E${_currentEpisode!.episode ?? 1}${episodeTitle != null && episodeTitle.isNotEmpty ? " • $episodeTitle" : ""}'
        : widget.detail?.year;

    final isOfflineFile = _currentSource.name == 'Downloaded';

    return Stack(
      children: [
        // Outside Tap Barrier to dismiss active floating menu
        if (_activeMenu != null)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => setState(() => _activeMenu = null),
              child: Container(color: Colors.transparent),
            ),
          ),

        // Top Header Bar
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: IgnorePointer(
            ignoring: (!_showControls && !_isLoading) || _showSubSyncBar || _showTextSyncOverlay,
            child: AnimatedOpacity(
              opacity: (_showControls || _isLoading) && !_showSubSyncBar && !_showTextSyncOverlay
                  ? 1.0
                  : 0.0,
              duration: const Duration(milliseconds: 200),
              child: MouseRegion(
                onEnter: (_) {
                  _isHoveringUI = true;
                  _hideTimer?.cancel();
                },
                onExit: (_) {
                  _isHoveringUI = false;
                  _startHideControlsTimer();
                },
                child: ValueListenableBuilder<List<DownloadTask>>(
                  valueListenable: DownloadService.instance.tasksNotifier,
                  builder: (context, tasks, _) {
                    final mediaId = widget.detail?.id ?? _currentTitle;
                    final season = _currentEpisode?.season;
                    final episode = _currentEpisode?.episode;
                    final isDownloading = tasks.any((t) =>
                        t.mediaId == mediaId &&
                        t.season == season &&
                        t.episode == episode &&
                        t.status == DownloadStatus.downloading);

                    return PlayerTopBar(
                      title: widget.detail?.name ?? _currentTitle,
                      subtitle: episodeSubtitle,
                      quality: _currentSource.name,
                      onDownload: (_isLoading || isOfflineFile) ? null : _handleDownloadMedia,
                      onShowDetails: widget.detail?.id.isNotEmpty == true
                          ? () => unawaited(_openShowDetails()) : null,
                      isDownloading: isDownloading,
                      onToggleEpisodes: (!_isLoading && _episodeCatalog.isNotEmpty)
                          ? _toggleEpisodesPanel
                          : null,
                      isEpisodesActive: _showEpisodesPanel || _showSourcesPanel,
                      onBack: () {
                        WindowService.instance.exitFullscreen();
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
            ),
          ),
        ),

          // Bottom Transport Bar
          if (!_isLoading)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                ignoring: (!_showControls && _activeMenu == null) || _showTextSyncOverlay,
                child: AnimatedOpacity(
                  opacity: (_showControls || _activeMenu != null) && !_showTextSyncOverlay ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: MouseRegion(
                    onEnter: (_) {
                      _isHoveringUI = true;
                      _hideTimer?.cancel();
                    },
                    onExit: (_) {
                      _isHoveringUI = false;
                      _startHideControlsTimer();
                    },
                    child: ValueListenableBuilder<bool>(
                      valueListenable: WindowService.instance.isFullscreenNotifier,
                      builder: (context, isFs, _) {
                        return PlayerTransport(
                          isPlaying: _isPlaying,
                          position: _position,
                          duration: _duration,
                          buffered: buffered,
                          positionListenable: _positionNotifier,
                          bufferedListenable: _bufferNotifier,
                          skipSegments: _skipSegments,
                          volume: _volume,
                          isMuted: _isMuted || _volume == 0,
                          playbackRate: _playbackRate,
                          isSubtitlesActive: _isSubtitleEnabled && _currentSubtitleVariant != null,
                          isSubSyncActive: _selectedEmbeddedSubtitleIndex == null && (_showSubSyncBar || _subtitleDelayMs != 0),
                          isAudioActive: _selectedAudioTrackIndex > 0,
                          isDiagnosticsActive: _showDiagnostics,
                          isAutoSyncBusy: _autoSyncBusy,
                          onAutoSync: () => unawaited(_autoSyncSubtitles()),
                          onToggleDiagnostics: _toggleDiagnostics,
                          isEpisodesActive: _showEpisodesPanel || _showSourcesPanel,
                          hasNextEpisode: _nextEpisode != null,
                          nextEpisodeLabel: _nextEpisode == null
                              ? null : 'S${_nextEpisode!.season}E${_nextEpisode!.episode}',
                          onNextEpisode: _nextEpisode != null && !_nextEpisodeBusy
                              ? () => unawaited(_goToNextEpisode()) : null,
                          isFullscreen: isFs,
                          onToggleEpisodes: (_episodeCatalog.isNotEmpty)
                              ? _toggleEpisodesPanel
                              : null,
                          onPlayPause: () {
                            _togglePlayPause();
                          },
                          onSeek: (pos) => _player.seek(pos),
                          onSeekBack10: () {
                            _seekRelative(const Duration(seconds: -10));
                          },
                          onSeekForward10: () {
                            _seekRelative(const Duration(seconds: 10));
                          },
                          onVolumeChanged: (vol) => _applyVolume(vol),
                          onToggleMute: () => _toggleMute(),
                          onToggleAspectMenu: () => _toggleMenu('aspect'),
                          onToggleSpeedMenu: () => _toggleMenu('speed'),
                          onToggleAudioMenu: () => _toggleMenu('audio'),
                          onToggleSubtitleMenu: () => _toggleMenu('subtitle'),
                          onToggleSubSync: () {
                            if (_selectedEmbeddedSubtitleIndex != null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Subtitle sync is not supported for embedded subtitles. Please select an external subtitle.'),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                              return;
                            }
                            if (_currentSubtitlePath == null || _currentSubtitleVariant == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Please load an external subtitle to use subtitle sync.'),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                              return;
                            }
                            setState(() {
                              _showSubSyncBar = !_showSubSyncBar;
                              _activeMenu = null;
                            });
                          },
                          onToggleFullscreen: () => WindowService.instance.toggleFullscreen(),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),

          // Floating read-only diagnostics; never obscures video with a modal.
          if (_showDiagnostics && !_isLoading)
            Positioned(
              top: MediaQuery.paddingOf(context).top + 58,
              right: MediaQuery.sizeOf(context).width < 680 ? 12 : 28,
              child: PlayerDiagnosticsOverlay(
                properties: _diagnosticsProperties,
                isPlaying: _isPlaying,
                isBuffering: _player.state.buffering,
                position: _position,
                duration: _duration,
                buffered: _buffered,
                playbackRate: _playbackRate,
                sourceKind: _diagnosticsSourceKind(),
              ),
            ),

          // Floating Subtitle Menu Popover
          if (_activeMenu == 'subtitle' && !_isLoading)
            Positioned(
              bottom: MediaQuery.sizeOf(context).height < 500
                  ? 44
                  : (MediaQuery.sizeOf(context).width < 560
                      ? 60
                      : (MediaQuery.sizeOf(context).width < 680 ? 76 : 96)),
              right: MediaQuery.sizeOf(context).width < 560
                  ? 8
                  : (MediaQuery.sizeOf(context).width < 680 ? 12 : 28),
              left: MediaQuery.sizeOf(context).width < 560 ? 8 : null,
              child: Align(
                alignment: MediaQuery.sizeOf(context).width < 560
                    ? Alignment.bottomCenter
                    : Alignment.bottomRight,
                child: PlayerSubtitleMenu(
                  groups: _subtitleGroups,
                  embeddedSubtitles: _embeddedSubtitles,
                  selectedEmbeddedIndex: _selectedEmbeddedSubtitleIndex,
                  selectedVariant: _currentSubtitleVariant,
                  isSubtitleEnabled: _isSubtitleEnabled,
                  movieTitle: widget.detail?.name ?? widget.title,
                  imdbId: widget.detail?.id,
                  season: _currentEpisode?.season,
                  episode: _currentEpisode?.episode,
                  year: widget.detail?.year != null ? int.tryParse(widget.detail!.year!) : null,
                  delaySec: _subtitleDelayMs / 1000.0,
                  onSelectVariant: (v) {
                    if (v != null) unawaited(_loadSubtitle(v));
                  },
                  onSelectEmbedded: (emb) => _selectEmbeddedSubtitle(emb),
                  onToggleOff: _disableSubtitles,
                  onOpenSyncBar: () {
                    if (_selectedEmbeddedSubtitleIndex != null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Subtitle sync is not supported for embedded subtitles.'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                      return;
                    }
                    setState(() {
                      _activeMenu = null;
                      _showSubSyncBar = true;
                    });
                  },
                  onOpenStyleBar: () {
                    setState(() => _activeMenu = 'style');
                  },
                  onOpenTextSync: () {
                    if (_selectedEmbeddedSubtitleIndex != null || _currentSubtitlePath == null || _currentCues.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Speech sync requires an external subtitle file.'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                      return;
                    }
                    setState(() {
                      _activeMenu = null;
                      _showTextSyncOverlay = true;
                    });
                  },
                  onClose: () => setState(() => _activeMenu = null),
                ),
              ),
            ),

          // Floating Audio Menu Popover
          if (_activeMenu == 'audio' && !_isLoading)
            Positioned(
              bottom: MediaQuery.sizeOf(context).height < 500
                  ? 46
                  : (MediaQuery.sizeOf(context).width < 680 ? 76 : 96),
              right: MediaQuery.sizeOf(context).width < 680 ? 12 : 28,
              child: PlayerAudioMenu(
                audioTracks: _audioTracks,
                selectedIndex: _selectedAudioTrackIndex,
                delaySec: _audioDelaySec,
                onTrackSelected: (idx) {
                  unawaited(_selectAudioTrack(idx, manual: true));
                },
                onDelayChanged: (sec) {
                  setState(() => _audioDelaySec = sec);
                  try {
                    final np = _player.platform as dynamic;
                    np.setProperty('audio-delay', sec.toString());
                  } catch (_) {}
                  _showAudioHudToast('AUDIO SYNC: ${sec > 0 ? "+" : ""}${sec.toStringAsFixed(2)}s');
                },
                onClose: () => setState(() => _activeMenu = null),
              ),
            ),

          // Floating Speed Menu Popover
          if (_activeMenu == 'speed' && !_isLoading)
            Positioned(
              bottom: MediaQuery.sizeOf(context).height < 500
                  ? 46
                  : (MediaQuery.sizeOf(context).width < 680 ? 76 : 96),
              right: MediaQuery.sizeOf(context).width < 680 ? 12 : 28,
              child: PlayerSpeedMenu(
                currentRate: _playbackRate,
                onRateSelected: (rate) {
                  setState(() => _playbackRate = rate);
                  _player.setRate(rate);
                },
                onClose: () => setState(() => _activeMenu = null),
              ),
            ),

          // Floating Aspect Ratio Popover
          if (_activeMenu == 'aspect' && !_isLoading)
            Positioned(
              bottom: MediaQuery.sizeOf(context).height < 500
                  ? 46
                  : (MediaQuery.sizeOf(context).width < 680 ? 76 : 96),
              right: MediaQuery.sizeOf(context).width < 680 ? 12 : 28,
              child: PlayerAspectMenu(
                currentFit: _videoFit,
                subtitleScale: _subtitleScale,
                onFitSelected: (fit) => setState(() => _videoFit = fit),
                onSubtitleScaleChanged: _setSubtitleScale,
                onClose: () => setState(() => _activeMenu = null),
              ),
            ),

          // Floating Subtitle Appearance & Customization Modal
          if (_activeMenu == 'style' && !_isLoading)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _activeMenu = null),
                child: Container(
                  color: Colors.black54,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: GestureDetector(
                    onTap: () {}, // Prevent tap through
                    child: PlayerSubStyleModal(
                      player: _player,
                      onClose: () => setState(() => _activeMenu = null),
                    ),
                  ),
                ),
              ),
            ),

          // Top Floating Live SubSyncBar
          if (_showSubSyncBar && !_isLoading && _selectedEmbeddedSubtitleIndex == null)
            Positioned(
              top: MediaQuery.paddingOf(context).top + 16,
              left: 0,
              right: 0,
              child: SubSyncBar(
                delaySec: _subtitleDelayMs / 1000.0,
                isTextSyncAvailable: _selectedEmbeddedSubtitleIndex == null && _currentSubtitlePath != null && _currentCues.isNotEmpty,
                onDelayChanged: (sec) => _applyLiveDelay(sec),
                onEnterTextSync: () {
                  setState(() {
                    _showSubSyncBar = false;
                    _showTextSyncOverlay = true;
                  });
                },
                onClose: () {
                  setState(() => _showSubSyncBar = false);
                  _startHideControlsTimer();
                },
              ),
            ),

          // In-Player Episodes Side Panel
          if (_showEpisodesPanel && _episodeCatalog.isNotEmpty && !_isLoading)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _showEpisodesPanel = false),
                child: Container(
                  color: Colors.black.withValues(alpha: 0.45),
                  child: GestureDetector(
                    onTap: () {},
                    child: PlayerEpisodesPanel(
                      videos: _episodeCatalog,
                      currentEpisode: _currentEpisode,
                      onEpisodeSelected: _onEpisodeChosen,
                      onClose: () => setState(() => _showEpisodesPanel = false),
                    ),
                  ),
                ),
              ),
            ),

          // In-Player Sources Side Panel (Targeted Scraping & Error Recovery)
          if (_showSourcesPanel && _sourcesEpisode != null && !_isLoading)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _showSourcesPanel = false),
                child: Container(
                  color: Colors.black.withValues(alpha: 0.45),
                  child: GestureDetector(
                    onTap: () {},
                    child: PlayerSourcesPanel(
                      episode: _sourcesEpisode!,
                      detail: widget.detail,
                      currentAddonName: _currentSource.addonName,
                      errorMessage: _sourcesErrorMessage,
                      cachedSources: _cachedSourcesByEpisode['${_sourcesEpisode!.season ?? 1}:${_sourcesEpisode!.episode ?? 1}'],
                      onSourcesLoaded: (sources) {
                        _cachedSourcesByEpisode['${_sourcesEpisode!.season ?? 1}:${_sourcesEpisode!.episode ?? 1}'] = sources;
                      },
                      onPlaySource: _playNewSource,
                      onBackToEpisodes: _onBackToEpisodes,
                      onClose: () => setState(() => _showSourcesPanel = false),
                    ),
                  ),
                ),
              ),
            ),

          // Right Drawer Text Sync
          if (_showTextSyncOverlay && !_isLoading && _currentCues.isNotEmpty && _selectedEmbeddedSubtitleIndex == null)
            Positioned.fill(
              child: TextSyncOverlay(
                player: _player,
                initialCues: _currentCues,
                baseOffsetSec: _subtitleDelayMs / 1000.0,
                onClose: () {
                  setState(() => _showTextSyncOverlay = false);
                  _startHideControlsTimer();
                },
                onSave: _saveTextSyncedCues,
              ),
            ),

          // Floating Skip Button (Skip Intro, Skip Recap, Skip Credits, Skip Preview)
          if (_showSkipButton && _activeSkipSegment != null && !_isLoading && !_showTextSyncOverlay && !_showEpisodesPanel && !_showSourcesPanel)
            Positioned(
              bottom: (_showControls || _activeMenu != null)
                  ? (MediaQuery.paddingOf(context).bottom +
                      (MediaQuery.sizeOf(context).width < 680 ? 108 : 128))
                  : (MediaQuery.paddingOf(context).bottom +
                      (MediaQuery.sizeOf(context).width < 680 ? 22 : 36)),
              right: MediaQuery.sizeOf(context).width < 680 ? 16 : 28,
              child: AnimatedOpacity(
                opacity: _showSkipButton ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 250),
                child: PlayerSkipButton(
                  segment: _activeSkipSegment!,
                  autoSkip: AutomaticSkipPolicy.eligible(
                    isSeriesEpisode: _currentEpisode != null,
                    segment: _activeSkipSegment!,
                    mediaDuration: _player.state.duration,
                  ),
                  isPlaying: _isPlaying,
                  onSkip: () {
                    final segment = _activeSkipSegment;
                    if (segment == null) return;
                    if (AutomaticSkipPolicy.eligible(
                        isSeriesEpisode: _currentEpisode != null,
                        segment: segment,
                        mediaDuration: _player.state.duration)) {
                      _handleAutomaticSkipSegment(segment);
                    } else {
                      _handleSkipSegment(segment);
                    }
                  },
                  onDismiss: () {
                    final segment = _activeSkipSegment;
                    if (segment != null) _handleDismissSkipSegment(segment);
                  },
                ),
              ),
            ),

          // Center Heads-Up Volume Display (HUD)
          if (_showVolumeHud)
            Positioned.fill(
              child: IgnorePointer(
                child: _buildVolumeHud(),
              ),
            ),

          // Center Heads-Up Audio Display (HUD)
          if (_showAudioHud)
            Positioned.fill(
              child: IgnorePointer(
                child: _buildAudioHud(),
              ),
            ),
        ],
      );
  }

  Widget _buildVolumeHud() {
    final effectiveVol = _isMuted ? 0.0 : _volume;
    final isBoosting = !_isMuted && _volume > 1.001;
    final pct = (effectiveVol * 100).round();
    final boostColor = _volume > 1.75
        ? const Color(0xFFFF3D00)
        : (_volume > 1.0 ? const Color(0xFFFF8A00) : Colors.white);

    IconData volIcon;
    if (_isMuted || _volume == 0) {
      volIcon = Icons.volume_off_rounded;
    } else if (_volume > 1.0) {
      volIcon = Icons.volume_up_rounded;
    } else if (_volume < 0.5) {
      volIcon = Icons.volume_down_rounded;
    } else {
      volIcon = Icons.volume_up_rounded;
    }

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF0F1117).withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isBoosting
                ? boostColor.withValues(alpha: 0.45)
                : Colors.white.withValues(alpha: 0.15),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: isBoosting ? boostColor.withValues(alpha: 0.28) : Colors.black54,
              blurRadius: 30,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  volIcon,
                  color: isBoosting ? boostColor : Colors.white,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Text(
                  _isMuted ? 'Muted' : '$pct%',
                  style: TextStyle(
                    color: isBoosting ? boostColor : Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                if (isBoosting) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: boostColor.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: boostColor.withValues(alpha: 0.4), width: 0.8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.bolt_rounded, size: 13, color: boostColor),
                        const SizedBox(width: 2),
                        Text(
                          _volume > 1.75 ? 'MAX BOOST' : 'BOOST',
                          style: TextStyle(
                            color: boostColor,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: 140,
              height: 6,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: Stack(
                  children: [
                    Container(color: Colors.white.withValues(alpha: 0.15)),
                    FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: (effectiveVol / PlayerVolumeControl.maxVolume).clamp(0.0, 1.0),
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: isBoosting
                              ? LinearGradient(
                                  colors: [
                                    Colors.white,
                                    const Color(0xFFFF8A00),
                                    if (_volume > 1.75) const Color(0xFFFF3D00),
                                  ],
                                )
                              : null,
                          color: isBoosting ? null : Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAudioHudToast(String text) {
    _audioHudTimer?.cancel();
    setState(() {
      _audioHudText = text;
      _showAudioHud = true;
    });
    _audioHudTimer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _showAudioHud = false);
    });
  }

  Widget _buildAudioHud() {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF0F1117).withValues(alpha: 0.90),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFF7C5CFF).withValues(alpha: 0.5),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF7C5CFF).withValues(alpha: 0.25),
              blurRadius: 24,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.audiotrack_rounded,
              color: Color(0xFF00D2EF),
              size: 24,
            ),
            const SizedBox(width: 10),
            Text(
              _audioHudText,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayerBody() {
    return ValueListenableBuilder<bool>(
      valueListenable: GlassSettings.enabled,
      builder: (context, enabled, _) {
        if (enabled) {
          return LiquidGlassView(
            realTimeCapture: _showControls && !_isLoading,
            useSync: true,
            pixelRatio: 0.85,
            refreshRate: LiquidGlassRefreshRate.deviceRefreshRate,
            regionCapture: true,
            backgroundWidget: _buildBackgroundStack(),
            child: _buildControlsOverlay(),
          );
        }

        return Stack(
          fit: StackFit.expand,
          children: [
            RepaintBoundary(child: _buildBackgroundStack()),
            RepaintBoundary(child: _buildControlsOverlay()),
          ],
        );
      },
    );
  }
}
