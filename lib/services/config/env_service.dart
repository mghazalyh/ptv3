import 'dart:io';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service that dynamically resolves configuration and API secrets.
///
/// Supports:
/// 1. Compile-time defines via `--dart-define-from-file=.env` or `--dart-define=KEY=VAL`
/// 2. Runtime `.env` file parsing from root directory (Desktop / Debug)
/// 3. Bundled `.env` asset loading (Mobile)
/// 4. System environment variables (`Platform.environment`)
class EnvService {
  static final Map<String, String> _env = {};
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    // Desktop builds intentionally contain no OAuth secrets. Allow the Trakt
    // application credentials to be configured at runtime on each device.
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in ['TRAKT_CLIENT_ID', 'TRAKT_CLIENT_SECRET', 'SIMKL_CLIENT_ID']) {
        final value = prefs.getString('local_config_$key') ?? '';
        if (value.isNotEmpty) _env[key] = value;
      }
    } catch (_) {}

    // 1. Try reading from root filesystem .env (Desktop / Local dev)
    try {
      final file = File('.env');
      if (await file.exists()) {
        final lines = await file.readAsLines();
        _parseLines(lines);
        return;
      }
    } catch (_) {}

    // 2. Try reading from rootBundle asset if bundled
    try {
      final content = await rootBundle.loadString('.env');
      _parseLines(content.split('\n'));
      return;
    } catch (_) {}

    try {
      final content = await rootBundle.loadString('assets/.env');
      _parseLines(content.split('\n'));
      return;
    } catch (_) {}
  }

  static void _parseLines(List<String> lines) {
    for (var line in lines) {
      line = line.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final eqIdx = line.indexOf('=');
      if (eqIdx != -1) {
        final key = line.substring(0, eqIdx).trim();
        var val = line.substring(eqIdx + 1).trim();
        // Strip surrounding quotes if present
        if ((val.startsWith('"') && val.endsWith('"')) ||
            (val.startsWith("'") && val.endsWith("'"))) {
          val = val.substring(1, val.length - 1);
        }
        _env[key] = val;
      }
    }
  }

  static String get(String key, {String defaultValue = ''}) {
    if (_env.containsKey(key) && _env[key]!.isNotEmpty) {
      return _env[key]!;
    }
    // Fallback to Platform.environment
    try {
      final platVal = Platform.environment[key];
      if (platVal != null && platVal.isNotEmpty) return platVal;
    } catch (_) {}

    return defaultValue;
  }

  /// Store OAuth *application* credentials only on the current device.
  /// They are never added to GitHub source or a compiled installer.
  static Future<void> saveLocalTraktApplication(String id, String secret) async {
    final prefs = await SharedPreferences.getInstance();
    final values = <String, String>{
      'TRAKT_CLIENT_ID': id.trim(),
      'TRAKT_CLIENT_SECRET': secret.trim(),
    };
    for (final entry in values.entries) {
      if (entry.value.isEmpty) {
        await prefs.remove('local_config_${entry.key}');
        _env.remove(entry.key);
      } else {
        await prefs.setString('local_config_${entry.key}', entry.value);
        _env[entry.key] = entry.value;
      }
    }
  }

  /// The public Simkl app client ID is not a user's access token.
  /// Configuring this per installation avoids embedding a personal API
  /// application in a public release; the PIN flow stores the user token.
  static Future<void> saveLocalSimklClientId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    if (id.trim().isEmpty) {
      await prefs.remove('local_config_SIMKL_CLIENT_ID');
      _env.remove('SIMKL_CLIENT_ID');
    } else {
      await prefs.setString('local_config_SIMKL_CLIENT_ID', id.trim());
      _env['SIMKL_CLIENT_ID'] = id.trim();
    }
  }

  // Trakt Credentials (checks compile-time dart-define first, then runtime .env)
  static String get traktClientId {
    const compileVal = String.fromEnvironment('TRAKT_CLIENT_ID');
    if (compileVal.isNotEmpty) return compileVal;
    return get('TRAKT_CLIENT_ID');
  }

  static String get traktClientSecret {
    const compileVal = String.fromEnvironment('TRAKT_CLIENT_SECRET');
    if (compileVal.isNotEmpty) return compileVal;
    return get('TRAKT_CLIENT_SECRET');
  }

  // Simkl Credentials (checks compile-time dart-define first, then runtime .env)
  static String get simklClientId {
    const compileVal = String.fromEnvironment('SIMKL_CLIENT_ID');
    if (compileVal.isNotEmpty) return compileVal;
    return get('SIMKL_CLIENT_ID');
  }

  static String get simklClientSecret {
    const compileVal = String.fromEnvironment('SIMKL_CLIENT_SECRET');
    if (compileVal.isNotEmpty) return compileVal;
    return get('SIMKL_CLIENT_SECRET');
  }

  // Discord Rich Presence App ID (checks compile-time dart-define first, then runtime .env)
  static String get discordAppId {
    const compileVal = String.fromEnvironment('DISCORD_APP_ID');
    if (compileVal.isNotEmpty) return compileVal;
    return get('DISCORD_APP_ID');
  }
}
