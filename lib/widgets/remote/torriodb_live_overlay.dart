import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../services/remote/lan_remote_service.dart';

/// A bounded declarative control surface supplied by the owner's Torriodb.
/// It is deliberately not an arbitrary Dart, JavaScript or HTML interpreter:
/// all interactive capabilities are compiled into the installed app.
class TorriodbLiveOverlayStore {
  TorriodbLiveOverlayStore._();
  static final TorriodbLiveOverlayStore instance = TorriodbLiveOverlayStore._();

  final ValueNotifier<Map<String, dynamic>?> document =
      ValueNotifier<Map<String, dynamic>?>(null);

  static const actions = <String>{
    'diagnostic_plan_cancel',
    'diagnostic_plan_status',
    'adaptive_stop',
    'open_channel',
    'live_channel_switch',
    'app_navigate',
    'settings_update',
    'settings_inspect',
    'player',
    'remote',
    'state',
    'player_verify',
  };
  static const widgetTypes = <String>{
    'text', 'button', 'switch', 'slider', 'row', 'column', 'divider', 'space',
  };

  @visibleForTesting
  static bool isValid(Map<String, dynamic>? source) {
    if (source == null) return true;
    if (source['schema'] != 1 || source['enabled'] is! bool) return false;
    final panels = source['panels'];
    if (panels is! List || panels.length > 8) return false;
    var total = 0;
    bool validNode(Object? raw, int depth) {
      if (depth > 4 || raw is! Map) return false;
      final node = Map<String, dynamic>.from(raw);
      final type = node['type'];
      if (type is! String || !widgetTypes.contains(type)) return false;
      total++;
      if (total > 96) return false;
      if (type == 'row' || type == 'column') {
        final children = node['children'];
        return children is List && children.length <= 16 &&
            children.every((child) => validNode(child, depth + 1));
      }
      if (type == 'text') {
        final value = node['text'];
        return value is String && value.length <= 500;
      }
      if (type == 'button' || type == 'switch' || type == 'slider') {
        final action = node['action'];
        final args = node['args'];
        final label = node['label'];
        if (action is! String || !actions.contains(action) ||
            label is! String || label.isEmpty || label.length > 100 ||
            args != null && args is! Map) return false;
        if (args is Map &&
            (args.length > 12 ||
             args.keys.any((key) => key is! String || key.length > 80) ||
             args.values.any((value) =>
               value is Map || value is List ||
               value is String && value.length > 220))) return false;
        if (type == 'switch' && node['value'] is! bool) return false;
        if (type == 'slider' &&
            (node['min'] is! num || node['max'] is! num ||
             node['value'] is! num ||
             (node['max'] as num) <= (node['min'] as num) ||
             (node['value'] as num) < (node['min'] as num) ||
             (node['value'] as num) > (node['max'] as num))) return false;
      }
      return true;
    }

    final ids = <String>{};
    for (final raw in panels) {
      if (raw is! Map) return false;
      final panel = Map<String, dynamic>.from(raw);
      final id = panel['id'];
      final position = panel['anchor'] ?? 'bottomRight';
      final when = panel['when'] ?? 'always';
      final width = panel['width'] ?? 320;
      final margin = panel['margin'] ?? 12;
      final items = panel['items'];
      if (id is! String ||
          !RegExp(r'^[a-zA-Z0-9_-]{1,50}$').hasMatch(id) ||
          !ids.add(id) ||
          !const {'topLeft', 'topRight', 'bottomLeft', 'bottomRight',
                  'topCenter', 'bottomCenter', 'center'}.contains(position) ||
          !const {'always', 'playing', 'notPlaying'}.contains(when) ||
          width is! num || width < 120 || width > 700 ||
          margin is! num || margin < 0 || margin > 100 ||
          items is! List || items.length > 20 ||
          !items.every((item) => validNode(item, 0))) return false;
    }
    return true;
  }

  void apply(Map<String, dynamic>? value) {
    if (!isValid(value)) {
      debugPrint('[TorriodbLiveOverlay] Invalid UI configuration rejected');
      return;
    }
    document.value = value;
  }
}

typedef TorriodbOverlayAction = Future<Map<String, Object?>> Function(
    String action, Map<String, dynamic> args);

class TorriodbLiveOverlay extends StatefulWidget {
  const TorriodbLiveOverlay({super.key, required this.onAction});

  final TorriodbOverlayAction onAction;

  @override
  State<TorriodbLiveOverlay> createState() => _TorriodbLiveOverlayState();
}

class _TorriodbLiveOverlayState extends State<TorriodbLiveOverlay> {
  final Map<String, bool> _switches = {};
  final Map<String, double> _sliders = {};
  final Set<String> _busy = <String>{};
  Timer? _visibilityTimer;
  bool _playerActive = false;

  @override
  void initState() {
    super.initState();
    _visibilityTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted) return;
      bool active = false;
      try {
        final player = LanRemoteService.instance.playerStatus?.call();
        active = player != null && player.isNotEmpty;
      } catch (error) {
        debugPrint('[TorriodbLiveOverlay] Player: ${error.runtimeType}');
      }
      if (active != _playerActive) setState(() => _playerActive = active);
    });
  }

  @override
  void dispose() {
    _visibilityTimer?.cancel();
    super.dispose();
  }

  Color _color(Object? value, Color fallback) {
    if (value is! String || !RegExp(r'^#[0-9a-fA-F]{8}$').hasMatch(value)) {
      return fallback;
    }
    return Color(int.parse(value.substring(1), radix: 16));
  }

  Future<void> _execute(String id, Map<String, dynamic> node,
      {Object? value}) async {
    if (_busy.contains(id)) return;
    final action = node['action'];
    if (action is! String ||
        !TorriodbLiveOverlayStore.actions.contains(action)) return;
    final args = node['args'] is Map
        ? Map<String, dynamic>.from(node['args'] as Map)
        : <String, dynamic>{};
    if (value != null) args['value'] = value;
    setState(() => _busy.add(id));
    try {
      final result = await widget.onAction(action, args);
      if (!mounted) return;
      if (result['accepted'] != true) {
        debugPrint('[TorriodbLiveOverlay] Rejected ${action}: ${result['reason']}');
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text('Action not accepted: ${result['reason'] ?? action}'),
              duration: const Duration(seconds: 2)));
      }
    } catch (error) {
      debugPrint('[TorriodbLiveOverlay] Action failed: ${error.runtimeType}');
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  Widget _node(Map<String, dynamic> node, String key, int depth) {
    if (depth > 4) return const SizedBox.shrink();
    final type = node['type'] as String? ?? '';
    final label = node['label']?.toString() ?? '';
    switch (type) {
      case 'text':
        final size = (node['fontSize'] is num
            ? (node['fontSize'] as num).toDouble().clamp(10.0, 36.0).toDouble()
            : 14.0);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Text(node['text']?.toString() ?? '',
            textAlign: node['align'] == 'center' ? TextAlign.center :
                node['align'] == 'right' ? TextAlign.right : TextAlign.left,
            style: TextStyle(
              fontSize: size,
              color: _color(node['color'], Colors.white),
              fontWeight: node['bold'] == true ? FontWeight.w700 : FontWeight.w400,
            )),
        );
      case 'button':
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: FilledButton(
            onPressed: _busy.contains(key) ? null : () => _execute(key, node),
            style: FilledButton.styleFrom(
              backgroundColor: _color(node['color'], const Color(0xFF344A80)),
              foregroundColor: Colors.white,
            ),
            child: _busy.contains(key)
                ? const SizedBox(height: 18, width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Text(label, textAlign: TextAlign.center)),
        );
      case 'switch':
        final enabled = _switches[key] ?? (node['value'] == true);
        return SwitchListTile.adaptive(
          title: Text(label, style: const TextStyle(color: Colors.white)),
          value: enabled,
          onChanged: _busy.contains(key) ? null : (value) {
            setState(() => _switches[key] = value);
            unawaited(_execute(key, node, value: value));
          },
        );
      case 'slider':
        final min = (node['min'] as num).toDouble();
        final max = (node['max'] as num).toDouble();
        final value = (_sliders[key] ?? (node['value'] as num).toDouble())
            .clamp(min, max).toDouble();
        return Column(mainAxisSize: MainAxisSize.min, children: [
          Text('$label: ${value.toStringAsFixed(0)}',
            style: const TextStyle(color: Colors.white)),
          Slider(
            min: min, max: max, value: value,
            onChanged: _busy.contains(key) ? null :
              (next) => setState(() => _sliders[key] = next),
            onChangeEnd: (next) => unawaited(_execute(key, node, value: next)),
          ),
        ]);
      case 'divider':
        return const Divider(color: Colors.white38);
      case 'space':
        return SizedBox(height: (node['height'] is num
            ? (node['height'] as num).toDouble().clamp(0.0, 100.0).toDouble() : 8.0));
      case 'row':
      case 'column':
        final children = node['children'] as List? ?? const [];
        final widgets = <Widget>[];
        for (var i = 0; i < children.length; i++) {
          if (children[i] is! Map) continue;
          final item = _node(Map<String, dynamic>.from(children[i] as Map),
              '$key/$i', depth + 1);
          widgets.add(type == 'row'
              ? Expanded(child: item) : item);
        }
        return type == 'row'
            ? Row(mainAxisSize: MainAxisSize.min, children: widgets)
            : Column(mainAxisSize: MainAxisSize.min, children: widgets);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _panel(Map<String, dynamic> panel) {
    final anchor = panel['anchor']?.toString() ?? 'bottomRight';
    final when = panel['when']?.toString() ?? 'always';
    if ((when == 'playing' && !_playerActive) ||
        (when == 'notPlaying' && _playerActive)) {
      return const SizedBox.shrink();
    }
    final margin = (panel['margin'] as num?)?.toDouble() ?? 12;
    final width = (panel['width'] as num?)?.toDouble() ?? 320;
    final left = anchor.contains('Left');
    final right = anchor.contains('Right');
    final top = anchor.startsWith('top');
    final bottom = anchor.startsWith('bottom');
    final centerX = anchor.contains('Center') || anchor == 'center';
    final items = panel['items'] as List? ?? const [];
    final screen = MediaQuery.sizeOf(context);
    final boundedWidth = width.clamp(120.0, screen.width - 2 * margin > 120
        ? screen.width - 2 * margin : 120.0).toDouble();
    Widget surface = Material(
      color: _color(panel['background'], const Color(0xDF151A27)),
      borderRadius: BorderRadius.circular(14),
      elevation: 8,
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false, bottom: false, left: false, right: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: screen.height * 0.75),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Column(mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < items.length; i++)
                  if (items[i] is Map)
                    _node(Map<String, dynamic>.from(items[i] as Map),
                        '${panel['id']}/$i', 0),
              ]),
          ),
        ),
      ),
    );
    return Positioned(
      left: left ? margin : centerX ? (screen.width - boundedWidth) / 2 : null,
      right: right ? margin : null,
      top: top ? margin + MediaQuery.paddingOf(context).top :
           (!bottom ? (screen.height * 0.5) : null),
      bottom: bottom ? margin + MediaQuery.paddingOf(context).bottom : null,
      width: boundedWidth,
      child: surface,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Map<String, dynamic>?>(
      valueListenable: TorriodbLiveOverlayStore.instance.document,
      builder: (context, document, _) {
        if (document == null || document['enabled'] != true) {
          return const SizedBox.shrink();
        }
        final panels = document['panels'] as List? ?? const [];
        return Stack(
          fit: StackFit.expand,
          children: [
            for (final panel in panels)
              if (panel is Map)
                _panel(Map<String, dynamic>.from(panel)),
          ],
        );
      },
    );
  }
}
