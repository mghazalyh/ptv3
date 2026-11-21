import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/movie/movie.dart';
import '../../models/movie/video.dart';
import '../../pages/remote/remote_control_page.dart';
import '../../services/remote/lan_cast_request.dart';
import '../../services/remote/lan_remote_service.dart';

/// Visible long-press action for browsing on an iPhone.
abstract final class PlayOnIpadSheet {
  static bool get supported => !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.iOS;

  static Future<void> show(BuildContext context, {
    required Movie movie,
    Video? episode,
  }) async {
    if (!supported) return;
    final type = LanCastRequest.normalizeType(movie.type);
    if (type == null) return;
    final base = Uri.tryParse(movie.addonBaseUrl);
    final request = LanCastRequest(
      type: type,
      mediaId: movie.id,
      title: movie.name,
      addonBaseUrl: base?.scheme == 'https'
          ? movie.addonBaseUrl : null,
      episodeId: episode?.id,
      season: episode?.season,
      episode: episode?.episode,
    );
    if (LanCastRequest.parse(request.toJson()) == null) return;
    await HapticFeedback.selectionClick();
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: const Color(0xFF171B27),
      builder: (sheetContext) => _CastSheetContent(
        request: request,
        onPairedNeeded: () {
          Navigator.of(sheetContext).pop();
          navigator.push(MaterialPageRoute<void>(
            builder: (_) => const RemoteControlPage()));
        },
        onSent: (message) {
          Navigator.of(sheetContext).pop();
          messenger.showSnackBar(SnackBar(content: Text(message)));
        },
      ),
    );
  }
}

class _CastSheetContent extends StatefulWidget {
  const _CastSheetContent({
    required this.request, required this.onPairedNeeded,
    required this.onSent,
  });
  final LanCastRequest request;
  final VoidCallback onPairedNeeded;
  final ValueChanged<String> onSent;

  @override
  State<_CastSheetContent> createState() => _CastSheetContentState();
}

class _CastSheetContentState extends State<_CastSheetContent> {
  bool _sending = false;
  String? _error;

  Future<void> _send() async {
    if (_sending) return;
    final service = LanRemoteService.instance;
    final session = service.activeSession.value;
    if (session == null) return;
    setState(() { _sending = true; _error = null; });
    try {
      final result = await service.sendCast(session, widget.request);
      if (!mounted) return;
      widget.onSent(result['launched'] == true
          ? 'Playback requested on ${session.peer.name}'
          : 'Opened source selection on ${session.peer.name}');
    } catch (error) {
      debugPrint('[LAN Cast UI] Send failed: ${error.runtimeType}');
      if (mounted) {
        setState(() { _error = 'iPad did not accept the request. '
            'Check pairing, Wi-Fi and that PlayTorrio is open.'; });
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = LanRemoteService.instance;
    return ValueListenableBuilder<LanRemoteSession?>(
      valueListenable: service.activeSession,
      builder: (context, session, _) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 30),
          child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(children: [
                Icon(Icons.cast_connected_rounded, color: Color(0xFFA999FF)),
                SizedBox(width: 10),
                Text('Play on iPad', style: TextStyle(
                  color: Colors.white, fontSize: 22,
                  fontWeight: FontWeight.w800)),
              ]),
              const SizedBox(height: 15),
              Text(widget.request.title, maxLines: 2,
                style: const TextStyle(color: Colors.white, fontSize: 17)),
              if (widget.request.episode != null)
                Text('Season ${widget.request.season ?? "?"} · '
                    'Episode ${widget.request.episode}',
                  style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 14),
              Text(session == null
                  ? 'Pair your iPhone with the iPad in Remote Control first.'
                  : 'Target: ${session.peer.name} (${session.peer.address})',
                style: const TextStyle(color: Colors.white70)),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style:
                    const TextStyle(color: Color(0xFFFF8888))),
              ],
              const SizedBox(height: 20),
              SizedBox(width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _sending ? null :
                      session == null ? widget.onPairedNeeded : _send,
                  icon: _sending
                      ? const SizedBox(width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(session == null
                          ? Icons.link_rounded : Icons.play_arrow_rounded),
                  label: Text(session == null
                      ? 'Pair iPad' : _sending
                      ? 'Sending to iPad...' : 'Play on ${session.peer.name}'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
