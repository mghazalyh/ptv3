import 'package:flutter/material.dart';

import '../../services/player/player_resolution_selector.dart';
import 'player_glass.dart';

/// Displays only resolutions actually advertised by the current episode's
/// discovered sources. Playback can later verify the decoded resolution.
class PlayerResolutionMenu extends StatelessWidget {
  final List<PlayerResolutionChoice> resolutions;
  final String? currentResolution;
  final bool isDiscovering;
  final bool isSwitching;
  final ValueChanged<PlayerResolutionChoice> onSelected;
  final VoidCallback onClose;

  const PlayerResolutionMenu({
    super.key,
    required this.resolutions,
    required this.currentResolution,
    required this.isDiscovering,
    required this.isSwitching,
    required this.onSelected,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final availableWidth = MediaQuery.sizeOf(context).width;
    final availableHeight = MediaQuery.sizeOf(context).height;
    return PlayerGlassCard(
      width: (335.0).clamp(220.0, availableWidth - 24),
      padding: const EdgeInsets.all(12),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: (availableHeight - 160).clamp(155.0, 410.0),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.high_quality_rounded,
                  color: PlayerTheme.accent, size: 18),
              const SizedBox(width: 7),
              const Expanded(
                child: Text('STREAM RESOLUTION',
                    style: TextStyle(
                      color: PlayerTheme.ink,
                      fontSize: 12,
                      letterSpacing: 0.9,
                      fontWeight: FontWeight.w700,
                    )),
              ),
              PlayerIconButton(
                size: 28,
                iconSize: 15,
                icon: const Icon(Icons.close_rounded),
                tooltip: 'Close resolution picker',
                onPressed: onClose,
              ),
            ]),
            const SizedBox(height: 4),
            const Text(
              'Switch sources without restarting this episode.',
              style: TextStyle(color: PlayerTheme.inkMuted, fontSize: 11),
            ),
            if (isDiscovering) ...[
              const SizedBox(height: 10),
              const LinearProgressIndicator(minHeight: 2),
            ],
            const SizedBox(height: 8),
            if (resolutions.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                    vertical: 18, horizontal: 8),
                child: Text(
                  isDiscovering
                      ? 'Searching installed addons for available qualities…'
                      : 'No playable sources with known resolution were found.',
                  style: const TextStyle(
                    color: PlayerTheme.inkMuted, fontSize: 12),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: resolutions.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: 4),
                  itemBuilder: (context, index) {
                    final choice = resolutions[index];
                    final current = currentResolution == choice.resolution;
                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        key: ValueKey('stream-resolution-${choice.resolution}'),
                        borderRadius: BorderRadius.circular(10),
                        onTap: isSwitching ? null : () => onSelected(choice),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 9),
                          decoration: BoxDecoration(
                            color: current
                                ? PlayerTheme.raised
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: current
                                  ? PlayerTheme.edge
                                  : Colors.transparent,
                            ),
                          ),
                          child: Row(children: [
                            Container(
                              constraints: const BoxConstraints(minWidth: 65),
                              child: Text(choice.resolution,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: current
                                      ? PlayerTheme.accent
                                      : PlayerTheme.ink,
                                )),
                            ),
                            const SizedBox(width: 8),
                            Expanded(child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  choice.source.addonName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: PlayerTheme.ink, fontSize: 11,
                                      fontWeight: FontWeight.w600),
                                ),
                                Text(
                                  '${choice.sourceCount} ranked source${choice.sourceCount == 1 ? "" : "s"}',
                                  style: const TextStyle(
                                      color: PlayerTheme.inkMuted, fontSize: 10),
                                ),
                              ],
                            )),
                            if (current)
                              const Padding(
                                padding: EdgeInsets.only(left: 7),
                                child: Icon(Icons.check_circle_rounded,
                                    color: PlayerTheme.accent, size: 18),
                              )
                            else
                              const Icon(Icons.chevron_right_rounded,
                                  color: PlayerTheme.inkMuted, size: 19),
                          ]),
                        ),
                      ),
                    );
                  },
                ),
              ),
            if (isSwitching)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Opening selected quality…',
                    style: TextStyle(
                        fontSize: 11, color: PlayerTheme.inkMuted)),
              ),
            const SizedBox(height: 9),
            const Divider(color: PlayerTheme.edgeSoft, height: 1),
            const SizedBox(height: 7),
            const Text(
              'Qualities come from addon release metadata. Actual decoded resolution is shown in Playback diagnostics.',
              style: TextStyle(color: PlayerTheme.inkMuted, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}
