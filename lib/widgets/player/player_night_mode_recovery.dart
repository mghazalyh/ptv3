import 'package:flutter/material.dart';

/// Emergency action outside the transport bar. Kept visible even when the
/// video cannot initialize and PlayerTransport is deliberately not rendered.
class PlayerNightModeRecovery extends StatelessWidget {
  final bool isRecovering;
  final VoidCallback onRetry;
  final VoidCallback? onCopyLogPath;

  const PlayerNightModeRecovery({
    super.key,
    required this.isRecovering,
    required this.onRetry,
    this.onCopyLogPath,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        heightFactor: 1,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton.icon(
          key: const ValueKey('player-night-mode-emergency-retry'),
          onPressed: isRecovering ? null : onRetry,
          icon: Icon(isRecovering
              ? Icons.hourglass_top_rounded
              : Icons.nightlight_outlined),
          label: Text(isRecovering
              ? 'Restoring normal audio...'
              : 'Turn Night Mode off and retry playback'),
            ),
            if (onCopyLogPath != null)
              TextButton.icon(
                key: const ValueKey('player-night-mode-copy-log'),
                onPressed: onCopyLogPath,
                icon: const Icon(Icons.copy_outlined),
                label: const Text('Copy diagnostic log path'),
              ),
          ],
        ),
      ),
    );
  }
}
