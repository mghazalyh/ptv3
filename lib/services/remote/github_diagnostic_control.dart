import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../my_list/github_library_cloud.dart';
import '../player/ios_audio_telemetry.dart';

typedef DiagnosticCommandHandler = Future<Map<String, Object?>> Function(
    String action, Map<String, dynamic> args);

/// GitHub-backed, unattended owner diagnostic control of the PlayTorrio app.
///
/// Nothing is executed by GitHub itself. The running iOS client reads a single
/// device-scoped command document, dispatches it on the Flutter isolate and
/// writes a receipt. No external process, shell, arbitrary Dart or JS eval,
/// credentials, raw stream URL or filesystem operation is exposed.
///
/// Opt in once in Settings; commands thereafter require no further prompts.
/// This controller cannot run while iOS suspends the app in the background.
class GithubDiagnosticControl {
  GithubDiagnosticControl._({
    http.Client? client,
    Future<String?> Function()? tokenProvider,
  })  : _client = client ?? http.Client(),
        _tokenProvider = tokenProvider;

  @visibleForTesting
  factory GithubDiagnosticControl.forTesting({
    required http.Client client,
    required Future<String?> Function() tokenProvider,
  }) => GithubDiagnosticControl._(
        client: client, tokenProvider: tokenProvider);

  static final GithubDiagnosticControl instance = GithubDiagnosticControl._();

  static const repository = 'mghazalyh/torriodb';
  static const branch = 'main';
  static const root = 'playtorrio/control/ios';
  static const preferenceEnabled = 'github_diagnostic_control_enabled_v1';
  static const _preferenceDeviceId = 'github_diagnostic_control_id_v1';
  static const _preferenceLastCommand = 'github_diagnostic_control_seen_v1';
  static const pollInterval = Duration(seconds: 12);
  static const statusInterval = Duration(minutes: 3);

  final http.Client _client;
  final Future<String?> Function()? _tokenProvider;
  final ValueNotifier<bool> enabled = ValueNotifier<bool>(false);
  final ValueNotifier<String> status =
      ValueNotifier<String>('Remote diagnostics disabled');
  final Random _random = Random.secure();

  DiagnosticCommandHandler? onCommand;
  DiagnosticCommandHandler? onPlayerCommand;
  bool forceTestPlatform = false;

  Timer? _timer;
  bool _started = false;
  bool _polling = false;
  bool _initialized = false;
  String? _deviceId;
  String? _lastCommand;
  DateTime? _lastStatusAt;

  String? get deviceId => _deviceId;
  String? get commandPath => _deviceId == null
      ? null
      : '$root/commands/${_deviceId!}.json';
  String? get receiptPath => _deviceId == null
      ? null
      : '$root/receipts/${_deviceId!}.json';
  String? get devicePath => _deviceId == null
      ? null
      : '$root/devices/${_deviceId!}.json';

  static String createDeviceId(Random rng) =>
      List<int>.generate(16, (_) => rng.nextInt(256))
          .map((number) => number.toRadixString(16).padLeft(2, '0'))
          .join();

  @visibleForTesting
  static bool validCommand(Map<String, dynamic> command,
      {required String deviceId, required DateTime now}) {
    if (command['deviceId'] != deviceId) return false;
    final id = command['id'];
    if (id is! String ||
        !RegExp(r'^[A-Za-z0-9_-]{8,100}$').hasMatch(id)) return false;
    final action = command['action'];
    if (action is! String ||
        !RegExp(r'^[a-z_]{2,45}$').hasMatch(action)) return false;
    if (command['args'] != null && command['args'] is! Map) return false;
    final timestamp = DateTime.tryParse(
        command['createdAtUtc']?.toString() ?? '')?.toUtc();
    if (timestamp == null) return false;
    final age = now.toUtc().difference(timestamp);
    // Prevent stale commands from unexpectedly replaying after an offline day.
    return age >= const Duration(minutes: -2) &&
        age <= const Duration(hours: 1);
  }

  Future<void> initialize() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_preferenceDeviceId);
    if (stored == null ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(stored)) {
      _deviceId = createDeviceId(_random);
      await prefs.setString(_preferenceDeviceId, _deviceId!);
    } else {
      _deviceId = stored;
    }
    _lastCommand = prefs.getString(_preferenceLastCommand);
    enabled.value = prefs.getBool(preferenceEnabled) ?? false;
    status.value = enabled.value
        ? 'Unattended diagnostics enabled'
        : 'Remote diagnostics disabled';
    _initialized = true;
  }

  Future<void> setEnabled(bool value) async {
    await initialize();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(preferenceEnabled, value);
    enabled.value = value;
    status.value = value
        ? 'Unattended diagnostics enabled'
        : 'Remote diagnostics disabled';
    if (value) {
      start();
      unawaited(pollNow());
    } else {
      _lastStatusAt = null;
    }
  }

  void start() {
    if (_started || (!Platform.isIOS && !forceTestPlatform)) return;
    _started = true;
    _timer = Timer.periodic(pollInterval, (_) => unawaited(pollNow()));
    unawaited(pollNow());
  }

  Future<String?> _token() async {
    if (_tokenProvider != null) return _tokenProvider();
    await GitHubLibraryCloud.instance.initialize();
    return GitHubLibraryCloud.instance.progressAccessToken;
  }

  Uri _uri(String path) =>
      Uri.https('api.github.com', '/repos/$repository/contents/$path',
          const {'ref': branch});

  Map<String, String> _headers(String token) => <String, String>{
        'Authorization': 'Bearer $token',
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
        'User-Agent': 'PlayTorrio-unattended-diagnostic-control',
        'Cache-Control': 'no-store',
      };

  Future<({Map<String, dynamic>? document, String? sha})> _readFile(
      String token, String path) async {
    final response = await _client.get(_uri(path), headers: _headers(token))
        .timeout(const Duration(seconds: 12));
    if (response.statusCode == 404) return (document: null, sha: null);
    if (response.statusCode != 200) {
      throw StateError('GitHub read HTTP ${response.statusCode}');
    }
    final wrapper = jsonDecode(response.body);
    if (wrapper is! Map || wrapper['content'] is! String) {
      throw const FormatException('Invalid GitHub contents response');
    }
    final bytes = base64Decode((wrapper['content'] as String)
        .replaceAll(RegExp(r'\s+'), ''));
    if (bytes.length > 32768) throw const FormatException('Command too large');
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) throw const FormatException('Invalid command JSON');
    return (
      document: Map<String, dynamic>.from(decoded),
      sha: wrapper['sha']?.toString(),
    );
  }

  Future<void> _writeFile(
      String token, String path, Map<String, Object?> body) async {
    final existing = await _readFile(token, path);
    final request = <String, Object?>{
      'branch': branch,
      'message': 'diagnostics(ios): unattended diagnostic receipt',
      'content': base64Encode(utf8.encode(jsonEncode(body))),
      if (existing.sha != null) 'sha': existing.sha,
    };
    final response = await _client.put(
      Uri.https('api.github.com', '/repos/$repository/contents/$path'),
      headers: {..._headers(token), 'Content-Type': 'application/json'},
      body: jsonEncode(request),
    ).timeout(const Duration(seconds: 15));
    if (response.statusCode != 201 && response.statusCode != 200) {
      throw StateError('GitHub write HTTP ${response.statusCode}');
    }
  }

  /// Publish only bounded private Live TV matrix evidence.
  Future<void> publishMatrixFile(String runId, String key,
      Map<String, Object?> result) async {
    await initialize();
    if (!enabled.value || _deviceId == null) {
      throw StateError('Remote diagnostics not enabled');
    }
    if (!RegExp(r'^[A-Za-z0-9_-]{8,50}$').hasMatch(runId) ||
        !(key == 'status' ||
            RegExp(r'^candidate_[0-9]+_[0-9]+$').hasMatch(key))) {
      throw const FormatException('Invalid matrix output path');
    }
    if (jsonEncode(result).length > 12000) {
      throw const FormatException('Matrix result too large');
    }
    final token = await _token();
    if (token == null || token.isEmpty) {
      throw StateError('Torriodb credentials unavailable');
    }
    await _writeFile(token,
        '$root/matrix/$_deviceId/$runId/$key.json', result);
  }

  Future<void> pollNow() async {
    await initialize();
    if ((!Platform.isIOS && !forceTestPlatform) ||
        !enabled.value || _polling || commandPath == null) return;
    _polling = true;
    try {
      final token = await _token();
      if (token == null || token.isEmpty) {
        status.value = 'GitHub Library credentials unavailable';
        return;
      }
      final now = DateTime.now().toUtc();
      if (_lastStatusAt == null ||
          now.difference(_lastStatusAt!) >= statusInterval) {
        try {
          await _writeFile(token, devicePath!, <String, Object?>{
            'schema': 1,
            'deviceId': _deviceId,
            'platform': 'ios',
            'buildCommit': IosAudioTelemetry.buildCommit,
            'buildRun': IosAudioTelemetry.buildRun,
            'state': 'ready',
            'enabled': enabled.value,
            'observedAtUtc': now.toIso8601String(),
          });
          _lastStatusAt = now;
        } catch (error) {
          debugPrint('[GithubDiagnosticControl] Heartbeat: ${error.runtimeType}');
        }
      }
      final command = (await _readFile(token, commandPath!)).document;
      if (command == null) return;
      if (!validCommand(command, deviceId: _deviceId!, now: now)) return;
      final id = command['id'] as String;
      if (_lastCommand == id) return;
      _lastCommand = id;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_preferenceLastCommand, id);
      final action = command['action'] as String;
      Map<String, Object?> result;
      String outcome = 'completed';
      try {
        final payload = command['args'];
        final args = payload is Map
            ? Map<String, dynamic>.from(payload)
            : <String, dynamic>{};
        result = await onCommand?.call(action, args) ??
            <String, Object?>{'accepted': false, 'reason': 'no_handler'};
      } catch (error) {
        outcome = 'failed';
        result = <String, Object?>{'errorClass': error.runtimeType.toString()};
        debugPrint('[GithubDiagnosticControl] Action failed: ${error.runtimeType}');
      }
      // Only fixed app-state results should be returned by the handler.
      await _writeFile(token, receiptPath!, <String, Object?>{
        'schema': 1,
        'deviceId': _deviceId,
        'commandId': id,
        'action': action,
        'state': outcome,
        'completedAtUtc': DateTime.now().toUtc().toIso8601String(),
        'result': result,
      });
      _lastStatusAt = DateTime.now().toUtc();
      status.value = 'Last diagnostic command: $action ($outcome)';
    } catch (error) {
      status.value = 'Diagnostic polling failed: ${error.runtimeType}';
      debugPrint('[GithubDiagnosticControl] Poll failed: ${error.runtimeType}');
    } finally {
      _polling = false;
    }
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _started = false;
    onCommand = null;
    _client.close();
    status.dispose();
    enabled.dispose();
  }
}
