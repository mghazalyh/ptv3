import 'package:flutter/material.dart';

/// Persistent player actions, rendered above the playback UI rather than
/// inside an auto-hiding bar or a native-video backdrop capture.
///
/// On Windows these remain discoverable after the transport controls fade.
/// The separate-window action launches an independent OS player process;
/// the mini-player action keeps the existing in-app player alive.
class PlayerWindowActions extends StatelessWidget {
  const PlayerWindowActions({
    super.key,
    required this.onStop,
    this.onSeparateWindow,
    this.onMinimize,
    this.openingSeparateWindow = false,
    this.compact = false,
  });

  final VoidCallback onStop;
  final VoidCallback? onSeparateWindow;
  final VoidCallback? onMinimize;
  final bool openingSeparateWindow;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const Key('player-window-actions'),
      color: const Color(0xEC101219),
      elevation: 12,
      shadowColor: Colors.black54,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onSeparateWindow != null) ...[
              _action(
                context: context,
                key: const Key('player-separate-window'),
                icon: openingSeparateWindow
                    ? Icons.hourglass_top_rounded
                    : Icons.open_in_new_rounded,
                label: 'Separate window',
                tooltip: 'Open a separate Windows player. Drag it to a second monitor and press F for fullscreen.',
                onPressed: openingSeparateWindow ? null : onSeparateWindow,
              ),
              const SizedBox(width: 4),
            ],
            if (onMinimize != null) ...[
              _action(
                context: context,
                key: const Key('player-mini-player'),
                icon: Icons.picture_in_picture_alt_rounded,
                label: 'Mini player',
                tooltip: 'Keep video playing while browsing PlayTorrio',
                onPressed: onMinimize,
              ),
              const SizedBox(width: 4),
            ],
            _action(
              context: context,
              key: const Key('player-stop'),
              icon: Icons.close_rounded,
              label: 'Stop',
              tooltip: 'Stop playback and close this player',
              onPressed: onStop,
              danger: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _action({
    required BuildContext context,
    required Key key,
    required IconData icon,
    required String label,
    required String tooltip,
    required VoidCallback? onPressed,
    bool danger = false,
  }) {
    final fg = danger ? const Color(0xFFFFBABE) : Colors.white;
    final buttonStyle = TextButton.styleFrom(
      foregroundColor: fg,
      disabledForegroundColor: Colors.white38,
      backgroundColor: danger
          ? const Color(0x33EF4444)
          : const Color(0x25FFFFFF),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 11 : 13,
        vertical: 11,
      ),
      minimumSize: const Size(42, 42),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );

    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 450),
      child: compact
          ? IconButton(
              key: key,
              onPressed: onPressed,
              icon: Icon(icon, size: 21, color: onPressed == null ? Colors.white38 : fg),
              style: IconButton.styleFrom(
                backgroundColor: danger
                    ? const Color(0x33EF4444)
                    : const Color(0x25FFFFFF),
                minimumSize: const Size(42, 42),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            )
          : TextButton.icon(
              key: key,
              onPressed: onPressed,
              icon: Icon(icon, size: 20),
              label: Text(
                label,
                maxLines: 1,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
              style: buttonStyle,
            ),
    );
  }
}
