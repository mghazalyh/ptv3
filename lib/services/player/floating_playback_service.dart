import 'package:flutter/material.dart';

import '../../models/movie/movie_detail.dart';
import '../../models/movie/video.dart';
import '../../models/stream/stream_model.dart';
import '../../pages/player/player_screen.dart';

/// Shared persistent playback host. It lives outside Navigator, so normal
/// browsing routes can be pushed/popped without disposing media_kit's Player.
class FloatingPlaybackSession {
  const FloatingPlaybackSession({
    required this.source,
    required this.title,
    this.backdropUrl,
    this.logoUrl,
    this.detail,
    this.episode,
    this.initialPosition,
  });

  final StreamSource source;
  final String title;
  final String? backdropUrl;
  final String? logoUrl;
  final MovieDetail? detail;
  final Video? episode;
  final Duration? initialPosition;
}

class FloatingPlaybackService {
  static final ValueNotifier<FloatingPlaybackSession?> current =
      ValueNotifier<FloatingPlaybackSession?>(null);
  static final ValueNotifier<bool> isMini = ValueNotifier<bool>(false);

  static void play(FloatingPlaybackSession session) {
    // App-level shell guarantees old media is disposed before a new session.
    current.value = session;
    isMini.value = false;
  }

  static void minimize() {
    if (current.value != null) isMini.value = true;
  }

  static void expand() {
    if (current.value != null) isMini.value = false;
  }

  static void stop() {
    current.value = null;
    isMini.value = false;
  }
}

/// Draggable in-app corner PiP for iPad; same shell on Windows. A separate
/// window action inside the full player supports dual-monitor playback.
class FloatingPlaybackHost extends StatefulWidget {
  const FloatingPlaybackHost({super.key, required this.child});
  final Widget child;

  @override
  State<FloatingPlaybackHost> createState() => _FloatingPlaybackHostState();
}

class _FloatingPlaybackHostState extends State<FloatingPlaybackHost> {
  Offset? _freePosition;
  Alignment _corner = Alignment.bottomRight;
  double _viewportW = 0;
  double _viewportH = 0;
  double _miniW = 260;
  double _miniH = 147;

  void _onMove(DragUpdateDetails delta) {
    final current = _freePosition ?? _alignedPosition();
    setState(() {
      _freePosition = Offset(
        (current.dx + delta.delta.dx).clamp(8.0, (_viewportW - _miniW - 8).clamp(8.0, double.infinity)),
        (current.dy + delta.delta.dy).clamp(8.0, (_viewportH - _miniH - 8).clamp(8.0, double.infinity)),
      );
    });
  }

  Offset _alignedPosition() {
    final right = (_viewportW - _miniW - 14).clamp(8.0, double.infinity);
    final bottom = (_viewportH - _miniH - 20).clamp(8.0, double.infinity);
    return Offset(_corner.x > 0 ? right : 14, _corner.y > 0 ? bottom : 20);
  }

  void _onMoveEnd(DragEndDetails _) {
    final p = _freePosition ?? _alignedPosition();
    setState(() {
      _corner = Alignment(
        p.dx + _miniW / 2 > _viewportW / 2 ? 1 : -1,
        p.dy + _miniH / 2 > _viewportH / 2 ? 1 : -1,
      );
      _freePosition = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      _viewportW = constraints.maxWidth;
      _viewportH = constraints.maxHeight;
      _miniW = (_viewportW * 0.38).clamp(195.0, 320.0);
      _miniH = _miniW * 9 / 16;
      return Stack(fit: StackFit.expand, children: [
        widget.child,
        ValueListenableBuilder<FloatingPlaybackSession?>(
          valueListenable: FloatingPlaybackService.current,
          builder: (context, session, _) {
            if (session == null) return const SizedBox.shrink();
            return ValueListenableBuilder<bool>(
              valueListenable: FloatingPlaybackService.isMini,
              builder: (context, mini, _) {
                final where = mini ? (_freePosition ?? _alignedPosition()) : Offset.zero;
                return Positioned(
                  left: where.dx,
                  top: where.dy,
                  width: mini ? _miniW : _viewportW,
                  height: mini ? _miniH : _viewportH,
                  child: Material(
                    color: Colors.black,
                    elevation: mini ? 14 : 0,
                    borderRadius: mini ? BorderRadius.circular(12) : null,
                    clipBehavior: mini ? Clip.antiAlias : Clip.none,
                    child: PlayerScreen(
                      key: ObjectKey(session),
                      source: session.source,
                      title: session.title,
                      backdropUrl: session.backdropUrl,
                      logoUrl: session.logoUrl,
                      detail: session.detail,
                      episode: session.episode,
                      initialPosition: session.initialPosition,
                      compact: mini,
                      onMinimize: FloatingPlaybackService.minimize,
                      onExpand: FloatingPlaybackService.expand,
                      onClose: FloatingPlaybackService.stop,
                      onMiniDrag: _onMove,
                      onMiniDragEnd: _onMoveEnd,
                    ),
                  ),
                );
              },
            );
          },
        ),
      ]);
    });
  }
}
