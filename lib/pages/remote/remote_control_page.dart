import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/remote/lan_remote_service.dart';

/// Both iPhone and iPad use the same screen. One enables the receiver, while
/// the other discovers it and becomes a paired navigation / playback remote.
class RemoteControlPage extends StatefulWidget {
  const RemoteControlPage({super.key});

  @override
  State<RemoteControlPage> createState() => _RemoteControlPageState();
}

class _RemoteControlPageState extends State<RemoteControlPage> {
  final LanRemoteService _lan = LanRemoteService.instance;
  final TextEditingController _address = TextEditingController();
  final TextEditingController _pin = TextEditingController();
  List<LanRemotePeer> _found = const <LanRemotePeer>[];
  LanRemotePeer? _selected;
  LanRemoteSession? _session;
  String? _localAddress;
  String? _error;
  String? _playerTitle;
  bool _isPlaying = false;
  bool _scanning = false;
  bool _pairing = false;
  bool _changingReceiver = false;
  Timer? _pollTimer;
  Future<void> _commandQueue = Future<void>.value();

  @override
  void initState() {
    super.initState();
    _lan.hosting.addListener(_refresh);
    _lan.pairedDevices.addListener(_refresh);
    _loadAddress();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && Platform.isIOS) unawaited(_scan());
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _lan.hosting.removeListener(_refresh);
    _lan.pairedDevices.removeListener(_refresh);
    _address.dispose();
    _pin.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _loadAddress() async {
    final address = await _lan.localAddress();
    if (mounted) setState(() => _localAddress = address);
  }

  Future<void> _startOrStopReceiver() async {
    if (_changingReceiver) return;
    setState(() {
      _changingReceiver = true;
      _error = null;
    });
    try {
      if (_lan.hosting.value) {
        await _lan.stopHosting();
      } else {
        final isTablet = MediaQuery.sizeOf(context).shortestSide >= 600;
        await _lan.startHosting(
            name: isTablet ? 'PlayTorrio iPad' : 'PlayTorrio iPhone');
        await _loadAddress();
      }
    } catch (error) {
      debugPrint('[LAN Remote UI] Receiver toggle failed: $error');
      _setError(error);
    } finally {
      if (mounted) setState(() => _changingReceiver = false);
    }
  }

  Future<void> _scan() async {
    if (_scanning) return;
    setState(() {
      _scanning = true;
      _error = null;
    });
    try {
      final devices = await _lan.discover();
      if (!mounted) return;
      setState(() {
        _found = devices;
        if (_selected == null && devices.length == 1) {
          _selected = devices.first;
          _address.text = devices.first.address;
        }
      });
    } catch (error) {
      debugPrint('[LAN Remote UI] Scan error: $error');
      _setError(error);
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  void _selectPeer(LanRemotePeer peer) {
    _selected = peer;
    _address.text = peer.address;
    _pin.clear();
    if (mounted) setState(() => _error = null);
  }

  void _setError(Object error) {
    if (!mounted) return;
    setState(() => _error = error.toString().replaceFirst(
        RegExp(r'^(Bad state|FormatException):\s*'), ''));
  }

  Future<void> _pair() async {
    if (_pairing) return;
    final ip = _address.text.trim();
    if (!LanRemoteProtocol.validLanAddress(ip)) {
      _setError('Enter the iPad Wi-Fi IPv4 address (for example 192.168.1.5).');
      return;
    }
    setState(() {
      _pairing = true;
      _error = null;
    });
    try {
      final peer = LanRemotePeer(
        name: _selected?.address == ip ? _selected!.name : 'PlayTorrio iPad',
        address: ip,
      );
      final session = await _lan.pair(peer, _pin.text.trim());
      if (!mounted) return;
      _pollTimer?.cancel();
      setState(() {
        _session = session;
        _selected = session.peer;
        _pin.clear();
      });
      _pollTimer = Timer.periodic(
          const Duration(seconds: 4), (_) => unawaited(_poll()));
      unawaited(_poll());
    } catch (error) {
      debugPrint('[LAN Remote UI] Pairing failed: $error');
      _setError(error);
    } finally {
      if (mounted) setState(() => _pairing = false);
    }
  }

  Future<void> _poll() async {
    final session = _session;
    if (session == null || !mounted) return;
    try {
      final state = await _lan.readState(session);
      if (!mounted || !identical(session, _session)) return;
      final player = state['player'];
      setState(() {
        _error = null;
        if (player is Map) {
          _playerTitle = player['title']?.toString();
          _isPlaying = player['playing'] == true;
        } else {
          _playerTitle = null;
          _isPlaying = false;
        }
      });
    } catch (error) {
      debugPrint('[LAN Remote UI] Status poll failed: $error');
      if (mounted && identical(session, _session)) _setError(error);
    }
  }

  void _disconnect() {
    _pollTimer?.cancel();
    _pollTimer = null;
    setState(() {
      _session = null;
      _playerTitle = null;
      _error = null;
      _isPlaying = false;
    });
  }

  void _send(LanRemoteCommand command) {
    final session = _session;
    if (session == null) return;
    // Serialize taps; quick left/right/OK sequences must arrive in order.
    _commandQueue = _commandQueue.then((_) async {
      if (!mounted || !identical(session, _session)) return;
      try {
        await _lan.send(session, command);
        if (command == LanRemoteCommand.playPause ||
            command == LanRemoteCommand.back ||
            command == LanRemoteCommand.select) {
          unawaited(_poll());
        }
      } catch (error) {
        debugPrint('[LAN Remote UI] Command failed: $error');
        _setError(error);
      }
    });
  }

  Widget _remoteButton(IconData icon, LanRemoteCommand command, {
    String? tooltip, double size = 68, bool emphasized = false,
  }) {
    return SizedBox(
      width: size, height: size,
      child: Tooltip(
        message: tooltip ?? command.name,
        child: Material(
          color: emphasized ? const Color(0xFF7C5CFF) :
              const Color(0xFF222536),
          borderRadius: BorderRadius.circular(23),
          child: InkWell(
            borderRadius: BorderRadius.circular(23),
            onTap: () => _send(command),
            child: Icon(icon, size: 32, color: Colors.white),
          ),
        ),
      ),
    );
  }

  Widget _receiverCard() {
    return Card(
      color: const Color(0xFF151925),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(children: [
              Icon(Icons.tv_rounded, color: Color(0xFF9C88FF)),
              SizedBox(width: 10),
              Expanded(child: Text('Control this device',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18))),
            ]),
            const SizedBox(height: 8),
            const Text(
              'On your iPad, enable this receiver and leave PlayTorrio open. '
              'Then choose it on your iPhone. Both devices must be on the same Wi-Fi.',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _changingReceiver ? null : _startOrStopReceiver,
              icon: Icon(_lan.hosting.value ? Icons.stop_circle_outlined :
                  Icons.settings_remote_rounded),
              label: Text(_lan.hosting.value ? 'Stop accepting remotes' :
                  'Enable remote control'),
            ),
            if (_lan.hosting.value) ...[
              const SizedBox(height: 18),
              const Text('PAIRING CODE', style: TextStyle(
                color: Colors.white60, letterSpacing: 2)),
              SelectableText(_lan.pairingCode ?? '------',
                  style: const TextStyle(fontSize: 37,
                      fontWeight: FontWeight.w800, letterSpacing: 7)),
              const SizedBox(height: 6),
              Text('iPad Wi-Fi address: ' + (_localAddress ?? 'Unavailable'),
                  style: const TextStyle(color: Colors.white70)),
              Text('Connected remotes: ' +
                  _lan.pairedDevices.value.toString(),
                  style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 4),
              const Text('This code changes whenever you restart the receiver. '
                  'Disabling the receiver disconnects paired phones.',
                  style: TextStyle(fontSize: 12, color: Colors.white54)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _pairingCard() {
    return Card(
      color: const Color(0xFF151925),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.phone_iphone_rounded, color: Color(0xFF9C88FF)),
            SizedBox(width: 10),
            Expanded(child: Text('Connect to your iPad',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18))),
          ]),
          const SizedBox(height: 8),
          const Text('Open PlayTorrio > Settings > Remote Control on '
              'the iPad and enable its receiver.',
              style: TextStyle(color: Colors.white70)),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _scanning ? null : _scan,
            icon: _scanning
                ? const SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.radar_rounded),
            label: Text(_scanning ? 'Searching Wi-Fi...' :
                'Find nearby PlayTorrio devices'),
          ),
          for (final peer in _found)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.tablet_mac_rounded),
              title: Text(peer.name),
              subtitle: Text(peer.address),
              selected: _selected?.address == peer.address,
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _selectPeer(peer),
            ),
          const SizedBox(height: 8),
          TextField(
            controller: _address,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'iPad IP address (manual fallback)',
              hintText: '192.168.1.5',
            ),
            keyboardType: TextInputType.url,
            autocorrect: false,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pin,
            keyboardType: TextInputType.number,
            obscureText: false,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Six-digit pairing code on the iPad',
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _pairing ? null : _pair,
            icon: const Icon(Icons.link_rounded),
            label: Text(_pairing ? 'Pairing...' : 'Connect remote'),
          ),
          const SizedBox(height: 8),
          const Text('If discovery does not find your iPad, enter the Wi-Fi '
              'IP address shown on the iPad receiver screen. '
              'Guest Wi-Fi and client isolation can prevent connections.',
              style: TextStyle(fontSize: 12, color: Colors.white54)),
        ]),
      ),
    );
  }

  Widget _controller() {
    final session = _session!;
    return Card(
      color: const Color(0xFF151925),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
        child: Column(children: [
          Row(children: [
            const Icon(Icons.cast_connected_rounded, color: Color(0xFF9C88FF)),
            const SizedBox(width: 10),
            Expanded(child: Text(session.peer.name,
                style: const TextStyle(fontWeight: FontWeight.bold,
                    fontSize: 18))),
            IconButton(
              tooltip: 'Disconnect',
              onPressed: _disconnect,
              icon: const Icon(Icons.link_off_rounded),
            ),
          ]),
          if (_playerTitle != null && _playerTitle!.isNotEmpty)
            Text((_isPlaying ? 'Playing: ' : 'Paused: ') + _playerTitle!,
                maxLines: 2, overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 18),
          const Text('NAVIGATION', style: TextStyle(
            fontWeight: FontWeight.w700, letterSpacing: 2,
            color: Colors.white54)),
          const SizedBox(height: 12),
          _remoteButton(Icons.keyboard_arrow_up_rounded,
              LanRemoteCommand.up, tooltip: 'Up', size: 72),
          const SizedBox(height: 7),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _remoteButton(Icons.keyboard_arrow_left_rounded,
                LanRemoteCommand.left, tooltip: 'Left', size: 72),
            const SizedBox(width: 7),
            _remoteButton(Icons.check_rounded,
                LanRemoteCommand.select, tooltip: 'Select',
                size: 72, emphasized: true),
            const SizedBox(width: 7),
            _remoteButton(Icons.keyboard_arrow_right_rounded,
                LanRemoteCommand.right, tooltip: 'Right', size: 72),
          ]),
          const SizedBox(height: 7),
          _remoteButton(Icons.keyboard_arrow_down_rounded,
              LanRemoteCommand.down, tooltip: 'Down', size: 72),
          const SizedBox(height: 17),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _remoteButton(Icons.arrow_back_rounded,
                LanRemoteCommand.back, tooltip: 'Back'),
            const SizedBox(width: 18),
            _remoteButton(Icons.home_rounded,
                LanRemoteCommand.home, tooltip: 'Home'),
          ]),
          const SizedBox(height: 24),
          const Divider(color: Colors.white12),
          const SizedBox(height: 9),
          const Text('PLAYBACK', style: TextStyle(
            fontWeight: FontWeight.w700, letterSpacing: 2,
            color: Colors.white54)),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _remoteButton(Icons.replay_10_rounded,
                LanRemoteCommand.seekBack, tooltip: 'Back 10 seconds'),
            const SizedBox(width: 18),
            _remoteButton(Icons.play_circle_filled_rounded,
                LanRemoteCommand.playPause, tooltip: 'Play / Pause',
                emphasized: true),
            const SizedBox(width: 18),
            _remoteButton(Icons.forward_10_rounded,
                LanRemoteCommand.seekForward, tooltip: 'Forward 10 seconds'),
          ]),
          const SizedBox(height: 12),
          const Text('Use arrows to move the highlighted selection on the '
              'iPad. Select opens it. During video, Left/Right seek by '
              '10 seconds and Select toggles playback.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.white54)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0C13),
      appBar: AppBar(
        title: const Text('PlayTorrio Remote'),
        backgroundColor: const Color(0xFF141722),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (!Platform.isIOS)
              const Card(child: Padding(
                padding: EdgeInsets.all(20),
                child: Text('LAN Remote is available in the iOS app.')))
            else ...[
              _receiverCard(),
              const SizedBox(height: 12),
              if (_session == null) _pairingCard() else _controller(),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFFFF8A80))),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
