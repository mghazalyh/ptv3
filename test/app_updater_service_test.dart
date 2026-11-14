import 'package:flutter_test/flutter_test.dart';
import 'package:playtorrio/services/updater/app_updater_service.dart';

void main() {
  group('Cross-platform release numbering', () {
    test('Installed iPad build 179 matches paired release 176', () {
      expect(AppUpdaterService.shouldOfferRelease(
        '1.1.15', 179, '1.1.15', 176, isIos: true), isFalse);
    });
    test('Installed iPad build 179 detects newer paired release 177', () {
      expect(AppUpdaterService.shouldOfferRelease(
        '1.1.15', 179, '1.1.15', 177, isIos: true), isTrue);
    });
    test('Windows installed build equals release run number', () {
      expect(AppUpdaterService.shouldOfferRelease(
        '1.1.15', 176, '1.1.15', 176), isFalse);
      expect(AppUpdaterService.shouldOfferRelease(
        '1.1.15', 176, '1.1.15', 177), isTrue);
    });
    test('Earlier semantic version must not prompt', () {
      expect(AppUpdaterService.shouldOfferRelease(
        '1.1.15', 179, '1.1.14', 999, isIos: true), isFalse);
    });
    test('Higher semantic version prompts', () {
      expect(AppUpdaterService.shouldOfferRelease(
        '1.1.15', 179, '1.1.16', 1, isIos: true), isTrue);
    });
    test('Unknown build cannot create same-version false positive', () {
      expect(AppUpdaterService.shouldOfferRelease(
        '1.1.15', null, '1.1.15', 177, isIos: true), isFalse);
    });
  });
  group('iOS package compatibility', () {
    test('Windows-only release has no iOS installable asset', () {
      expect(AppUpdaterService.findIosAsset([
        {'name': 'PlayTorrio-Windows-Setup.exe',
         'browser_download_url': 'https://github.com/example/win.exe'},
        {'name': 'SHA256SUMS.txt'},
      ]), isNull);
    });
    test('Finds genuine signed TrollStore IPA in paired release', () {
      const ipaUrl =
          'https://github.com/mghazalyh/ptv3/releases/download/'
          'build-v1.1.15-b176/PlayTorrio-v1.1.15-build176-iOS15-TrollStore.ipa';
      expect(AppUpdaterService.findIosAsset([
        {'name': 'PlayTorrio-Windows-Setup.exe'},
        {'name': 'PlayTorrio-v1.1.15-build176-iOS15-TrollStore.ipa',
         'browser_download_url': ipaUrl},
      ]), ipaUrl);
    });
    test('Rejects non-GitHub or invalid IPA links', () {
      expect(AppUpdaterService.findIosAsset([
        {'name': 'PlayTorrio-iOS15-TrollStore.ipa',
         'browser_download_url': 'https://example.invalid/ipa'},
      ]), isNull);
    });
  });

  group('Windows release provenance and checksums', () {
    const goodUrl = 'https://github.com/mghazalyh/ptv3/releases/download/'
        'build-v1.1.15-b192/PlayTorrio-v1.1.15-build192-Windows-Setup.exe';
    const name = 'PlayTorrio-v1.1.15-build192-Windows-Setup.exe';
    final good = {'name': name, 'browser_download_url': goodUrl};
    test('matches exact release build and installer', () {
      expect(AppUpdaterService.findWindowsSetupAsset(
          [good], '1.1.15', 192), goodUrl);
      expect(AppUpdaterService.findWindowsSetupAsset(
          [good], '1.1.15', 191), isNull);
      expect(AppUpdaterService.findWindowsSetupAsset(
          [good], '1.1.16', 192), isNull);
      expect(AppUpdaterService.findWindowsSetupAsset(
          [good], '1.1.15', null), isNull);
    });
    test('rejects URL from wrong release or host', () {
      expect(AppUpdaterService.findWindowsSetupAsset([
        {'name': name,
         'browser_download_url': goodUrl.replaceFirst(
           'build-v1.1.15-b192/', 'build-v1.1.15-b191/')}
      ], '1.1.15', 192), isNull);
      expect(AppUpdaterService.findWindowsSetupAsset([
        {'name': name,
         'browser_download_url': 'https://example.invalid/installer.exe'}
      ], '1.1.15', 192), isNull);
    });
    test('finds checksum file from matching GitHub domain', () {
      const url = 'https://github.com/mghazalyh/ptv3/releases/download/'
          'build-v1.1.15-b192/SHA256SUMS.txt';
      expect(AppUpdaterService.findChecksumAsset([
        {'name': 'SHA256SUMS.txt', 'browser_download_url': url}
      ]), url);
      expect(AppUpdaterService.findChecksumAsset([
        {'name': 'SHA256SUMS.txt',
         'browser_download_url': 'https://example.invalid/SHA256SUMS.txt'}
      ]), isNull);
    });
    test('validates exact filename and matching SHA256', () {
      const hash = '0123456789abcdef0123456789abcdef'
          '0123456789abcdef0123456789abcdef';
      const sums = '0123456789abcdef0123456789abcdef'
          '0123456789abcdef0123456789abcdef  '
          'PlayTorrio-v1.1.15-build192-Windows-Setup.exe\n';
      expect(AppUpdaterService.checksumMatches(sums, name, hash), isTrue);
      expect(AppUpdaterService.checksumMatches(
        sums, 'Older-Windows-Setup.exe', hash), isFalse);
      expect(AppUpdaterService.checksumMatches(
        sums, name, 'ffffffffffffffffffffffffffffffff'
            'ffffffffffffffffffffffffffffffff'), isFalse);
      expect(AppUpdaterService.checksumMatches(
        'bad manifest', name, hash), isFalse);
    });
  });
}
