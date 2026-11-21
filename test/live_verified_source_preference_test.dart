import 'package:flutter_test/flutter_test.dart';
import 'package:playtorrio/models/stream/stream_model.dart';
import 'package:playtorrio/services/player/live_tv/live_verified_source_preference.dart';

void main() {
  tearDown(LiveVerifiedSourcePreference.clearForTesting);

  StreamSource src(String url, {String addon = 'Live TV'}) =>
      StreamSource(url: url, addonName: addon);

  test('Native-verified exact URL is promoted without losing other sources',
      () {
    final first = src('https://jmp2.uk/blocked.m3u8');
    final verified = src('https://jmp2.uk/working.m3u8');
    final third = src('https://unbeaten-tcl.amagi.tv/live.m3u8');
    LiveVerifiedSourcePreference.remember(
        channelId: 'nltv:us:Channel.us', verifiedSource: verified);
    final ordered = LiveVerifiedSourcePreference.prioritize(
        'nltv:us:Channel.us', [first, verified, third]);

    expect(ordered, [same(verified), same(first), same(third)]);
    expect(
      LiveVerifiedSourcePreference.prioritize(
          'nltv:us:Other.us', [first, verified, third]),
      [same(first), same(verified), same(third)],
    );
  });

  test('Same host, different URL cannot receive false preference', () {
    final old = src('https://jmp2.uk/pathA.m3u8');
    final replacement = src('https://jmp2.uk/pathB.m3u8');
    final second = src('https://jmp2.uk/pathC.m3u8');
    LiveVerifiedSourcePreference.remember(
      channelId: 'nltv:us:Channel.us', verifiedSource: old);
    expect(
      LiveVerifiedSourcePreference.prioritize(
        'nltv:us:Channel.us', [replacement, second]),
      [same(replacement), same(second)],
    );
  });

  test('Source must belong to same addon, even with identical URL', () {
    final verified = src('https://example.test/master.m3u8', addon: 'TV A');
    final other = src('https://example.test/master.m3u8', addon: 'TV B');
    final backup = src('https://example.test/other.m3u8');
    LiveVerifiedSourcePreference.remember(
      channelId: 'nltv:us:Channel.us', verifiedSource: verified);
    final sorted = LiveVerifiedSourcePreference.prioritize(
        'nltv:us:Channel.us', [backup, other]);
    expect(sorted, [same(backup), same(other)]);
  });

  test('Expired preferred source never outranks current addon results', () {
    final reference = DateTime.utc(2026, 11, 21, 0, 0);
    LiveVerifiedSourcePreference.clock = () => reference;
    final first = src('https://example.test/a.m3u8');
    final verified = src('https://example.test/b.m3u8');
    LiveVerifiedSourcePreference.remember(
        channelId: 'nltv:us:Channel.us', verifiedSource: verified);
    LiveVerifiedSourcePreference.clock =
        () => reference.add(const Duration(minutes: 21));
    expect(
      LiveVerifiedSourcePreference.prioritize(
          'nltv:us:Channel.us', [first, verified]),
      [same(first), same(verified)],
    );
  });

  test('A native playback failure invalidates the stored preference', () {
    final first = src('https://example.test/a.m3u8');
    final verified = src('https://example.test/b.m3u8');
    LiveVerifiedSourcePreference.remember(
        channelId: 'nltv:us:Channel.us', verifiedSource: verified);
    LiveVerifiedSourcePreference.invalidate(
        'nltv:us:Channel.us', verified);
    expect(
      LiveVerifiedSourcePreference.prioritize(
          'nltv:us:Channel.us', [first, verified]),
      [same(first), same(verified)],
    );
  });

  test('Invalid stream cannot populate preferred source', () {
    final first = src('https://example.test/a.m3u8');
    final invalid = StreamSource(addonName: 'Live TV');
    LiveVerifiedSourcePreference.remember(
        channelId: 'nltv:us:Channel.us', verifiedSource: invalid);
    expect(
      LiveVerifiedSourcePreference.prioritize(
          'nltv:us:Channel.us', [first, invalid]),
      [same(first), same(invalid)],
    );
  });
}
