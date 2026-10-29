import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import '../../models/player/skip_segment_model.dart';
import '../../services/player/subtitle_auto_sync_platform.dart';
import '../../services/theme/glass_settings.dart';
import 'player_glass.dart';
import 'player_seek_bar.dart';
import 'player_volume_control.dart';

/// Full bottom transport bar containing timeline scrubber, play controls, and menu triggers.
class PlayerTransport extends StatelessWidget {
  final bool isPlaying;
  final Duration position;
  final Duration duration;
  final Duration? buffered;
  final ValueListenable<Duration>? positionListenable;
  final ValueListenable<Duration?>? bufferedListenable;
  final List<MediaSkipSegment> skipSegments;
  final double volume;
  final bool isMuted;
  final double playbackRate;
  final bool isSubtitlesActive;
  final bool isSubSyncActive;
  final bool isAudioActive;
  final bool isNightModeEnabled;
  final double extraBrightness;
  final bool isBrightnessMenuActive;
  final bool isDiagnosticsActive;
  final bool isAutoSyncBusy;
  final bool isEpisodesActive;
  final bool isFullscreen;
  final bool hasPrevEpisode;
  final bool hasNextEpisode;
  final String? nextEpisodeLabel;

  // Actions
  final VoidCallback onPlayPause;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onSeekBack10;
  final VoidCallback onSeekForward10;
  final ValueChanged<double> onVolumeChanged;
  final VoidCallback onToggleMute;
  final VoidCallback? onToggleEpisodes;
  final VoidCallback onToggleAspectMenu;
  final VoidCallback onToggleSpeedMenu;
  final VoidCallback onToggleAudioMenu;
  final VoidCallback? onToggleNightMode;
  final VoidCallback? onToggleBrightnessMenu;
  final VoidCallback? onToggleDiagnostics;
  final VoidCallback? onAutoSync;
  final VoidCallback onToggleSubtitleMenu;
  final VoidCallback onToggleSubSync;
  final VoidCallback onToggleFullscreen;
  final VoidCallback? onPrevEpisode;
  final VoidCallback? onNextEpisode;
  final ValueChanged<bool>? onScrubbingChanged;

  const PlayerTransport({
    super.key,
    required this.isPlaying,
    required this.position,
    required this.duration,
    this.buffered,
    this.positionListenable,
    this.bufferedListenable,
    this.skipSegments = const [],
    required this.volume,
    required this.isMuted,
    required this.playbackRate,
    required this.isSubtitlesActive,
    required this.isSubSyncActive,
    required this.isAudioActive,
    this.isNightModeEnabled = false,
    this.extraBrightness = 0,
    this.isBrightnessMenuActive = false,
    this.isDiagnosticsActive = false,
    this.isAutoSyncBusy = false,
    this.isEpisodesActive = false,
    required this.isFullscreen,
    this.hasPrevEpisode = false,
    this.hasNextEpisode = false,
    this.nextEpisodeLabel,
    required this.onPlayPause,
    required this.onSeek,
    required this.onSeekBack10,
    required this.onSeekForward10,
    required this.onVolumeChanged,
    required this.onToggleMute,
    this.onToggleEpisodes,
    required this.onToggleAspectMenu,
    required this.onToggleSpeedMenu,
    required this.onToggleAudioMenu,
    this.onToggleNightMode,
    this.onToggleBrightnessMenu,
    this.onToggleDiagnostics,
    this.onAutoSync,
    required this.onToggleSubtitleMenu,
    required this.onToggleSubSync,
    required this.onToggleFullscreen,
    this.onPrevEpisode,
    this.onNextEpisode,
    this.onScrubbingChanged,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isCompact = screenWidth < 680;
    final isDesktop = !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
    final btnSize = isCompact ? 36.0 : 42.0;
    final btnIconSize = isCompact ? 20.0 : 22.0;
    final playBtnSize = isCompact ? 46.0 : 54.0;
    final gap = isCompact ? 2.0 : 4.0;

    return Container(
      padding: EdgeInsets.fromLTRB(
        isCompact ? 14 : 28,
        isCompact ? 32 : 48,
        isCompact ? 14 : 28,
        isCompact ? 14 : 24,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withValues(alpha: 0.85),
            Colors.black.withValues(alpha: 0.40),
            Colors.transparent,
          ],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Seek Bar & Timers
          PlayerSeekBar(
            position: position,
            duration: duration,
            buffered: buffered,
            positionListenable: positionListenable,
            bufferedListenable: bufferedListenable,
            skipSegments: skipSegments,
            onSeek: onSeek,
            onScrubbingChanged: onScrubbingChanged,
          ),

          SizedBox(height: isCompact ? 8 : 14),

          // A labeled, dedicated next-episode control is visible even in
          // compact/narrow Windows windows. It is not hidden in a tooltip.
          if (hasNextEpisode) ...[
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                key: const ValueKey('player-next-episode'),
                onPressed: onNextEpisode,
                icon: const Icon(Icons.skip_next_rounded, size: 22),
                label: Text(nextEpisodeLabel == null
                    ? 'Next Episode'
                    : 'Next Episode · $nextEpisodeLabel'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFF6F2FF),
                  backgroundColor: const Color(0xFF4933A0),
                  side: const BorderSide(color: Color(0xFF977BFF)),
                  padding: EdgeInsets.symmetric(
                    horizontal: isCompact ? 12 : 18,
                    vertical: isCompact ? 8 : 10,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],

          // Bottom Controls Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Left Group: Play/Pause, Rewind 10, FastForward 10, Volume Control
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Frosted/Liquid Glass Play/Pause Button
                  _PlayerPlayPauseButton(
                    isPlaying: isPlaying,
                    size: playBtnSize,
                    iconSize: isCompact ? 28 : 34,
                    onTap: onPlayPause,
                  ),

                  SizedBox(width: isCompact ? 8 : 14),

                  // Seek Back 10s
                  PlayerIconButton(
                    size: btnSize,
                    iconSize: btnIconSize + 2,
                    icon: const Icon(Icons.replay_10_rounded),
                    tooltip: 'Seek -10s',
                    onPressed: onSeekBack10,
                  ),

                  SizedBox(width: gap),

                  // Seek Forward 10s
                  PlayerIconButton(
                    size: btnSize,
                    iconSize: btnIconSize + 2,
                    icon: const Icon(Icons.forward_10_rounded),
                    tooltip: 'Seek +10s',
                    onPressed: onSeekForward10,
                  ),

                  // Volume Control (Full slider on wide screens, Mute button on compact)
                  if (!isCompact) ...[
                    const SizedBox(width: 10),
                    PlayerVolumeControl(
                      volume: volume,
                      isMuted: isMuted,
                      onVolumeChanged: onVolumeChanged,
                      onToggleMute: onToggleMute,
                    ),
                  ] else ...[
                    SizedBox(width: gap),
                    PlayerIconButton(
                      size: btnSize,
                      iconSize: btnIconSize,
                      icon: Icon(
                        isMuted || volume == 0
                            ? Icons.volume_off_rounded
                            : (volume > 1.0 ? Icons.volume_up_rounded : Icons.volume_down_rounded),
                      ),
                      tooltip: isMuted ? 'Unmute' : 'Mute',
                      onPressed: onToggleMute,
                    ),
                  ],
                ],
              ),

              // Center Group: optional previous-episode shortcut.
              if (!isCompact && hasPrevEpisode)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (hasPrevEpisode && onPrevEpisode != null)
                      PlayerIconButton(
                        size: 40,
                        iconSize: 22,
                        icon: const Icon(Icons.skip_previous_rounded),
                        tooltip: 'Previous Episode',
                        onPressed: onPrevEpisode,
                      ),
                  ],
                ),

              // Right Group: Aspect, Speed, Audio, Subtitles, SubSync, Fullscreen
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Episodes Menu Trigger (for TV Shows)
                  if (onToggleEpisodes != null) ...[
                    PlayerIconButton(
                      size: btnSize,
                      iconSize: btnIconSize,
                      icon: const Icon(Icons.video_library_rounded),
                      tooltip: 'Episodes',
                      active: isEpisodesActive,
                      activeColor: PlayerTheme.accent,
                      onPressed: onToggleEpisodes,
                    ),
                    SizedBox(width: gap),
                  ],

                  // Aspect Ratio Menu Trigger
                  PlayerIconButton(
                    size: btnSize,
                    iconSize: btnIconSize,
                    icon: const Icon(Icons.aspect_ratio_rounded),
                    tooltip: 'Aspect Ratio',
                    onPressed: onToggleAspectMenu,
                  ),

                  SizedBox(width: gap),

                  // Playback Speed Menu Trigger
                  PlayerIconButton(
                    size: btnSize,
                    iconSize: btnIconSize,
                    icon: const Icon(Icons.speed_rounded),
                    tooltip: 'Playback Speed',
                    showActiveBadge: playbackRate != 1.0,
                    onPressed: onToggleSpeedMenu,
                  ),

                  SizedBox(width: gap),

                  // Audio Menu Trigger
                  PlayerIconButton(
                    size: btnSize,
                    iconSize: btnIconSize,
                    icon: const Icon(Icons.audiotrack_rounded),
                    tooltip: 'Audio Tracks',
                    onPressed: onToggleAudioMenu,
                  ),

                  SizedBox(width: gap),

                  // Compact persistent Night Mode toggle, beside audio/subtitles.
                   if (onToggleNightMode != null) ...[
                     PlayerIconButton(
                       key: const ValueKey('player-night-mode'),
                       size: isCompact ? 30 : 32,
                       iconSize: isCompact ? 16 : 18,
                       icon: const Icon(Icons.nightlight_round),
                       tooltip: isNightModeEnabled
                           ? 'Night Mode On — tap to disable'
                           : 'Night Mode — soften loud scenes and lift dialogue',
                       active: isNightModeEnabled,
                       activeColor: PlayerTheme.accent,
                       onPressed: onToggleNightMode!,
                     ),
                     SizedBox(width: gap),
                   ],

                   // Brightness changes the video, not device backlight.
                   if (onToggleBrightnessMenu != null) ...[
                     PlayerIconButton(
                       key: const ValueKey('player-extra-brightness'),
                       size: isCompact ? 30 : 32,
                       iconSize: isCompact ? 16 : 18,
                       icon: const Icon(Icons.brightness_6_rounded),
                       tooltip: 'Extra Brightness · +${extraBrightness.round()}',
                       active: isBrightnessMenuActive || extraBrightness > 0,
                       activeColor: PlayerTheme.accent,
                       onPressed: onToggleBrightnessMenu!,
                     ),
                     SizedBox(width: gap),
                   ],

                   // Compact playback diagnostics toggle, alongside audio/subtitles.
                  if (onToggleDiagnostics != null) ...[
                    PlayerIconButton(
                      size: isCompact ? 30 : 32,
                      iconSize: isCompact ? 15 : 17,
                      icon: const Icon(Icons.analytics_outlined),
                      tooltip: 'Playback diagnostics',
                      active: isDiagnosticsActive,
                      activeColor: PlayerTheme.accent,
                      onPressed: onToggleDiagnostics!,
                    ),
                    SizedBox(width: gap),
                  ],

                  // Separate one-tap subtitle matching action, beside diagnostics.
                  if (onAutoSync != null) ...[
                    PlayerIconButton(
                      size: isCompact ? 30 : 32,
                      iconSize: isCompact ? 15 : 17,
                      icon: Icon(isAutoSyncBusy ? Icons.hourglass_top_rounded : Icons.sync_rounded),
                      tooltip: SubtitleAutoSyncPlatform.tooltipFor(
                        isIOS: !kIsWeb && Platform.isIOS,
                        isWindows: !kIsWeb && Platform.isWindows,
                      ),
                      active: isAutoSyncBusy,
                      activeColor: PlayerTheme.accent,
                      onPressed: onAutoSync!,
                    ),
                    SizedBox(width: gap),
                  ],

                  // Subtitles Menu Trigger
                  PlayerIconButton(
                    size: btnSize,
                    iconSize: btnIconSize,
                    icon: const Icon(Icons.subtitles_rounded),
                    tooltip: 'Subtitles',
                    showActiveBadge: isSubtitlesActive,
                    badgeColor: const Color(0xFF10B981), // Emerald
                    onPressed: onToggleSubtitleMenu,
                  ),

                  SizedBox(width: gap),

                  // Subtitle Sync Trigger
                  PlayerIconButton(
                    size: btnSize,
                    iconSize: btnIconSize,
                    icon: const Icon(Icons.tune_rounded),
                    tooltip: 'Subtitle Sync',
                    active: isSubSyncActive,
                    activeColor: PlayerTheme.accent,
                    onPressed: onToggleSubSync,
                  ),

                  // Fullscreen Button (Desktop only)
                  if (isDesktop) ...[
                    SizedBox(width: gap),
                    PlayerIconButton(
                      size: btnSize,
                      iconSize: btnIconSize,
                      icon: Icon(
                        isFullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                      ),
                      tooltip: isFullscreen ? 'Exit Fullscreen' : 'Fullscreen',
                      onPressed: onToggleFullscreen,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PlayerPlayPauseButton extends StatefulWidget {
  final bool isPlaying;
  final double size;
  final double iconSize;
  final VoidCallback onTap;

  const _PlayerPlayPauseButton({
    required this.isPlaying,
    required this.size,
    required this.iconSize,
    required this.onTap,
  });

  @override
  State<_PlayerPlayPauseButton> createState() => _PlayerPlayPauseButtonState();
}

class _PlayerPlayPauseButtonState extends State<_PlayerPlayPauseButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: GlassSettings.enabled,
      builder: (context, glassEnabled, _) {
        return ValueListenableBuilder<int>(
          valueListenable: GlassSettings.styleRevision,
          builder: (context, _, __) {
            final hoverScaleVal = glassEnabled ? GlassSettings.hoverScale.value : 1.0;
            final effectiveScale = _hovered ? hoverScaleVal : 1.0;

            final iconWidget = Icon(
              widget.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: Colors.white,
              size: widget.iconSize,
            );

            Widget body;
            if (glassEnabled) {
              final style = GlassSettings.createButtonGlassStyle(
                cornerRadius: widget.size / 2,
                customColor: _hovered ? const Color(0x45FFFFFF) : const Color(0x28FFFFFF),
              );

              body = RepaintBoundary(
                child: LiquidGlassLens(
                  style: style,
                  useImpellerBackdrop: true,
                  child: Container(
                    width: widget.size,
                    height: widget.size,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x66000000),
                          offset: Offset(0, 4),
                          blurRadius: 16,
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: iconWidget,
                  ),
                ),
              );
            } else {
              body = AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  color: _hovered
                      ? Colors.white.withValues(alpha: 0.28)
                      : Colors.white.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.25),
                    width: 1.2,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x66000000),
                      offset: Offset(0, 4),
                      blurRadius: 16,
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: iconWidget,
              );
            }

            return MouseRegion(
              cursor: SystemMouseCursors.click,
              onEnter: (_) => setState(() => _hovered = true),
              onExit: (_) => setState(() => _hovered = false),
              child: GestureDetector(
                onTap: widget.onTap,
                child: AnimatedScale(
                  scale: effectiveScale,
                  duration: const Duration(milliseconds: 140),
                  curve: Curves.easeOutCubic,
                  child: body,
                ),
              ),
            );
          },
        );
      },
    );
  }
}
