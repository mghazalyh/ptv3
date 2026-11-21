/// A strictly bounded, identity-only native decoder diagnostic request.
///
/// The request never accepts media URLs, HTTP headers, cookies or arbitrary
/// addon endpoints. The device resolves the source from an enabled, installed
/// Stremio addon before opening a separate muted native test player.
class LiveUnattendedNativeProbeRequest {
  const LiveUnattendedNativeProbeRequest({
    required this.channelId,
    required this.addonHost,
    required this.sourceIndex,
  });

  final String channelId;
  final String addonHost;
  final int sourceIndex;

  static LiveUnattendedNativeProbeRequest? parse(
      Map<String, dynamic> raw) {
    const allowed = <String>{'channelId', 'addonHost', 'sourceIndex'};
    if (raw.keys.any((key) => !allowed.contains(key))) return null;
    final id = raw['channelId'];
    final host = raw['addonHost'];
    final index = raw['sourceIndex'] ?? 0;
    if (id is! String || id.length < 4 || id.length > 180 ||
        !(id.startsWith('nltv:') || id.startsWith('iptv:')) ||
        !RegExp(r'^[a-zA-Z0-9:_./%-]+$').hasMatch(id) ||
        id.contains('..') || id.contains('//') ||
        host is! String || host.length < 4 || host.length > 253 ||
        !RegExp(r'^[a-zA-Z0-9.-]+$').hasMatch(host) ||
        host.startsWith('.') || host.endsWith('.') ||
        host.contains('..') ||
        index is! int || index < 0 || index > 7) {
      return null;
    }
    return LiveUnattendedNativeProbeRequest(
      channelId: id,
      addonHost: host.toLowerCase(),
      sourceIndex: index,
    );
  }
}
