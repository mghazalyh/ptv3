import 'package:flutter/material.dart';
import 'player_glass.dart';

/// MPV video-signal brightness. The hardware display backlight is unchanged.
class PlayerBrightnessMenu extends StatelessWidget {
  final double brightness;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;
  final VoidCallback onClose;

  const PlayerBrightnessMenu({
    super.key,
    required this.brightness,
    required this.onChanged,
    required this.onChangeEnd,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final level = brightness.round().clamp(0, 80);
    return PlayerGlassCard(
      width: (296.0).clamp(220.0, width - 24),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.brightness_6_rounded, size: 19,
                color: PlayerTheme.accent),
            const SizedBox(width: 9),
            const Expanded(child: Text('EXTRA BRIGHTNESS',
                style: TextStyle(color: PlayerTheme.inkSubtle,
                    fontSize: 11, fontWeight: FontWeight.w700,
                    letterSpacing: 1.1))),
            PlayerIconButton(
              size: 28, iconSize: 15,
              icon: const Icon(Icons.close_rounded),
              tooltip: 'Close brightness controls',
              onPressed: onClose,
            ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: Text('Video +$level',
                key: const ValueKey('player-brightness-level'),
                style: const TextStyle(color: PlayerTheme.ink,
                    fontWeight: FontWeight.w600, fontSize: 14))),
            TextButton(
              key: const ValueKey('player-brightness-reset'),
              onPressed: level == 0 ? null : () {
                onChanged(0);
                onChangeEnd(0);
              },
              child: const Text('Reset'),
            ),
          ]),
          Slider(
            key: const ValueKey('player-brightness-slider'),
            value: brightness.clamp(0, 80).toDouble(),
            min: 0, max: 80, divisions: 20,
            label: '+$level',
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
          ),
          const Text(
            'Brightens video pixels, not the display backlight. '
            'High values may wash out highlights.',
            style: TextStyle(color: PlayerTheme.inkMuted, fontSize: 11.5),
          ),
        ],
      ),
    );
  }
}
