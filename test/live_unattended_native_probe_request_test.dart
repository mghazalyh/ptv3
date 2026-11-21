import 'package:flutter_test/flutter_test.dart';
import 'package:playtorrio/services/player/live_tv/live_unattended_native_probe_request.dart';

void main() {
  test('Accepts only exact channel identity, installed addon host and index', () {
    final request = LiveUnattendedNativeProbeRequest.parse({
      'channelId': 'nltv:us:CineRomantico.us',
      'addonHost': 'PTV3-LIVETV-ADDON.PAGES.DEV',
      'sourceIndex': 2,
    });
    expect(request, isNotNull);
    expect(request!.channelId, 'nltv:us:CineRomantico.us');
    expect(request.addonHost, 'ptv3-livetv-addon.pages.dev');
    expect(request.sourceIndex, 2);
    expect(LiveUnattendedNativeProbeRequest.parse({
      'channelId': 'iptv:channel_100',
      'addonHost': 'installed.example',
    })?.sourceIndex, 0);
  });

  test('Rejects URLs, arbitrary headers and unbounded probing', () {
    final base = {
      'channelId': 'nltv:us:Charge.us',
      'addonHost': 'installed.example',
    };
    expect(LiveUnattendedNativeProbeRequest.parse({...base,
      'url': 'https://untrusted.example/watch.m3u8'}), isNull);
    expect(LiveUnattendedNativeProbeRequest.parse({...base,
      'headers': {'Authorization': 'secret'}}), isNull);
    expect(LiveUnattendedNativeProbeRequest.parse({...base,
      'sourceIndex': 8}), isNull);
    expect(LiveUnattendedNativeProbeRequest.parse({...base,
      'sourceIndex': -1}), isNull);
    expect(LiveUnattendedNativeProbeRequest.parse({...base,
      'sourceIndex': '0'}), isNull);
  });

  test('Rejects malformed or non-live media identifiers and addon hosts', () {
    final base = {
      'channelId': 'nltv:us:Charge.us',
      'addonHost': 'installed.example',
    };
    for (final id in [
      'tt1234567', 'nltv:../../secret', 'iptv://host/stream',
      'https://any.example', 'nltv:us:Channel?apiKey=secret',
    ]) {
      expect(LiveUnattendedNativeProbeRequest.parse({
        ...base, 'channelId': id,
      }), isNull, reason: id);
    }
    for (final host in [
      'https://installed.example', 'installed.example:443',
      'user:pass@installed.example', '../installed.example',
      '.installed.example', 'installed..example',
    ]) {
      expect(LiveUnattendedNativeProbeRequest.parse({
        ...base, 'addonHost': host,
      }), isNull, reason: host);
    }
  });
}
