import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Native process counters on iOS; no power-hungry monitoring timers.
abstract final class IosNativeProcessMetrics {
  static const MethodChannel _channel =
      MethodChannel('playtorrio/device_diagnostics');

  static Future<Map<String, Object?>> capture() async {
    if (!Platform.isIOS) {
      return {'accepted': false, 'reason': 'ios_only'};
    }
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>(
          'processMetrics');
      if (raw == null) {
        return {'accepted': false, 'reason': 'native_metrics_unavailable'};
      }
      return <String, Object?>{
        'accepted': true,
        'processMetrics': Map<String, Object?>.from(raw),
      };
    } on PlatformException catch (error) {
      debugPrint('[NativeProcessMetrics] Platform: ${error.code}');
      return {
        'accepted': false,
        'reason': 'native_metrics_failed',
        'errorCode': error.code,
        'error': error.message,
      };
    } catch (error) {
      debugPrint('[NativeProcessMetrics] ${error.runtimeType}');
      return {
        'accepted': false,
        'reason': 'native_metrics_unavailable',
        'errorClass': error.runtimeType.toString(),
      };
    }
  }
}
