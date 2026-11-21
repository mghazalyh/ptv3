import 'package:flutter/material.dart';

import '../../services/remote/unattended_test_activity.dart';

/// Read-only overlay: never intercepts taps, navigation or video gestures.
/// Mounted above Navigator, so the indicator survives channel route changes.
class UnattendedTestIndicator extends StatelessWidget {
  const UnattendedTestIndicator({
    super.key,
    required this.activity,
  });

  final ValueListenable<UnattendedTestSnapshot> activity;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<UnattendedTestSnapshot>(
      valueListenable: activity,
      builder: (context, status, _) {
        if (!status.isVisible) return const SizedBox.shrink();
        final completed = status.channelsDone;
        final total = status.totalChannels;
        final text = status.cancelRequested
            ? 'STOPPING LIVE TV TEST'
            : 'LIVE TV TEST RUNNING';
        return IgnorePointer(
          ignoring: true,
          child: SafeArea(
            bottom: false,
            child: Align(
              alignment: Alignment.topCenter,
              heightFactor: 1,
              child: Padding(
                padding: const EdgeInsets.only(
                    top: 6, left: 16, right: 16),
                child: Semantics(
                  label: '$text. $completed of $total channel rounds. '
                      '${status.sustainedPlaybackSessions} sustained '
                      'playback sessions.',
                  liveRegion: true,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 310),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xE6192232),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: const Color(0xFF6F9DE3), width: 1),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.science_outlined,
                              size: 16, color: Color(0xFF88B8FF)),
                          const SizedBox(width: 7),
                          Flexible(
                            child: Text(
                              text,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11, color: Colors.white,
                                fontWeight: FontWeight.w700,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ),
                          const SizedBox(width: 9),
                          Text('$completed / $total',
                            style: const TextStyle(
                              fontSize: 11, color: Colors.white,
                              fontWeight: FontWeight.w700,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ]),
                        const SizedBox(height: 5),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            minHeight: 3,
                            value: status.progress,
                            backgroundColor: const Color(0xFF384050),
                            color: const Color(0xFF88B8FF),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${status.sourcesDone} source attempts'
                          '  ·  ${status.sustainedPlaybackSessions} sustained'
                          '  ·  ${status.uploadFailures} upload errors',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFD0D5E1),
                            fontSize: 9, decoration: TextDecoration.none,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
