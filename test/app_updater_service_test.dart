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
}
