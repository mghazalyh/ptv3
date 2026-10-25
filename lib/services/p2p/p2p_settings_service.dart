import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages settings for the built-in P2P (torrent) source (PlayTorrio)
/// and the startup privacy/ISP advisory modal.
class P2pSettingsService {
  P2pSettingsService._();

  static const String _kP2pEnabledKey = 'playtorrio_p2p_source_enabled';
  static const String _kNeverShowWarningKey = 'playtorrio_p2p_warning_never_show';
  static const String _kHttpEnabledKey = 'playtorrio_http_source_enabled';

  /// Whether the built-in P2P torrent source ('PlayTorrio') is enabled.
  /// When false, only direct HTTP streaming ('PlayTorrioHTTP') and external addons are used.
  static final ValueNotifier<bool> isP2pEnabled = ValueNotifier<bool>(true);
  static final ValueNotifier<bool> isHttpEnabled = ValueNotifier<bool>(true);

  /// Initializes the service and loads preferences from disk.
  static Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      isP2pEnabled.value = prefs.getBool(_kP2pEnabledKey) ?? true;
      isHttpEnabled.value = prefs.getBool(_kHttpEnabledKey) ?? true;
    } catch (e) {
      debugPrint('[P2pSettingsService] Error initializing: $e');
    }
  }

  /// Updates the P2P torrent source enabled state and persists it.
  static Future<void> setP2pEnabled(bool enabled) async {
    isP2pEnabled.value = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kP2pEnabledKey, enabled);
    } catch (e) {
      debugPrint('[P2pSettingsService] Error saving enabled state: $e');
    }
  }

  /// Controls built-in HTTP scrapers independently of external addons.
  /// When disabled, Torrentio / TorBox remain available as installed addons.
  static Future<void> setHttpEnabled(bool enabled) async {
    isHttpEnabled.value = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kHttpEnabledKey, enabled);
    } catch (e) {
      debugPrint('[P2pSettingsService] Failed to save HTTP toggle: $e');
    }
  }

  /// Checks if the startup P2P advisory modal should be displayed.
  static Future<bool> shouldShowWarning() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final neverShow = prefs.getBool(_kNeverShowWarningKey) ?? false;
      return !neverShow;
    } catch (e) {
      debugPrint('[P2pSettingsService] Error checking warning state: $e');
      return true;
    }
  }

  /// Sets whether the startup P2P advisory modal should never be shown again.
  static Future<void> setNeverShowWarning(bool neverShow) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kNeverShowWarningKey, neverShow);
    } catch (e) {
      debugPrint('[P2pSettingsService] Error saving never show state: $e');
    }
  }

  /// Resets the warning dialog state so it will show again on next startup.
  static Future<void> resetWarningPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kNeverShowWarningKey);
    } catch (e) {
      debugPrint('[P2pSettingsService] Error resetting warning preference: $e');
    }
  }
}
