import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../services/player/playback_diagnostics_probe.dart';

/// Read-only, small "Stats for Nerds" panel over the current video.
class PlayerDiagnosticsOverlay extends StatelessWidget {
  final Map<String, String> properties;
  final bool isPlaying;
  final bool isBuffering;
  final Duration position;
  final Duration duration;
  final Duration? buffered;
  final double playbackRate;
  final String sourceKind;

  const PlayerDiagnosticsOverlay({
    super.key,
    required this.properties,
    required this.isPlaying,
    required this.isBuffering,
    required this.position,
    required this.duration,
    required this.buffered,
    required this.playbackRate,
    required this.sourceKind,
  });

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final width = math.min(385.0, math.max(220.0, screen.width - 24));
    final height = math.min(340.0, math.max(135.0, screen.height - 98));
    final data = properties;
    final rows = <(String, String)>[
      ('Playback', isBuffering ? 'Buffering' : (isPlaying ? 'Playing' : 'Paused')),
      ('Position', '${PlaybackDiagnosticsProbe.time(position)} / ${PlaybackDiagnosticsProbe.time(duration)}'),
      ('Buffered until', buffered == null || buffered! <= Duration.zero
          ? 'Unavailable' : PlaybackDiagnosticsProbe.time(buffered!)),
      ('Speed', '${playbackRate.toStringAsFixed(2)}×'),
      ('Source type', sourceKind),
      ('Video codec', PlaybackDiagnosticsProbe.readable(data['video-codec'])),
      ('Resolution', PlaybackDiagnosticsProbe.resolution(data)),
      ('Video FPS', PlaybackDiagnosticsProbe.frameRate(data)),
      ('Video bitrate', PlaybackDiagnosticsProbe.bitrate(data, 'video-bitrate')),
      ('Dropped frames', PlaybackDiagnosticsProbe.readable(data['frame-drop-count'])),
      ('Decoder drops', PlaybackDiagnosticsProbe.readable(data['decoder-frame-drop-count'])),
      ('Hardware decode', PlaybackDiagnosticsProbe.readable(data['hwdec-current'])),
      ('Audio codec', PlaybackDiagnosticsProbe.readable(data['audio-codec'])),
      ('Audio bitrate', PlaybackDiagnosticsProbe.bitrate(data, 'audio-bitrate')),
      ('Audio sample rate', PlaybackDiagnosticsProbe.audioSampleRate(data)),
      ('Demux cache ahead', PlaybackDiagnosticsProbe.cacheAhead(data)),
    ];
    return Semantics(
      label: 'Playback diagnostics overlay',
      child: GestureDetector(
        onTap: () {}, // Do not forward taps to the video gesture layer.
        child: Container(
          width: width,
          height: height,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: const Color(0xEB0A111B),
            border: Border.all(color: const Color(0x887FA8FF)),
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [
              BoxShadow(color: Colors.black54, blurRadius: 16, offset: Offset(0, 6)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(children: [
                Icon(Icons.analytics_outlined, color: Color(0xFF9BC2FF), size: 17),
                SizedBox(width: 7),
                Text('Playback diagnostics',
                    style: TextStyle(fontSize: 14, color: Colors.white,
                        fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 5),
              const Text('Live data · unavailable fields are not estimated',
                style: TextStyle(fontSize: 10, color: Color(0xFFB3BBCB))),
              const Divider(height: 12, color: Color(0x447D90A5)),
              Expanded(child: ListView.separated(
                padding: EdgeInsets.zero,
                itemCount: rows.length,
                separatorBuilder: (_, __) => const SizedBox(height: 5),
                itemBuilder: (context, index) {
                  final (label, value) = rows[index];
                  return Row(crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 122,
                        child: Text(label, style: const TextStyle(
                          color: Color(0xFFB0BDD3),
                          fontFamily: 'monospace', fontSize: 11))),
                      Expanded(child: Text(value,
                        maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white,
                          fontFamily: 'monospace', fontSize: 11,
                          fontWeight: FontWeight.w600))),
                    ]);
                },
              )),
            ],
          ),
        ),
      ),
    );
  }
}
