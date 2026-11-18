import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/player/playback_diagnostics_probe.dart';

/// Read-only player diagnostics with decoder-verified quality information.
/// Addon labels are displayed separately and never treated as proof of 4K.
class PlayerDiagnosticsOverlay extends StatelessWidget {
  final Map<String, String> properties;
  final bool isPlaying;
  final bool isBuffering;
  final Duration position;
  final Duration duration;
  final Duration? buffered;
  final double playbackRate;
  final String sourceKind;
  final String? sourceAdvertisedQuality;
  final String? sourceProvider;
  final double? sourceSizeBytes;
  final String? selectedAudioLanguage;
  final String? selectedAudioTitle;
  final int? selectedAudioChannelCount;

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
    this.sourceAdvertisedQuality,
    this.sourceProvider,
    this.sourceSizeBytes,
    this.selectedAudioLanguage,
    this.selectedAudioTitle,
    this.selectedAudioChannelCount,
  });

  static const _muted = Color(0xFFB6C6DA);
  static const _accent = Color(0xFF9BC2FF);
  static const _background = Color(0xF408111C);

  static Widget _section(String title) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 6),
    child: Text(title.toUpperCase(),
      style: const TextStyle(color: _accent, fontSize: 10,
        fontWeight: FontWeight.w800, letterSpacing: 1.1)),
  );

  static Widget _detail(String label, String value, {bool emphasize = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 144,
            child: Text(label, style: const TextStyle(
              color: _muted, fontSize: 11))),
          Expanded(child: Text(value,
            softWrap: true, maxLines: 4, overflow: TextOverflow.ellipsis,
            style: TextStyle(color: emphasize
                ? const Color(0xFFACE6CE) : Colors.white,
              fontSize: 11, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  static String _sourceSize(double? bytes) {
    if (bytes == null || !bytes.isFinite || bytes <= 0 ||
        bytes >= 1e14) return 'Unavailable';
    if (bytes >= 1073741824) {
      return (bytes / 1073741824).toStringAsFixed(2) + ' GiB (reported)';
    }
    return (bytes / 1048576).toStringAsFixed(1) + ' MiB (reported)';
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final width = math.min(465.0, math.max(220.0, screen.width - 24));
    final height = math.min(520.0, math.max(175.0, screen.height - 110));
    final quality = PlaybackDiagnosticsProbe.qualityTier(properties);
    final fourK = PlaybackDiagnosticsProbe.fourKStatus(properties);
    final true4K = fourK == '4K-class decoded video';
    final videoBitrate = PlaybackDiagnosticsProbe.bitrate(
      properties, 'video-bitrate');
    final advertised = sourceAdvertisedQuality?.trim();
    final declared4K = advertised?.toLowerCase() == '4k';
    final hasMismatch = declared4K &&
        PlaybackDiagnosticsProbe.dimensions(properties) != null && !true4K;
    final dynamicRange = PlaybackDiagnosticsProbe.dynamicRange(properties);
    final audioLanguage = PlaybackDiagnosticsProbe.audioLanguage(properties,
      selectedLanguage: selectedAudioLanguage);

    return Semantics(
      label: 'Playback diagnostics overlay',
      child: GestureDetector(
        onTap: () {}, // Do not forward taps to the movie gesture layer.
        child: Container(
          width: width,
          height: height,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: _background,
            border: Border.all(color: const Color(0x887FA8FF)),
            borderRadius: BorderRadius.circular(14),
            boxShadow: const [
              BoxShadow(color: Colors.black54, blurRadius: 18,
                offset: Offset(0, 7)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(children: [
                Icon(Icons.analytics_outlined, color: _accent, size: 18),
                SizedBox(width: 8),
                Expanded(child: Text('Playback diagnostics',
                  style: TextStyle(fontSize: 15, color: Colors.white,
                    fontWeight: FontWeight.w800))),
              ]),
              const SizedBox(height: 4),
              const Text(
                'Decoded stream details · missing fields are not guessed',
                style: TextStyle(fontSize: 10, color: _muted),
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: true4K
                      ? const Color(0x2430C8A8)
                      : const Color(0x223B82E3),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: true4K
                      ? const Color(0x6653D9BE)
                      : const Color(0x665A9AF7)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('ACTUAL VIDEO QUALITY',
                      style: TextStyle(color: _muted, fontSize: 9,
                        fontWeight: FontWeight.w800, letterSpacing: 1)),
                    const SizedBox(height: 3),
                    Text(quality, style: const TextStyle(
                      color: Colors.white, fontSize: 19,
                      fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(fourK, style: TextStyle(
                      color: true4K ? const Color(0xFF96EBD8)
                          : const Color(0xFFBAD7FF),
                      fontSize: 11, fontWeight: FontWeight.w700)),
                    if (hasMismatch) ...[
                      const SizedBox(height: 5),
                      const Text('Warning: addon advertises 4K, but decoded video is below 4K.',
                        style: TextStyle(color: Color(0xFFFFCC88),
                          fontSize: 10)),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: Scrollbar(
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      _section('Video'),
                      _detail('Resolution',
                        PlaybackDiagnosticsProbe.resolution(properties)),
                      _detail('Video codec',
                        PlaybackDiagnosticsProbe.videoCodec(properties)),
                      _detail('HDR / SDR', dynamicRange),
                      _detail('Color depth',
                        PlaybackDiagnosticsProbe.colorDepth(properties)),
                      _detail('Color primaries',
                        PlaybackDiagnosticsProbe.colorPrimaries(properties)),
                      _detail('Pixel format',
                        PlaybackDiagnosticsProbe.pixelFormat(properties)),
                      _detail('Frame rate',
                        PlaybackDiagnosticsProbe.frameRate(properties)),
                      _detail('Video bitrate', videoBitrate),
                      _detail('Bitrate indication',
                        PlaybackDiagnosticsProbe.bitrateIndication(properties)),
                      const Padding(
                        padding: EdgeInsets.only(top: 3, bottom: 2),
                        child: Text('Bitrate indicates compression, not guaranteed picture quality.',
                          style: TextStyle(color: _muted,
                            fontSize: 9, fontStyle: FontStyle.italic)),
                      ),
                      _section('Audio'),
                      _detail('Audio codec',
                        PlaybackDiagnosticsProbe.audioCodec(properties)),
                      _detail('Audio language', audioLanguage),
                      _detail('Channels', PlaybackDiagnosticsProbe.audioChannels(
                        properties,
                        selectedChannelCount: selectedAudioChannelCount)),
                      _detail('Audio track', selectedAudioTitle == null
                          ? PlaybackDiagnosticsProbe.readable(
                              properties['current-tracks/audio/title'])
                          : PlaybackDiagnosticsProbe.readable(selectedAudioTitle)),
                      _detail('Track ID',
                        PlaybackDiagnosticsProbe.selectedTrack(properties)),
                      _detail('Audio bitrate',
                        PlaybackDiagnosticsProbe.bitrate(properties, 'audio-bitrate')),
                      _detail('Sample rate',
                        PlaybackDiagnosticsProbe.audioSampleRate(properties)),
                      _section('Playback health'),
                      _detail('Status', isBuffering ? 'Buffering'
                          : (isPlaying ? 'Playing' : 'Paused'), emphasize: isPlaying && !isBuffering),
                      _detail('Position',
                        PlaybackDiagnosticsProbe.time(position) + ' / ' +
                        PlaybackDiagnosticsProbe.time(duration)),
                      _detail('Buffered until', buffered == null ||
                          buffered! <= Duration.zero ? 'Unavailable'
                          : PlaybackDiagnosticsProbe.time(buffered!)),
                      _detail('Buffer ahead',
                        PlaybackDiagnosticsProbe.bufferingAhead(position, buffered)),
                      _detail('Demux cache ahead',
                        PlaybackDiagnosticsProbe.cacheAhead(properties)),
                      _detail('A/V synchronization',
                        PlaybackDiagnosticsProbe.avSync(properties)),
                      _detail('Playback speed', playbackRate.toStringAsFixed(2) + '×'),
                      _detail('Dropped frames',
                        PlaybackDiagnosticsProbe.readable(properties['frame-drop-count'])),
                      _detail('Decoder drops',
                        PlaybackDiagnosticsProbe.readable(
                          properties['decoder-frame-drop-count'])),
                      _detail('Delayed frames',
                        PlaybackDiagnosticsProbe.readable(
                          properties['vo-delayed-frame-count'])),
                      _detail('Hardware decode',
                        PlaybackDiagnosticsProbe.readable(properties['hwdec-current'])),
                      _section('Source'),
                      _detail('Source type', sourceKind),
                      if (sourceProvider != null && sourceProvider!.isNotEmpty)
                        _detail('Addon', sourceProvider!),
                      _detail('Advertised quality',
                        advertised == null || advertised.isEmpty
                            ? 'Not specified' : advertised),
                      _detail('Reported file size', _sourceSize(sourceSizeBytes)),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
