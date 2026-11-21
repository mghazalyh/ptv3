import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'ios_diagnostic_journal.dart';

/// Observes only app-owned navigation, not other iOS applications. Route
/// payloads and user text are deliberately excluded from remote snapshots.
class IosRemoteRouteObserver extends NavigatorObserver {
  IosRemoteRouteObserver();

  final List<Route<dynamic>> _stack = [];

  void _add(Route<dynamic> route) {
    _stack.remove(route);
    _stack.add(route);
    if (_stack.length > 40) _stack.removeAt(0);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _add(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.remove(route);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.remove(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute,
      Route<dynamic>? oldRoute}) {
    if (oldRoute != null) _stack.remove(oldRoute);
    if (newRoute != null) _add(newRoute);
  }

  Map<String, Object?> state() => <String, Object?>{
    'routeCount': _stack.length,
    'currentRoute': _stack.isEmpty ? null : _label(_stack.last),
    'dialogVisible': _stack.isNotEmpty &&
        _stack.last is PopupRoute,
    'stack': _stack.reversed.take(12).map(_label).toList(),
  };

  String _label(Route<dynamic> route) {
    final name = route.settings.name;
    if (name != null &&
        RegExp(r'^/[A-Za-z0-9_/-]{1,80}$').hasMatch(name)) {
      return name;
    }
    return route is PopupRoute ? 'popup_route' :
        route is PageRoute ? 'page_route' : 'route';
  }
}

/// Flutter UI screenshots may omit platform-backed video textures. The
/// resulting image is used only as private evidence, never as proof of
/// native decoded video. MPV verification remains a separate operation.
class IosRemoteAppObservability {
  IosRemoteAppObservability();

  static final IosRemoteAppObservability instance =
      IosRemoteAppObservability();

  final GlobalKey captureKey = GlobalKey(debugLabel: 'remote_app_capture');
  final IosRemoteRouteObserver routes = IosRemoteRouteObserver();

  Map<String, Object?> inspect({
    required bool foreground,
    required bool navigatorReady,
    required bool playerActive,
    required bool matrixRunning,
  }) {
    final focus = FocusManager.instance.primaryFocus;
    return <String, Object?>{
      'accepted': true,
      'foreground': foreground,
      'navigatorReady': navigatorReady,
      'playerActive': playerActive,
      'matrixRunning': matrixRunning,
      'canCaptureFlutterUi': captureKey.currentContext != null,
      'hasPrimaryFocus': focus != null,
      'focusHasContext': focus?.context != null,
      ...routes.state(),
    };
  }

  Future<Map<String, Object?>> capture() async {
    try {
      final context = captureKey.currentContext;
      if (context == null || !context.mounted) {
        return <String, Object?>{
          'accepted': false, 'reason': 'capture_surface_unavailable',
        };
      }
      final object = context.findRenderObject();
      if (object is! RenderRepaintBoundary ||
          !object.attached || object.size.isEmpty) {
        return <String, Object?>{
          'accepted': false, 'reason': 'capture_surface_not_ready',
        };
      }
      if (object.debugNeedsPaint) {
        await WidgetsBinding.instance.endOfFrame;
      }
      final image = await object.toImage(pixelRatio: 1.0);
      try {
        final bytes = await image.toByteData(
            format: ui.ImageByteFormat.png);
        if (bytes == null || bytes.lengthInBytes == 0) {
          return <String, Object?>{
            'accepted': false, 'reason': 'flutter_capture_empty',
          };
        }
        final result = await IosDiagnosticJournal.instance.saveCapture(
          bytes.buffer.asUint8List(),
        );
        return <String, Object?>{
          ...result,
          'captureType': 'flutter_app_surface',
          'width': image.width,
          'height': image.height,
          'nativeVideoTextureMayBeOmitted': true,
        };
      } finally {
        image.dispose();
      }
    } catch (error) {
      debugPrint('[IosRemoteAppObservability] Capture: ${error.runtimeType}');
      return <String, Object?>{
        'accepted': false, 'reason': 'flutter_capture_failed',
        'errorClass': error.runtimeType.toString(),
      };
    }
  }
}
