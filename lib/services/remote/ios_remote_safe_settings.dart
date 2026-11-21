import 'package:flutter/foundation.dart';

import '../player/player_settings.dart';

/// Typed, allowlisted user settings. No arbitrary preference key reads/writes.
/// Existing PlayerSettings setters are authoritative for persistence.
abstract final class IosRemoteSafeSettings {
  static const supported = <String>[
    'subtitleFontSize',
    'subtitleScale',
    'subtitleBold',
    'subtitleItalic',
    'subtitlePosition',
  ];

  static Map<String, Object?> inspect() => <String, Object?>{
    'accepted': true,
    'supported': supported,
    'settings': <String, Object?>{
      'subtitleFontSize': PlayerSettings.subFontSize.value,
      'subtitleScale': PlayerSettings.subScale.value,
      'subtitleBold': PlayerSettings.subBold.value,
      'subtitleItalic': PlayerSettings.subItalic.value,
      'subtitlePosition': PlayerSettings.subPos.value,
    },
    'effectiveOnNextPlayback': true,
  };

  static Future<Map<String, Object?>> update(
      Map<String, dynamic> args) async {
    if (args.length != 2 ||
        !args.containsKey('setting') || !args.containsKey('value')) {
      return <String, Object?>{
        'accepted': false, 'reason': 'invalid_settings_request',
      };
    }
    final key = args['setting'];
    final value = args['value'];
    if (key is! String || !supported.contains(key)) {
      return <String, Object?>{
        'accepted': false, 'reason': 'unsupported_setting',
      };
    }
    try {
      switch (key) {
        case 'subtitleFontSize':
          if (value is! int || value < 14 || value > 80) {
            return <String, Object?>{
              'accepted': false, 'reason': 'invalid_setting_value',
            };
          }
          await PlayerSettings.setSubFontSize(value);
        case 'subtitleScale':
          if (value is! num || value < 0.5 || value > 3) {
            return <String, Object?>{
              'accepted': false, 'reason': 'invalid_setting_value',
            };
          }
          await PlayerSettings.setSubScale(value.toDouble());
        case 'subtitleBold':
          if (value is! bool) return <String, Object?>{
            'accepted': false, 'reason': 'invalid_setting_value',
          };
          await PlayerSettings.setSubBold(value);
        case 'subtitleItalic':
          if (value is! bool) return <String, Object?>{
            'accepted': false, 'reason': 'invalid_setting_value',
          };
          await PlayerSettings.setSubItalic(value);
        case 'subtitlePosition':
          if (value is! num || value < 0 || value > 100) {
            return <String, Object?>{
              'accepted': false, 'reason': 'invalid_setting_value',
            };
          }
          await PlayerSettings.setSubPos(value.toDouble());
      }
      final checked = inspect();
      final settings = checked['settings'] as Map<String, Object?>;
      return <String, Object?>{
        'accepted': settings[key] == value ||
            value is num && settings[key] is num &&
                ((settings[key] as num) - value).abs() < 0.011,
        'setting': key,
        'value': settings[key],
        'effectiveOnNextPlayback': true,
      };
    } catch (error) {
      debugPrint('[IosRemoteSafeSettings] Update: ${error.runtimeType}');
      return <String, Object?>{
        'accepted': false, 'reason': 'setting_update_failed',
        'errorClass': error.runtimeType.toString(),
      };
    }
  }
}
