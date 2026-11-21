import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

/// Reduces an MPV screenshot to a bounded, standard PNG for private visual
/// inspection. Never embeds source URLs, HTTP headers, addon configuration,
/// player context, tokens or the raw native-resolution screenshot.
abstract final class IosRemoteVisualFrameEncoder {
  static const maxFrameBytes = 64000;

  static Future<Uint8List?> encode(Uint8List screenshot) async {
    if (screenshot.isEmpty || screenshot.length > 8 * 1024 * 1024) {
      return null;
    }
    ui.Codec? codec;
    ui.Image? original;
    try {
      codec = await ui.instantiateImageCodec(screenshot);
      final frame = await codec.getNextFrame();
      original = frame.image;
      if (original.width <= 0 || original.height <= 0) return null;

      for (final size in const <(int, int)>[
        (256, 144), (192, 108), (144, 81),
      ]) {
        final ratio = math.min(
          size.$1 / original.width, size.$2 / original.height,
        );
        final width = math.max(1, (original.width * ratio).floor());
        final height = math.max(1, (original.height * ratio).floor());
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder);
        canvas.drawImageRect(
          original,
          ui.Rect.fromLTWH(0, 0,
              original.width.toDouble(), original.height.toDouble()),
          ui.Rect.fromLTWH(0, 0,
              width.toDouble(), height.toDouble()),
          ui.Paint()..filterQuality = ui.FilterQuality.medium,
        );
        final picture = recorder.endRecording();
        ui.Image? reduced;
        try {
          reduced = await picture.toImage(width, height);
          final data = await reduced.toByteData(
              format: ui.ImageByteFormat.png);
          if (data == null) continue;
          final png = data.buffer.asUint8List(
              data.offsetInBytes, data.lengthInBytes);
          if (isBoundedPng(png)) return Uint8List.fromList(png);
        } finally {
          reduced?.dispose();
          picture.dispose();
        }
      }
    } catch (error) {
      debugPrint('[IosRemoteVisualFrameEncoder] Encode: '
          '${error.runtimeType}');
    } finally {
      original?.dispose();
      codec?.dispose();
    }
    return null;
  }

  static bool isBoundedPng(Uint8List bytes) {
    if (bytes.length < 32 || bytes.length > maxFrameBytes) return false;
    const signature = <int>[137, 80, 78, 71, 13, 10, 26, 10];
    for (var i = 0; i < signature.length; i++) {
      if (bytes[i] != signature[i]) return false;
    }
    return true;
  }
}
