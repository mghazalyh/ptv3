/// Pure playback-progress verification shared by remote recovery and
/// unattended plans. An accepted play command never proves decoded playback.
abstract final class IosRemotePlaybackVerification {
  static Map<String, Object?> compare(
    Map<String, Object?> before,
    Map<String, Object?> after, {
    required int sampleMs,
  }) {
    final live = after['isLive'] == true;
    final first = live && before['live'] is Map
        ? Map<String, Object?>.from(before['live'] as Map)
        : before;
    final last = live && after['live'] is Map
        ? Map<String, Object?>.from(after['live'] as Map)
        : after;
    final firstPosition = first['positionMs'];
    final lastPosition = last['positionMs'];
    final progress = firstPosition is num && lastPosition is num
        ? lastPosition - firstPosition : null;
    final active = after['playing'] == true &&
        after['buffering'] == false &&
        after['nativeOpening'] != true;
    final liveDecoded = !live ||
        last['videoWidth'] is num && (last['videoWidth'] as num) > 0 &&
        last['videoHeight'] is num && (last['videoHeight'] as num) > 0 &&
        last['trackCount'] is num && (last['trackCount'] as num) > 0;
    final moved = progress != null &&
        progress >= (sampleMs * 0.25).clamp(250, 3000);
    return <String, Object?>{
      'accepted': true,
      'verified': active && moved && liveDecoded,
      'isLive': live,
      'playerActive': active,
      'nativeVideoEvidence': live ? liveDecoded : null,
      'positionAdvanceMs': progress,
      'sampleMs': sampleMs,
      'reason': !active ? 'not_playing_or_buffering' :
          !liveDecoded ? 'native_video_not_verified' :
          !moved ? 'timeline_not_advancing' : 'playback_progress_verified',
      'before': <String, Object?>{
        'playing': before['playing'],
        'positionMs': firstPosition,
        'buffering': before['buffering'],
        'sourceAddon': before['sourceAddon'],
      },
      'after': <String, Object?>{
        'playing': after['playing'],
        'positionMs': lastPosition,
        'buffering': after['buffering'],
        'sourceAddon': after['sourceAddon'],
      },
    };
  }
}
