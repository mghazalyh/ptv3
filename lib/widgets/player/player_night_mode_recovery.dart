import 'package:flutter/material.dart';

/// Emergency action outside the transport bar. Kept visible even when the
/// video cannot initialize and PlayerTransport is deliberately not rendered.
class PlayerNightModeRecovery extends StatelessWidget {
  final bool isRecovering;
  final VoidCallback onRetry;

  const PlayerNightModeRecovery({
    super.key,
    required this.isRecovering,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        heightFactor: 1,
        child: FilledButton.icon(
          key: const ValueKey('player-night-mode-emergency-retry'),
          onPressed: isRecovering ? null : onRetry,
          icon: Icon(isRecovering
              ? Icons.hourglass_top_rounded
              : Icons.nightlight_outlined),
          label: Text(isRecovering
              ? 'Restoring normal audio...'
              : 'Turn Night Mode off and retry playback'),
        ),
      ),
    );
  }
}
