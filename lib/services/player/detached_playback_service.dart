import 'dart:convert';
import 'dart:io';

import '../../models/stream/stream_model.dart';

/// Windows handoff: creates another PlayTorrio process/window. The main
/// library browser stays open and the viewer can be moved to another monitor.
/// Transfer is via a one-time UTF-8 file, not an exposed URL command argument.
class DetachedPlaybackRequest {
  const DetachedPlaybackRequest({
    required this.title, required this.url, required this.position,
    required this.headers,
  });
  final String title;
  final String url;
  final Duration position;
  final Map<String, String> headers;

  Map<String, dynamic> toJson() => {
    'title': title, 'url': url, 'positionMs': position.inMilliseconds,
    'headers': headers,
  };

  factory DetachedPlaybackRequest.fromJson(Map<String, dynamic> json) =>
      DetachedPlaybackRequest(
        title: json['title']?.toString() ?? 'PlayTorrio Player',
        url: json['url'] as String,
        position: Duration(milliseconds: json['positionMs'] as int? ?? 0),
        headers: (json['headers'] as Map? ?? {})
            .map((k, v) => MapEntry(k.toString(), v.toString())),
      );

  StreamSource toSource() => StreamSource.fromJson({
    'name': 'Detached Playback', 'title': title,
    'url': url, 'headers': headers,
  }, 'PlayTorrio');

  static Future<DetachedPlaybackRequest?> takeFromArgs(
      List<String> args) async {
    if (!Platform.isWindows) return null;
    for (final arg in args) {
      if (!arg.startsWith('--pt-player-request=')) continue;
      final name = arg.substring('--pt-player-request='.length);
      if (name.isEmpty) return null;
      final file = File(name);
      try {
        if (!await file.exists()) return null;
        final raw = await file.readAsString();
        await file.delete();
        final parent = file.parent;
        if (parent.path.contains('playtorrio-viewer-')) {
          try { await parent.delete(); } catch (_) {}
        }
        final value = jsonDecode(raw);
        if (value is! Map<String, dynamic>) return null;
        return DetachedPlaybackRequest.fromJson(value);
      } catch (_) { return null; }
    }
    return null;
  }

  static Future<bool> launch(DetachedPlaybackRequest request) async {
    if (!Platform.isWindows) return false;
    final uri = Uri.tryParse(request.url);
    if (uri == null || !(['https', 'http', 'file'].contains(uri.scheme)
        || File(request.url).existsSync())) return false;
    // A torrent served from the app's own loopback endpoint will disappear
    // if the original player is stopped. Require independent HTTP / files.
    if (uri.host == '127.0.0.1' || uri.host == 'localhost') return false;
    Directory? temp;
    try {
      temp = await Directory.systemTemp.createTemp('playtorrio-viewer-');
      final requestFile = File('${temp.path}${Platform.pathSeparator}session.json');
      await requestFile.writeAsString(jsonEncode(request.toJson()), flush: true);
      await Process.start(
        Platform.resolvedExecutable,
        ['--pt-player-request=${requestFile.path}'],
        mode: ProcessStartMode.detached,
        workingDirectory: File(Platform.resolvedExecutable).parent.path,
      );
      return true;
    } catch (_) {
      if (temp != null) {
        try { await temp.delete(recursive: true); } catch (_) {}
      }
      return false;
    }
  }
}
