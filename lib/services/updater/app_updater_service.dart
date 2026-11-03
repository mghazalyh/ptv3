import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class AppUpdaterService {
  static const String githubRepo = 'mghazalyh/ptv3';
  static const String githubApiUrl =
      'https://api.github.com/repos/$githubRepo/releases?per_page=50';
  static const String _keyDismissedVersion = 'dismissed_update_version';

  static Future<void> dismissVersion(String version) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyDismissedVersion, version);
      debugPrint('[AppUpdaterService] Dismissed update version: $version');
    } catch (e) {
      debugPrint('[AppUpdaterService] Error dismissing update version: $e');
    }
  }

  static Future<bool> isVersionDismissed(String version) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dismissed = prefs.getString(_keyDismissedVersion);
      return dismissed == version;
    } catch (e) {
      return false;
    }
  }

  static Future<void> clearDismissedVersion() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyDismissedVersion);
    } catch (_) {}
  }

  /// Paired iOS IPA CFBundleVersion is the GitHub release run number + 3.
  /// The Windows build number equals the release run number.
  @visibleForTesting
  static bool shouldOfferRelease(
      String installedVersion, int? installedBuild,
      String releaseVersion, int? releaseBuild, {bool isIos = false}) {
    if (_isNewerVersion(installedVersion, releaseVersion)) return true;
    if (_isNewerVersion(releaseVersion, installedVersion)) return false;
    if (installedBuild == null || releaseBuild == null) return false;
    return releaseBuild + (isIos ? 3 : 0) > installedBuild;
  }

  @visibleForTesting
  static String? findIosAsset(List assets) {
    for (final asset in assets) {
      if (asset is! Map) continue;
      final name = (asset['name'] ?? '').toString().toLowerCase();
      final url = (asset['browser_download_url'] ?? '').toString();
      if (name.endsWith('.ipa') && name.contains('trollstore') &&
          url.startsWith('https://github.com/')) {
        return url;
      }
    }
    return null;
  }

  Future<UpdateInfo?> checkForUpdates({bool ignoreDismissed = false}) async {
    if (kIsWeb) return null;
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;
      final currentBuild = int.tryParse(packageInfo.buildNumber);
      final response = await http.get(
        Uri.parse(githubApiUrl),
        headers: {'Accept': 'application/vnd.github+json'},
      );
      if (response.statusCode != 200) {
        debugPrint('[AppUpdaterService] Release lookup HTTP ' +
            response.statusCode.toString());
        return null;
      }
      final payload = json.decode(response.body);
      if (payload is! List) {
        debugPrint('[AppUpdaterService] Unexpected release response');
        return null;
      }

      Map? selectedRelease;
      String? selectedVersion;
      int? selectedBuild;
      String? selectedAsset;
      final pattern = RegExp(
        r'^(?:build-)?v?(\d+\.\d+\.\d+)(?:-b(\d+))?$',
        caseSensitive: false,
      );
      for (final raw in payload) {
        if (raw is! Map || raw['draft'] == true ||
            raw['prerelease'] == true) continue;
        final match = pattern.firstMatch((raw['tag_name'] ?? '').toString());
        if (match == null) continue;
        final version = match.group(1)!;
        final runNumber = int.tryParse(match.group(2) ?? '');
        final assets = raw['assets'];
        if (assets is! List) continue;
        // Reject Windows-only releases on iPad and other incompatible builds.
        final platformUrl = _findAssetForPlatform(assets);
        if (platformUrl == null || platformUrl.isEmpty) continue;
        final isBest = selectedVersion == null ||
            _isNewerVersion(selectedVersion, version) ||
            (selectedVersion == version &&
              (runNumber ?? -1) > (selectedBuild ?? -1));
        if (isBest) {
          selectedRelease = raw;
          selectedVersion = version;
          selectedBuild = runNumber;
          selectedAsset = platformUrl;
        }
      }

      if (selectedRelease == null || selectedVersion == null ||
          selectedAsset == null) {
        debugPrint('[AppUpdaterService] No compatible published release');
        return null;
      }
      final ios = Platform.isIOS;
      if (!shouldOfferRelease(currentVersion, currentBuild,
          selectedVersion, selectedBuild, isIos: ios)) {
        debugPrint('[AppUpdaterService] Installed ' + currentVersion +
            ' build ' + packageInfo.buildNumber +
            ' is current for the available platform releases');
        return null;
      }
      final displayVersion = selectedBuild == null
          ? selectedVersion
          : selectedVersion + ' (Release Build ' + selectedBuild.toString() + ')';
      if (!ignoreDismissed && await isVersionDismissed(displayVersion)) {
        debugPrint('[AppUpdaterService] Update dismissed: ' + displayVersion);
        return null;
      }
      final publishedAt = DateTime.tryParse(
          (selectedRelease['published_at'] ?? '').toString());
      if (publishedAt == null) {
        debugPrint('[AppUpdaterService] Invalid release published_at');
        return null;
      }
      return UpdateInfo(
        currentVersion: currentVersion + ' (Build ' +
            packageInfo.buildNumber + ')',
        latestVersion: displayVersion,
        downloadUrl: selectedAsset,
        releaseNotes: (selectedRelease['body'] ??
            'No release notes available').toString(),
        publishedAt: publishedAt,
        isMacOS: Platform.isMacOS,
        isIOS: ios,
      );
    } catch (error) {
      debugPrint('[AppUpdaterService] Update check error: ' +
          error.toString());
      return null;
    }
  }

  /// Detects the current CPU architecture and finds the matching release asset.
  String? _findAssetForPlatform(List assets) {
    if (kIsWeb) return null;

    Abi? abi;
    try {
      abi = Abi.current();
      debugPrint('Detected system ABI: $abi');
    } catch (e) {
      debugPrint('Error detecting ABI: $e');
    }

    if (Platform.isIOS) {
      return findIosAsset(assets);
    } else if (Platform.isAndroid) {
      return _findAndroidAsset(assets, abi);
    } else if (Platform.isWindows) {
      return _findWindowsAsset(assets, abi);
    } else if (Platform.isLinux) {
      return _findLinuxAsset(assets, abi);
    } else if (Platform.isMacOS) {
      return _findMacOSAsset(assets, abi);
    }
    return null;
  }

  /// Android: match arm64-v8a, armeabi-v7a, x86_64, or fall back to universal
  String? _findAndroidAsset(List assets, Abi? abi) {
    final apks = assets
        .where((a) => (a['name'] as String).toLowerCase().endsWith('.apk'))
        .toList();

    if (apks.isEmpty) return null;

    // Determine architecture keywords to search for
    List<String> archKeywords = [];
    if (abi == Abi.androidArm64) {
      archKeywords = ['arm64-v8a', 'arm64_v8a', 'arm64', 'v8a', 'aarch64'];
    } else if (abi == Abi.androidArm) {
      archKeywords = ['armeabi-v7a', 'armeabi_v7a', 'armeabi', 'v7a', 'armv7', 'arm-v7a'];
    } else if (abi == Abi.androidX64) {
      archKeywords = ['x86_64', 'x86-64', 'x64'];
    } else if (abi == Abi.androidIA32) {
      archKeywords = ['x86', 'x86_32', 'ia32'];
    } else {
      // Default to arm64-v8a on modern Android if ABI couldn't be determined
      archKeywords = ['arm64-v8a', 'arm64', 'v8a'];
    }

    // 1. Try exact architecture match
    for (final keyword in archKeywords) {
      final match = apks
          .where((a) => (a['name'] as String).toLowerCase().contains(keyword))
          .firstOrNull;
      if (match != null) {
        debugPrint('Matched specific APK for $abi ($keyword): ${match['name']}');
        return match['browser_download_url'];
      }
    }

    // 2. Fall back to a "universal" APK if available
    final universal = apks
        .where((a) => (a['name'] as String).toLowerCase().contains('universal'))
        .firstOrNull;
    if (universal != null) {
      debugPrint('Falling back to universal APK: ${universal['name']}');
      return universal['browser_download_url'];
    }

    // 3. Fall back to standard release APK name
    final standardRelease = apks
        .where((a) => (a['name'] as String).toLowerCase().contains('release'))
        .firstOrNull;
    if (standardRelease != null) {
      debugPrint('Using standard release APK: ${standardRelease['name']}');
      return standardRelease['browser_download_url'];
    }

    // 4. Last resort: first available APK
    debugPrint('Using first available APK: ${apks.first['name']}');
    return apks.first['browser_download_url'];
  }

  /// Windows: match x64 or arm64 installer (.exe prioritized over .zip)
  String? _findWindowsAsset(List assets, Abi? abi) {
    final windowsAssets = assets.where((a) {
      final name = (a['name'] as String).toLowerCase();
      return (name.contains('windows') || name.contains('win') || name.contains('setup') || name.endsWith('.exe')) &&
          (name.endsWith('.exe') || name.endsWith('.msix') || name.endsWith('.zip'));
    }).toList();

    if (windowsAssets.isEmpty) return null;

    // 1. Look for installer .exe matching setup/installer
    final setupExe = windowsAssets
        .where((a) => (a['name'] as String).toLowerCase().endsWith('.exe') &&
            ((a['name'] as String).toLowerCase().contains('setup') || (a['name'] as String).toLowerCase().contains('install')))
        .firstOrNull;
    if (setupExe != null) {
      debugPrint('Selected Windows Setup installer: ${setupExe['name']}');
      return setupExe['browser_download_url'];
    }

    // 2. Look for any .exe
    final anyExe = windowsAssets
        .where((a) => (a['name'] as String).toLowerCase().endsWith('.exe'))
        .firstOrNull;
    if (anyExe != null) {
      debugPrint('Selected Windows exe: ${anyExe['name']}');
      return anyExe['browser_download_url'];
    }

    // 3. Match architecture in remaining assets (.zip/.msix)
    List<String> archKeywords;
    if (abi == Abi.windowsArm64) {
      archKeywords = ['arm64', 'aarch64'];
    } else {
      archKeywords = ['x64', 'x86_64', 'amd64', 'win64'];
    }

    for (final keyword in archKeywords) {
      final match = windowsAssets
          .where((a) => (a['name'] as String).toLowerCase().contains(keyword))
          .firstOrNull;
      if (match != null) return match['browser_download_url'];
    }

    return windowsAssets.first['browser_download_url'];
  }

  /// Linux: match x64 or arm64 AppImage/deb
  String? _findLinuxAsset(List assets, Abi? abi) {
    final linuxAssets = assets.where((a) {
      final name = (a['name'] as String).toLowerCase();
      return name.contains('linux') ||
          name.endsWith('.appimage') ||
          name.endsWith('.deb') ||
          name.endsWith('.tar.gz');
    }).toList();

    if (linuxAssets.isEmpty) return null;

    if (linuxAssets.length == 1) {
      return linuxAssets.first['browser_download_url'];
    }

    List<String> archKeywords;
    if (abi == Abi.linuxArm64) {
      archKeywords = ['arm64', 'aarch64'];
    } else {
      archKeywords = ['x86_64', 'x64', 'amd64'];
    }

    for (final keyword in archKeywords) {
      final match = linuxAssets
          .where((a) => (a['name'] as String).toLowerCase().contains(keyword))
          .firstOrNull;
      if (match != null) return match['browser_download_url'];
    }

    return linuxAssets.first['browser_download_url'];
  }

  /// macOS: match dmg or zip
  String? _findMacOSAsset(List assets, Abi? abi) {
    final macAssets = assets.where((a) {
      final name = (a['name'] as String).toLowerCase();
      return name.contains('mac') || name.contains('darwin') || name.endsWith('.dmg') || name.endsWith('.pkg');
    }).toList();

    if (macAssets.isNotEmpty) {
      return macAssets.first['browser_download_url'];
    }
    return null;
  }

  static bool _isNewerVersion(String current, String latest) {
    // Strip any suffix like "-test" or "-beta" for comparison
    final currentClean = current.split('-').first;
    final latestClean = latest.split('-').first;

    final currentParts = currentClean
        .split('.')
        .map((p) => int.tryParse(p) ?? 0)
        .toList();
    final latestParts = latestClean
        .split('.')
        .map((p) => int.tryParse(p) ?? 0)
        .toList();

    for (int i = 0; i < 3; i++) {
      final currentPart = i < currentParts.length ? currentParts[i] : 0;
      final latestPart = i < latestParts.length ? latestParts[i] : 0;

      if (latestPart > currentPart) return true;
      if (latestPart < currentPart) return false;
    }
    return false;
  }

  Future<void> openDownloadPage(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

class UpdateInfo {
  final String currentVersion;
  final String latestVersion;
  final String downloadUrl;
  final String releaseNotes;
  final DateTime publishedAt;
  final bool isMacOS;
  final bool isIOS;

  UpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.downloadUrl,
    required this.releaseNotes,
    required this.publishedAt,
    required this.isMacOS,
    this.isIOS = false,
  });
}
