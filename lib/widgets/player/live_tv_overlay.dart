import 'package:flutter/material.dart';
import '../../services/player/live_tv/live_signal_health.dart';

/// Stays visible when transport controls disappear.
class LiveTvSignalBadge extends StatelessWidget {
  const LiveTvSignalBadge({super.key, required this.snapshot});
  final LiveSignalSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color color, String label) = switch (snapshot.level) {
      LiveSignalLevel.strong =>
        (Icons.signal_cellular_4_bar_rounded, const Color(0xFF37DC93), 'Strong'),
      LiveSignalLevel.unstable =>
        (Icons.signal_cellular_alt_2_bar_rounded, const Color(0xFFFFCE5E), 'Unstable'),
      LiveSignalLevel.critical =>
        (Icons.signal_cellular_alt_1_bar_rounded, const Color(0xFFFF705B), 'Critical'),
      LiveSignalLevel.reconnecting =>
        (Icons.sync_rounded, const Color(0xFFFFCE5E), 'Reconnecting'),
      LiveSignalLevel.unavailable =>
        (Icons.signal_cellular_connected_no_internet_0_bar_rounded,
         const Color(0xFFFF705B), 'Unavailable'),
      LiveSignalLevel.connecting =>
        (Icons.signal_cellular_alt_rounded, Colors.white70, 'Connecting'),
    };
    final bufferLabel = snapshot.bufferSeconds == null ? ''
        : ' · ${snapshot.bufferSeconds!.toStringAsFixed(0)} seconds buffered';
    return Semantics(
      label: 'Live stream health: $label$bufferLabel',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xD90C1523),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.65)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 19, color: color),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(
                color: color, fontWeight: FontWeight.w700, fontSize: 12,
              )),
              if (snapshot.bufferSeconds != null)
                Text('  ${snapshot.bufferSeconds!.toStringAsFixed(0)}s',
                  style: const TextStyle(color: Colors.white70, fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Unknown-duration network acquisition must not display fictitious percentages.
class LiveTvLoadingOverlay extends StatelessWidget {
  const LiveTvLoadingOverlay({
    super.key, required this.channelTitle,
    required this.message, required this.snapshot,
  });
  final String channelTitle;
  final String message;
  final LiveSignalSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isUnavailable = snapshot.level == LiveSignalLevel.unavailable;
    return IgnorePointer(
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: width < 560 ? width - 52 : 400),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xE8172133),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white24),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 24, vertical: 22,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.live_tv_rounded,
                    color: Colors.white, size: 30),
                  const SizedBox(height: 10),
                  Text(channelTitle,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white,
                      fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  Text(message, textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white70, fontSize: 13)),
                  const SizedBox(height: 16),
                  if (isUnavailable)
                    const Text('This stream has not delivered video. '
                      'Available channel links will be retried.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFFFFC0B5), fontSize: 11))
                  else
                    const LinearProgressIndicator(
                      minHeight: 5,
                      backgroundColor: Color(0xFF344359),
                      color: Color(0xFF6FB5FF),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
