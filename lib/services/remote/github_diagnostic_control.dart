import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../my_list/github_library_cloud.dart';
import '../player/ios_audio_telemetry.dart';
import 'torriodb_write_queue.dart';

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
  @visibleForTesting
  static const preferencePendingReceipt =
      'github_diagnostic_control_pending_receipt_v1';
  static const pollInterval = Duration(seconds: 12);
  static const statusInterval = Duration(minutes: 3);

  final http.Client _client;
  final Future<String?> Function()? _tokenProvider;
  final ValueNotifier<bool> enabled = ValueNotifier<bool>(false);
  final ValueNotifier<String> status =
      ValueNotifier<String>('Remote diagnostics disabled');
  final Random _random = Random.secure();

  DiagnosticCommandHandler? onCommand;
  void Function(Map<String, dynamic>?)? onUiConfiguration;
  String? _lastUiSha;
  DateTime? _lastUiCheckAt;
  bool _uiPolling = false;
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
  String? get uiConfigurationPath => _deviceId == null
      ? null : '$root/ui/${_deviceId!}.json';
  String? get adaptiveSurfPath => _deviceId == null
      ? null : '$root/adaptive_surf/${_deviceId!}/config.json';
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

  /// Stop the external adaptive GitHub controller from an in-player button.
  /// The active workflow checks this config before issuing further commands.
  Future<Map<String, Object?>> stopAdaptiveSurf() async {
    await initialize();
    if (!enabled.value || adaptiveSurfPath == null) return <String, Object?>{
      'accepted': false, 'reason': 'remote_diagnostics_disabled'};
    try {
      final token = await _token();
      if (token == null || token.isEmpty) return <String, Object?>{
        'accepted': false, 'reason': 'credentials_unavailable'};
      final file = await _readFile(token, adaptiveSurfPath!);
      final config = file.document;
      if (config == null) return <String, Object?>{
        'accepted': false, 'reason': 'adaptive_plan_not_configured'};
      if (config['enabled'] == false) return <String, Object?>{
        'accepted': true, 'alreadyStopped': true};
      final revised = <String, Object?>{...config, 'enabled': false};
      await _writeFile(token, adaptiveSurfPath!, revised);
      return <String, Object?>{
        'accepted': true, 'stopped': true,
        'runId': config['runId']?.toString()};
    } catch (error) {
      debugPrint('[GithubDiagnosticControl] Stop surf: ${error.runtimeType}');
      return <String, Object?>{'accepted': false,
        'errorClass': error.runtimeType.toString()};
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
      String token, String path, Map<String, Object?> body) {
    // Telemetry uses the same Torriodb branch. Coordinate both uploaders,
    // not merely the command/heartbeat/matrix writes inside this controller.
    return TorriodbWriteQueue.instance.run<void>(
        () => _writeFileWithRetry(token, path, body));
  }

  Future<String?> _readExistingSha(String token, String path) async {
    final response = await _client.get(_uri(path), headers: _headers(token))
        .timeout(const Duration(seconds: 12));
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw StateError('GitHub read HTTP ${response.statusCode}');
    }
    final wrapper = jsonDecode(response.body);
    if (wrapper is! Map) {
      throw const FormatException('Invalid GitHub blob metadata');
    }
    return wrapper['sha']?.toString();
  }

  Future<void> _writeFileWithRetry(
      String token, String path, Map<String, Object?> body) async {
    final encoded = base64Encode(utf8.encode(jsonEncode(body)));
    for (var attempt = 0; attempt < 4; attempt++) {
      try {
        // Always re-read the SHA, including after an ambiguous PUT timeout:
        // the previous write may have reached GitHub before the socket failed.
        final previousSha = await _readExistingSha(token, path);
        final request = <String, Object?>{
          'branch': branch,
          'message': 'diagnostics(ios): unattended diagnostic receipt',
          'content': encoded,
          if (previousSha != null) 'sha': previousSha,
        };
        final response = await _client.put(
          Uri.https('api.github.com', '/repos/$repository/contents/$path'),
          headers: {..._headers(token), 'Content-Type': 'application/json'},
          body: jsonEncode(request),
        ).timeout(const Duration(seconds: 15));
        if (response.statusCode == 201 || response.statusCode == 200) return;

        final code = response.statusCode;
        final retryable = code == 409 || code == 429 ||
            code == 502 || code == 503 || code == 504 ||
            (code == 403 && response.headers['retry-after'] != null);
        if (!retryable || attempt == 3) {
          throw StateError('GitHub write HTTP $code');
        }
        final retryAfter =
            int.tryParse(response.headers['retry-after'] ?? '') ?? 0;
        final delay = retryAfter > 0
            ? Duration(seconds: retryAfter.clamp(1, 4).toInt())
            : Duration(milliseconds: 250 * (attempt + 1));
        debugPrint('[GithubDiagnosticControl] Retrying GitHub write '
            'after HTTP $code');
        await Future<void>.delayed(delay);
        continue;
      } on TimeoutException {
        if (attempt == 3) rethrow;
      } on IOException {
        if (attempt == 3) rethrow;
      } on http.ClientException {
        if (attempt == 3) rethrow;
      } on StateError catch (error) {
        // Never retry invalid credentials, malformed data or ordinary 4xx
        // failures; only transient GET failures are eligible here.
        final message = error.message.toString();
        final transientRead = RegExp(
            r'^GitHub read HTTP (429|500|502|503|504)$').hasMatch(message);
        if (!transientRead || attempt == 3) rethrow;
      }
      // Do not log URL, response body, credentials or provider headers.
      debugPrint('[GithubDiagnosticControl] Retrying transient upload '
          'transport failure');
      await Future<void>.delayed(
          Duration(milliseconds: 250 * (attempt + 1)));
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

  /// Bounded private evidence upload for owner-requested native visual checks.
  Future<void> publishVisualFile(
      String runId, String key, Map<String, Object?> payload) async {
    await initialize();
    if (!enabled.value || _deviceId == null) {
      throw StateError('Remote diagnostics not enabled');
    }
    if (!RegExp(r'^[A-Za-z0-9_-]{8,50}$').hasMatch(runId) ||
        !(key == 'status' ||
            RegExp(r'^(channel_[0-9]{1,3}|frame_[0-9]{1,3}_[0-9]{1,2})$')
                .hasMatch(key))) {
      throw const FormatException('Invalid visual evidence path');
    }
    if (utf8.encode(jsonEncode(payload)).length > 98000) {
      throw const FormatException('Visual evidence too large');
    }
    if (key.startsWith('frame_')) {
      final image = payload['imageBase64'];
      final bytes = payload['byteLength'];
      if (payload['mimeType'] != 'image/png' ||
          payload['nativeVerified'] != true ||
          image is! String || image.length > 86000 ||
          bytes is! int || bytes < 32 || bytes > 64000) {
        throw const FormatException('Invalid frame evidence');
      }
    } else if (payload.containsKey('imageBase64')) {
      throw const FormatException('Unexpected image data');
    }
    final token = await _token();
    if (token == null || token.isEmpty) {
      throw StateError('Torriodb credentials unavailable');
    }
    await _writeFile(token,
        '$root/visual/$_deviceId/$runId/$key.json', payload);
  }

  /// Immutable byte-range artifact chunks for resumable engineering exports.
  Future<void> publishJournalFile(String runId, String key,
      Map<String, Object?> payload) async {
    await initialize();
    if (!enabled.value || _deviceId == null) {
      throw StateError('Remote diagnostics not enabled');
    }
    if (!RegExp(r'^[A-Za-z0-9_-]{8,50}$').hasMatch(runId) ||
        !RegExp(r'^chunk_(current|previous|capture)_[0-9]{8}$').hasMatch(key)) {
      throw const FormatException('Invalid diagnostic artifact path');
    }
    if (utf8.encode(jsonEncode(payload)).length > 100000) {
      throw const FormatException('Diagnostic artifact too large');
    }
    final token = await _token();
    if (token == null || token.isEmpty) {
      throw StateError('Torriodb credentials unavailable');
    }
    await _writeFile(token,
        '$root/artifacts/$_deviceId/$runId/$key.json', payload);
  }

  /// A result is stored locally before network delivery, so a dropped upload
  /// cannot silently discard completed actions or cause them to execute twice.
  Future<void> _persistPending(
      SharedPreferences prefs, Map<String, Object?> pending) async {
    final encoded = jsonEncode(pending);
    if (utf8.encode(encoded).length > 262144) {
      throw const FormatException('Diagnostic receipt exceeds storage bound');
    }
    if (!await prefs.setString(preferencePendingReceipt, encoded)) {
      throw StateError('Could not persist diagnostic receipt');
    }
  }

  /// Resend undelivered receipts before accepting new commands. A persisted
  /// "executing" intent after process restart does not prove that a side effect
  /// happened. Publish "uncertain" instead of replaying that operation.
  Future<void> _flushPendingReceipt(
      String token, SharedPreferences prefs) async {
    final encoded = prefs.getString(preferencePendingReceipt);
    if (encoded == null) return;

    final decoded = jsonDecode(encoded);
    if (decoded is! Map) {
      throw const FormatException('Invalid stored diagnostic receipt');
    }
    final pending = Map<String, dynamic>.from(decoded);
    final id = pending['commandId'];
    final action = pending['action'];
    final state = pending['state'];
    if (pending['deviceId'] != _deviceId ||
        id is! String ||
        !RegExp(r'^[A-Za-z0-9_-]{8,100}$').hasMatch(id) ||
        action is! String ||
        !RegExp(r'^[a-z_]{2,45}$').hasMatch(action) ||
        (state != 'executing' && state != 'completed' &&
            state != 'failed' && state != 'uncertain')) {
      throw const FormatException('Invalid persisted command state');
    }

    // Repair the deduplication marker when a termination happened between
    // saving the intent and saving the last-command preference.
    if (_lastCommand != id) {
      if (!await prefs.setString(_preferenceLastCommand, id)) {
        throw StateError('Could not persist diagnostic command identifier');
      }
      _lastCommand = id;
    }

    Map<String, Object?> receipt = Map<String, Object?>.from(pending);
    if (state == 'executing') {
      receipt = <String, Object?>{
        'schema': 2,
        'deviceId': _deviceId,
        'commandId': id,
        'action': action,
        'state': 'uncertain',
        'startedAtUtc': pending['startedAtUtc'],
        'completedAtUtc': DateTime.now().toUtc().toIso8601String(),
        'result': <String, Object?>{
          'accepted': false,
          'reason': 'execution_interrupted_outcome_unknown',
        },
      };
      await _persistPending(prefs, receipt);
    }

    await _writeFile(token, receiptPath!, receipt);
    if (!await prefs.remove(preferencePendingReceipt)) {
      throw StateError('Could not clear delivered diagnostic receipt');
    }
    status.value = 'Last diagnostic command: $action (${receipt['state']})';
  }

  Future<void> _refreshUiConfiguration(String token, DateTime now) async {
    if (_uiPolling || uiConfigurationPath == null) return;
    _uiPolling = true;
    try {
      final ui = await _readFile(token, uiConfigurationPath!);
      if (_lastUiSha != ui.sha) {
        onUiConfiguration?.call(ui.document);
        _lastUiSha = ui.sha;
      }
      _lastUiCheckAt = now;
    } catch (error) {
      debugPrint('[GithubDiagnosticControl] UI: ${error.runtimeType}');
    } finally {
      _uiPolling = false;
    }
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
      final prefs = await SharedPreferences.getInstance();
      // Retry an older result even after its original command has expired.
      await _flushPendingReceipt(token, prefs);
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
      // Read the UI independently: its network latency must never delay
      // channel switching, playback verification, or command receipts.
      if (onUiConfiguration != null && uiConfigurationPath != null &&
          !_uiPolling && (_lastUiCheckAt == null ||
          now.difference(_lastUiCheckAt!) >= pollInterval)) {
        unawaited(_refreshUiConfiguration(token, now));
      }
      final command = (await _readFile(token, commandPath!)).document;
      if (command == null) return;
      if (!validCommand(command, deviceId: _deviceId!, now: now)) return;
      final id = command['id'] as String;
      if (_lastCommand == id) return;
      final action = command['action'] as String;
      final startedAtUtc = DateTime.now().toUtc().toIso8601String();
      await _persistPending(prefs, <String, Object?>{
        'schema': 2,
        'deviceId': _deviceId,
        'commandId': id,
        'action': action,
        'state': 'executing',
        'startedAtUtc': startedAtUtc,
      });
      if (!await prefs.setString(_preferenceLastCommand, id)) {
        throw StateError('Could not persist diagnostic command identifier');
      }
      _lastCommand = id;
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
      // Never repeat a completed action just because GitHub upload failed.
      await _persistPending(prefs, <String, Object?>{
        'schema': 2,
        'deviceId': _deviceId,
        'commandId': id,
        'action': action,
        'state': outcome,
        'startedAtUtc': startedAtUtc,
        'completedAtUtc': DateTime.now().toUtc().toIso8601String(),
        'result': result,
      });
      await _flushPendingReceipt(token, prefs);
      _lastStatusAt = DateTime.now().toUtc();
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
    onUiConfiguration = null;
    _client.close();
    status.dispose();
    enabled.dispose();
  }
}
