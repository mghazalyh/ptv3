import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'lan_cast_request.dart';

/// LAN remote messages never contain media URLs, tokens, or library data.
enum LanRemoteCommand {
  up, down, left, right, select, back, home, playPause, seekBack, seekForward,
}

abstract final class LanRemoteProtocol {
  static const int httpPort = 47891;
  static const int discoveryPort = 47890;
  static const String probe = 'PLAYTORRIO_REMOTE_DISCOVER_V1';
  static const String reply = 'PLAYTORRIO_REMOTE_HERE_V1 ';

  static LanRemoteCommand? parseCommand(String value) {
    for (final command in LanRemoteCommand.values) {
      if (command.name == value) return command;
    }
    return null;
  }

  static bool validCode(String value) =>
      RegExp(r'^[0-9]{6}$').hasMatch(value);

  static bool validLanAddress(String value) {
    final address = InternetAddress.tryParse(value.trim());
    if (address == null || address.type != InternetAddressType.IPv4) {
      return false;
    }
    final b = address.rawAddress;
    return b[0] == 10 ||
        (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
        (b[0] == 192 && b[1] == 168) ||
        (b[0] == 169 && b[1] == 254);
  }
}

class LanRemotePeer {
  final String name;
  final String address;
  final int port;
  const LanRemotePeer({
    required this.name,
    required this.address,
    this.port = LanRemoteProtocol.httpPort,
  });
}

class LanRemoteSession {
  final LanRemotePeer peer;
  final String token;
  const LanRemoteSession({required this.peer, required this.token});
}

/// Receiver is opt-in, foreground-only (iOS suspends network execution when
/// backgrounded), and uses a fresh random six-digit PIN per receiver session.
/// Paired credentials exist in memory only and die when hosting is stopped.
class LanRemoteService {
  LanRemoteService._();
  static final LanRemoteService instance = LanRemoteService._();
  final ValueNotifier<bool> hosting = ValueNotifier<bool>(false);
  final ValueNotifier<int> pairedDevices = ValueNotifier<int>(0);
  final Random _random = Random.secure();
  HttpServer? _server;
  RawDatagramSocket? _discovery;
  StreamSubscription<RawSocketEvent>? _discoveryEvents;
  String? _pin;
  String _deviceName = 'PlayTorrio';
  final Set<String> _authorizedTokens = <String>{};
  final Map<String, int> _badPinAttempts = <String, int>{};
  final Map<String, DateTime> _blockedUntil = <String, DateTime>{};

  void Function(LanRemoteCommand)? onNavigationCommand;
  bool Function(LanRemoteCommand)? onPlayerCommand;
  Map<String, Object?> Function()? playerStatus;
  Future<Map<String, Object?>> Function(LanCastRequest)? onCastRequest;
  final ValueNotifier<LanRemoteSession?> activeSession =
      ValueNotifier<LanRemoteSession?>(null);
  String? get pairingCode => _pin;
  String get deviceName => _deviceName;

  Future<String?> localAddress() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4, includeLoopback: false);
      final ordered = interfaces.toList()
        ..sort((a, b) {
          if (a.name == 'en0') return -1;
          if (b.name == 'en0') return 1;
          return a.name.compareTo(b.name);
        });
      for (final interface in ordered) {
        for (final address in interface.addresses) {
          if (LanRemoteProtocol.validLanAddress(address.address)) {
            return address.address;
          }
        }
      }
    } catch (error) {
      debugPrint('[LAN Remote] Interface lookup failed: $error');
    }
    return null;
  }

  Future<void> startHosting({required String name}) async {
    if (!Platform.isIOS) {
      throw UnsupportedError('Remote receiving is available on iOS.');
    }
    if (_server != null) return;
    _deviceName = name.trim().isEmpty ? 'PlayTorrio' : name.trim();
    _pin = (100000 + _random.nextInt(900000)).toString();
    _authorizedTokens.clear();
    _badPinAttempts.clear();
    _blockedUntil.clear();
    pairedDevices.value = 0;
    try {
      final server = await HttpServer.bind(
          InternetAddress.anyIPv4, LanRemoteProtocol.httpPort);
      _server = server;
      server.listen((request) => unawaited(_handleRequest(request)),
          onError: (Object error, StackTrace trace) {
        debugPrint('[LAN Remote] HTTP listener failed: $error');
      });
      try {
        final discovery = await RawDatagramSocket.bind(
            InternetAddress.anyIPv4, LanRemoteProtocol.discoveryPort);
        _discovery = discovery;
        _discoveryEvents = discovery.listen(_handleProbe,
            onError: (Object error, StackTrace trace) {
          debugPrint('[LAN Remote] Discovery listener failed: $error');
        });
      } catch (error) {
        // IP-based connection stays available if broadcast is unavailable.
        debugPrint('[LAN Remote] UDP discovery unavailable: $error');
      }
      hosting.value = true;
      debugPrint('[LAN Remote] Receiver enabled');
    } catch (error) {
      await stopHosting();
      debugPrint('[LAN Remote] Receiver start failed: $error');
      rethrow;
    }
  }

  Future<void> stopHosting() async {
    hosting.value = false;
    _pin = null;
    _authorizedTokens.clear();
    _badPinAttempts.clear();
    _blockedUntil.clear();
    pairedDevices.value = 0;
    await _discoveryEvents?.cancel();
    _discoveryEvents = null;
    _discovery?.close();
    _discovery = null;
    final server = _server;
    _server = null;
    await server?.close(force: true);
  }

  void _handleProbe(RawSocketEvent event) {
    if (event != RawSocketEvent.read || !hosting.value) return;
    final socket = _discovery;
    if (socket == null) return;
    Datagram? packet;
    while ((packet = socket.receive()) != null) {
      final datagram = packet!;
      if (datagram.data.length > 128 ||
          utf8.decode(datagram.data, allowMalformed: true).trim() !=
              LanRemoteProtocol.probe) continue;
      try {
        socket.send(
          utf8.encode(LanRemoteProtocol.reply +
              jsonEncode({'name': _deviceName,
                'port': LanRemoteProtocol.httpPort})),
          datagram.address, datagram.port);
      } catch (error) {
        debugPrint('[LAN Remote] Discovery reply failed: $error');
      }
    }
  }

  Future<List<LanRemotePeer>> discover() async {
    if (!Platform.isIOS) return const <LanRemotePeer>[];
    RawDatagramSocket? socket;
    StreamSubscription<RawSocketEvent>? listener;
    final found = <String, LanRemotePeer>{};
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
      final receiver = socket;
      listener = receiver.listen((event) {
        if (event != RawSocketEvent.read) return;
        Datagram? packet;
        while ((packet = receiver.receive()) != null) {
          final datagram = packet!;
          if (datagram.data.length > 512 ||
              !LanRemoteProtocol.validLanAddress(datagram.address.address)) {
            continue;
          }
          final message = utf8.decode(datagram.data, allowMalformed: true);
          if (!message.startsWith(LanRemoteProtocol.reply)) continue;
          try {
            final payload = jsonDecode(
                message.substring(LanRemoteProtocol.reply.length));
            if (payload is! Map<String, dynamic>) continue;
            final name = payload['name'];
            if (name is! String || name.isEmpty || name.length > 80 ||
                payload['port'] != LanRemoteProtocol.httpPort) continue;
            found[datagram.address.address] = LanRemotePeer(
                name: name, address: datagram.address.address);
          } catch (error) {
            debugPrint('[LAN Remote] Invalid UDP response: $error');
          }
        }
      });
      receiver.send(utf8.encode(LanRemoteProtocol.probe),
          InternetAddress('255.255.255.255'),
          LanRemoteProtocol.discoveryPort);
      await Future<void>.delayed(const Duration(milliseconds: 2100));
    } catch (error) {
      debugPrint('[LAN Remote] Scan failed: $error');
    } finally {
      await listener?.cancel();
      socket?.close();
    }
    return found.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  String _newToken() => base64Url.encode(
      List<int>.generate(32, (_) => _random.nextInt(256)));

  Future<void> _handleRequest(HttpRequest request) async {
    final response = request.response;
    response.headers.contentType = ContentType.json;
    response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    try {
      if (request.method == 'POST' && request.uri.path == '/pair') {
        final ip = request.connectionInfo?.remoteAddress.address ?? 'unknown';
        final blocked = _blockedUntil[ip];
        if (blocked != null && DateTime.now().isBefore(blocked)) {
          await _write(response, 429,
              {'error': 'Too many incorrect codes. Try again in two minutes.'});
          return;
        }
        final payload = await _readJson(request);
        final pin = payload['pin'];
        if (pin is! String || !LanRemoteProtocol.validCode(pin) ||
            pin != _pin) {
          final attempts = (_badPinAttempts[ip] ?? 0) + 1;
          _badPinAttempts[ip] = attempts;
          if (attempts >= 5) {
            _badPinAttempts[ip] = 0;
            _blockedUntil[ip] =
                DateTime.now().add(const Duration(minutes: 2));
          }
          await _write(response, 403, {'error': 'Incorrect pairing code.'});
          return;
        }
        _badPinAttempts.remove(ip);
        _blockedUntil.remove(ip);
        final token = _newToken();
        _authorizedTokens.add(token);
        pairedDevices.value = _authorizedTokens.length;
        await _write(response, 200,
            {'token': token, 'name': _deviceName});
        return;
      }

      final auth = request.headers.value(HttpHeaders.authorizationHeader);
      if (auth == null || !auth.startsWith('Bearer ') ||
          !_authorizedTokens.contains(auth.substring(7))) {
        await _write(response, 401, {'error': 'Pairing required.'});
        return;
      }
      if (request.method == 'GET' && request.uri.path == '/state') {
        await _write(response, 200, {
          'name': _deviceName,
          'player': playerStatus?.call() ?? <String, Object?>{},
        });
        return;
      }
      if (request.method == 'POST' && request.uri.path == '/cast') {
        final command = LanCastRequest.parse(await _readJson(request));
        if (command == null) {
          await _write(response, 400, {'error': 'Invalid media identity.'});
          return;
        }
        final handler = onCastRequest;
        if (handler == null) {
          await _write(response, 503, {'error': 'Receiver is not ready.'});
          return;
        }
        final result = await handler(command)
            .timeout(const Duration(seconds: 55));
        await _write(response, result['accepted'] == true ? 200 : 422,
            result);
        return;
      }
      if (request.method == 'POST' && request.uri.path == '/command') {
        final payload = await _readJson(request);
        final name = payload['command'];
        final command = name is String
            ? LanRemoteProtocol.parseCommand(name) : null;
        if (command == null) {
          await _write(response, 400, {'error': 'Unknown command.'});
          return;
        }
        final handled = onPlayerCommand?.call(command) ?? false;
        if (!handled) onNavigationCommand?.call(command);
        await _write(response, 200, {'ok': true});
        return;
      }
      await _write(response, 404, {'error': 'Not found.'});
    } catch (error) {
      debugPrint('[LAN Remote] Invalid request: $error');
      try {
        await _write(response, 400, {'error': 'Invalid remote request.'});
      } catch (_) {
        try { await response.close(); } catch (_) {}
      }
    }
  }

  Future<Map<String, dynamic>> _readJson(HttpRequest request) async {
    if (request.contentLength > 2048) {
      throw const FormatException('Request too large');
    }
    final bytes = <int>[];
    await for (final chunk in request) {
      bytes.addAll(chunk);
      if (bytes.length > 2048) {
        throw const FormatException('Request too large');
      }
    }
    final parsed = jsonDecode(utf8.decode(bytes));
    if (parsed is! Map<String, dynamic>) {
      throw const FormatException('Expected JSON object');
    }
    return parsed;
  }

  Future<void> _write(HttpResponse response, int status,
      Map<String, Object?> payload) async {
    response.statusCode = status;
    response.write(jsonEncode(payload));
    await response.close();
  }

  Future<Map<String, dynamic>> _request(
      LanRemotePeer peer, String method, String path, {
      Map<String, Object?>? body, String? token,
      Duration responseTimeout = const Duration(seconds: 5)}) async {
    if (!LanRemoteProtocol.validLanAddress(peer.address) ||
        peer.port != LanRemoteProtocol.httpPort) {
      throw const FormatException('Enter a private Wi-Fi IPv4 address.');
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 4);
    try {
      final uri = Uri(scheme: 'http', host: peer.address,
          port: peer.port, path: path);
      final request = await client.openUrl(method, uri)
          .timeout(const Duration(seconds: 5));
      if (token != null) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }
      final response = await request.close()
          .timeout(responseTimeout);
      final text = await utf8.decoder.bind(response).join()
          .timeout(responseTimeout);
      final payload = jsonDecode(text);
      if (payload is! Map<String, dynamic>) {
        throw const FormatException('Invalid response');
      }
      if (response.statusCode != 200) {
        throw StateError(payload['error']?.toString() ??
            'Receiver returned HTTP ' + response.statusCode.toString());
      }
      return payload;
    } on SocketException catch (error) {
      debugPrint('[LAN Remote] Connection refused: $error');
      throw StateError(
          'iPad is unreachable. Keep PlayTorrio open on the same Wi-Fi.');
    } on TimeoutException {
      throw StateError(
          'iPad timed out. Check Wi-Fi and receiver mode.');
    } finally {
      client.close(force: true);
    }
  }

  Future<LanRemoteSession> pair(LanRemotePeer peer, String pin) async {
    if (!LanRemoteProtocol.validCode(pin)) {
      throw const FormatException('Enter the six-digit code on the iPad.');
    }
    final payload = await _request(
        peer, 'POST', '/pair', body: {'pin': pin});
    final token = payload['token'];
    if (token is! String || token.length < 32) {
      throw const FormatException('Receiver did not return a valid session.');
    }
    final name = payload['name'];
    return LanRemoteSession(
      peer: LanRemotePeer(
        name: name is String && name.isNotEmpty ? name : peer.name,
        address: peer.address),
      token: token,
    );
  }

  Future<void> send(
      LanRemoteSession session, LanRemoteCommand command) async {
    await _request(session.peer, 'POST', '/command',
        token: session.token, body: {'command': command.name});
  }

  Future<Map<String, dynamic>> sendCast(
      LanRemoteSession session, LanCastRequest request) async {
    final response = await _request(session.peer, 'POST', '/cast',
        token: session.token, body: request.toJson(),
        responseTimeout: const Duration(seconds: 60));
    if (response['accepted'] != true) {
      throw StateError('iPad did not accept the media request.');
    }
    return response;
  }

  Future<Map<String, dynamic>> readState(LanRemoteSession session) {
    return _request(
        session.peer, 'GET', '/state', token: session.token);
  }
}
