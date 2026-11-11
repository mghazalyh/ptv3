import 'package:flutter/material.dart';
import 'player_glass.dart';

/// Manual 0–100% playback gain control.
/// Hardware volume keys belong to Windows; mouse wheel never changes gain.
class PlayerVolumeControl extends StatefulWidget {
  final double volume;
  final bool isMuted;
  final ValueChanged<double> onVolumeChanged;
  final VoidCallback onToggleMute;

  static const double maxVolume = 1.0;

  const PlayerVolumeControl({
    super.key,
    required this.volume,
    required this.isMuted,
    required this.onVolumeChanged,
    required this.onToggleMute,
  });

  @override
  State<PlayerVolumeControl> createState() => _PlayerVolumeControlState();
}

class _PlayerVolumeControlState extends State<PlayerVolumeControl> {
  static const double _trackWidth = 96.0;
  bool _isHovered = false;

  IconData _volumeIcon() {
    if (widget.isMuted || widget.volume <= 0) {
      return Icons.volume_off_rounded;
    }
    return widget.volume < 0.5
        ? Icons.volume_down_rounded : Icons.volume_up_rounded;
  }

  void _onPosition(double x) {
    final fraction = (x / _trackWidth).clamp(0.0, 1.0);
    widget.onVolumeChanged((fraction * 100).round() / 100.0);
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.isMuted ? 0.0 : widget.volume.clamp(0.0, 1.0);
    final percent = (current * 100).round();
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PlayerIconButton(
            size: 40,
            iconSize: 22,
            icon: Icon(_volumeIcon(),
                color: widget.isMuted ? PlayerTheme.inkSubtle : Colors.white),
            tooltip: widget.isMuted ? 'Unmute' : 'Mute',
            onPressed: widget.onToggleMute,
          ),
          const SizedBox(width: 4),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: (e) => _onPosition(e.localPosition.dx),
            onTapDown: (e) => _onPosition(e.localPosition.dx),
            child: SizedBox(
              width: _trackWidth,
              height: 32,
              child: Center(
                child: SizedBox(
                  width: _trackWidth,
                  height: 18,
                  child: Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      Container(
                        width: _trackWidth,
                        height: 6,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                      Container(
                        width: _trackWidth * current,
                        height: 6,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.90),
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                      Positioned(
                        left: (_trackWidth * current - 6)
                            .clamp(0.0, _trackWidth - 12),
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black54,
                                blurRadius: 4,
                                offset: Offset(0, 1),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_isHovered) ...[
            const SizedBox(width: 6),
            SizedBox(
              width: 42,
              child: Text(
                '$percent%',
                style: const TextStyle(
                  color: PlayerTheme.inkMuted,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
