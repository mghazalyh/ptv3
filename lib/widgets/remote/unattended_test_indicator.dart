import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../services/remote/unattended_test_activity.dart';

/// Dismissible on-device test progress; only its close button takes taps.
class UnattendedTestIndicator extends StatelessWidget {
  const UnattendedTestIndicator({
    super.key,
    required this.activity,
    this.onDismiss,
  });

  final ValueListenable<UnattendedTestSnapshot> activity;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<UnattendedTestSnapshot>(
    valueListenable: activity,
    builder: (context, status, _) {
      if (!status.isVisible) return const SizedBox.shrink();
      final native = status.totalChannels == 0;
      final title = native
          ? 'NATIVE SOURCE TEST RUNNING'
          : status.cancelRequested
              ? 'STOPPING LIVE TV TEST'
              : 'LIVE TV TEST RUNNING';
      return IgnorePointer(
        ignoring: onDismiss == null,
        child: SafeArea(
          bottom: false,
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: 1,
            child: Padding(
              padding: const EdgeInsets.only(top: 6, left: 16, right: 16),
              child: Semantics(
                label: native
                    ? 'Native source test running'
                    : '$title. ${status.channelsDone} of '
                      '${status.totalChannels} channel rounds. '
                      '${status.sustainedPlaybackSessions} sustained sessions.',
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
                          child: Text(title,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11,
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                decoration: TextDecoration.none),
                          ),
                        ),
                        if (!native) ...[
                          const SizedBox(width: 9),
                          Text(
                            '${status.channelsDone} / ${status.totalChannels}',
                            style: const TextStyle(fontSize: 11,
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                decoration: TextDecoration.none),
                          ),
                        ],
                        if (onDismiss != null) ...[
                          const SizedBox(width: 4),
                          Material(
                            type: MaterialType.transparency,
                            child: IconButton(
                            tooltip: 'Hide test indicator',
                            onPressed: onDismiss,
                            icon: const Icon(Icons.close, size: 15,
                                color: Colors.white),
                            constraints: const BoxConstraints(
                                minWidth: 28, minHeight: 28),
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                            ),
                          ),
                        ],
                      ]),
                      if (!native) ...[
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
                          '${status.sourcesDone} sources'
                          '  ·  ${status.sustainedPlaybackSessions} sustained'
                          '  ·  ${status.uploadFailures} upload errors',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFD0D5E1),
                            fontSize: 9, decoration: TextDecoration.none),
                        ),
                      ],
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
