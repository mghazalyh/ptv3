import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;

/// Disk-backed, privacy-filtered diagnostics for Windows MPV Night Mode.
///
/// Records native MPV audio-filter messages, not application media URLs,
/// metadata, subtitles, cookies, credentials or HTTP headers. A bounded
/// current file and one previous file are retained per Windows user.
class NightModeDiagnostics {
  static final NightModeDiagnostics instance = NightModeDiagnostics(
    directory: Directory(defaultDirectoryPath),
    enabled: !kIsWeb && Platform.isWindows,
    requireDebugOptIn: true,
  );

  static const String debugModePreferenceKey = 'player_debug_mode_enabled';
  static final ValueNotifier<bool> debugModeEnabled = ValueNotifier<bool>(false);

  /// Persisted opt-in. If OFF we never create or append a diagnostic file.
  static Future<void> initializeDebugMode() async {
    final prefs = await SharedPreferences.getInstance();
    debugModeEnabled.value = prefs.getBool(debugModePreferenceKey) ?? false;
    if (debugModeEnabled.value) await instance.start();
  }

  static Future<void> setDebugMode(bool enabled) async {
    if (!enabled) {
      // Stop future MPV callbacks immediately, even while prefs are saving.
      debugModeEnabled.value = false;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(debugModePreferenceKey, enabled);
    if (enabled) {
      debugModeEnabled.value = true;
      await instance.start();
    }
  }

  static const int maxBytes = 512 * 1024;
  static const String filename = 'night-mode-diagnostics.log';
  static const String previousFilename = 'night-mode-diagnostics.previous.log';

  final Directory directory;
  final bool enabled;
  final bool requireDebugOptIn;
  bool get isActive => enabled &&
      (!requireDebugOptIn || debugModeEnabled.value);
  Future<void> _pending = Future<void>.value();
  bool _started = false;

  NightModeDiagnostics({
    required this.directory,
    required this.enabled,
    this.requireDebugOptIn = false,
  });

  static String get defaultDirectoryPath {
    final env = Platform.environment;
    final local = env['LOCALAPPDATA'];
    final profile = env['USERPROFILE'];
    final root = local != null && local.isNotEmpty
        ? local
        : profile != null && profile.isNotEmpty
            ? p.join(profile, 'AppData', 'Local')
            : Directory.systemTemp.path;
    return p.join(root, 'PlayTorrio', 'logs');
  }

  String get filePath => p.join(directory.path, filename);
  String get previousFilePath => p.join(directory.path, previousFilename);

  Future<void> start() async {
    if (!isActive || _started) return;
    _started = true;
    try {
      await directory.create(recursive: true);
      await _rotateIfNeeded();
      await record(
        'session',
        'started; platform=windows; '
        'commit=${const String.fromEnvironment('PLAYTORRIO_COMMIT', defaultValue: 'unknown')}; '
        'run=${const String.fromEnvironment('PLAYTORRIO_RUN', defaultValue: 'unknown')}',
      );
      await flush();
    } catch (error) {
      debugPrint('[NightModeDiagnostics] Failed to initialize: ${error.runtimeType}');
    }
  }

  /// Asynchronous writes are serialized to prevent interleaved MPV callbacks.
  Future<void> record(String category, String detail) {
    if (!isActive || !_started) return Future<void>.value();
    final safeCategory = sanitize(category);
    final safeDetail = sanitize(detail);
    final line = '${DateTime.now().toUtc().toIso8601String()} '
        '[${safeCategory.isEmpty ? 'event' : safeCategory}] $safeDetail\n';
    _pending = _pending.then((_) async {
      // Settings may have changed while this entry was waiting in the queue.
      if (!isActive) return;
      try {
        await directory.create(recursive: true);
        await _rotateIfNeeded(incomingBytes: line.length * 4);
        await File(filePath).writeAsString(line, mode: FileMode.append, flush: true);
      } catch (error) {
        debugPrint('[NightModeDiagnostics] Write failed: ${error.runtimeType}');
      }
    });
    return _pending;
  }

  /// Capture only audio engine/filter context, avoiding general playback logs.
  Future<void> recordMpv({
    required String prefix,
    required String level,
    required String message,
  }) async {
    if (!isActive || !shouldCaptureMpv(prefix, message)) return;
    await record('mpv/${sanitize(prefix)}/${sanitize(level)}', message);
  }

  Future<void> flush() => _pending;

  Future<void> _rotateIfNeeded({int incomingBytes = 0}) async {
    final current = File(filePath);
    if (!await current.exists()) return;
    if (await current.length() + incomingBytes <= maxBytes) return;
    final previous = File(previousFilePath);
    if (await previous.exists()) await previous.delete();
    await current.rename(previousFilePath);
  }

  static bool shouldCaptureMpv(String prefix, String text) {
    final module = prefix.toLowerCase();
    final message = text.toLowerCase();
    const keywords = <String>[
      'acompressor',
      'lavfi',
      'avfilter',
      'audio filter',
      'audio-filter',
      'filter graph',
      'filtergraph',
      'resample',
      'afilter',
      'audio format',
      'audio output',
      'failed to initialize',
      'could not create filter',
    ];
    if (keywords.any(message.contains)) return true;
    return module == 'af' ||
        module.startsWith('af/') ||
        module == 'ao' ||
        module.startsWith('ao/') ||
        module == 'ad' ||
        module.startsWith('ad/') ||
        module.startsWith('ffmpeg/audio');
  }

  /// Log redaction is intentionally aggressive. Personal media identity and
  /// arbitrary MPV parameters must never be written to disk.
  @visibleForTesting
  static String sanitize(String source) {
    var safe = source
        .replaceAll(RegExp(r'[\r\n\t]+'), ' ')
        .replaceAll(RegExp(r'\b(?:https?|rtsp|rtmp|ftp|file|magnet)://?[^\s\x27\x22<>]+', caseSensitive: false), '[REDACTED_URL]')
        .replaceAll(RegExp(r'\bmagnet:\?[^\s\x27\x22<>]+', caseSensitive: false), '[REDACTED_URL]')
        .replaceAll(RegExp(r'\b[a-z]:[\\/][^\s\x27\x22<>]+', caseSensitive: false), '[REDACTED_PATH]')
        .replaceAll(RegExp(r'(?:^|\s)/(?:home|users|mnt|media|tmp|var|storage|sdcard|private)/[^\s\x27\x22<>]+', caseSensitive: false), ' [REDACTED_PATH]')
        .replaceAll(RegExp(r'\b(?:authorization|bearer|cookie|api[_-]?key|access[_-]?token|refresh[_-]?token|password|secret|signature|referer|origin)\s*[:=]\s*[^\s,;]+', caseSensitive: false), '[REDACTED_CREDENTIAL]')
        .replaceAll(RegExp(r'\b(?:token|key|pass|auth|sig|signature|cookie)=[^\s&]+', caseSensitive: false), '[REDACTED_CREDENTIAL]')
        .replaceAll(RegExp(r'\b(?:[a-f0-9]{48,}|[a-z0-9_-]{80,})\b', caseSensitive: false), '[REDACTED_VALUE]')
        .replaceAll(RegExp(r'(?:title|filename|path|url|uri)\s*[:=]\s*(?:\x22[^\x22]*\x22|\x27[^\x27]*\x27|[^\s,;]+)', caseSensitive: false), '[REDACTED_METADATA]');
    if (safe.length > 380) safe = '${safe.substring(0, 380)} [TRUNCATED]';
    return safe.trim();
  }
}
