import 'dart:convert';

import '../../models/addon/addon.dart';
import '../addon/addon_manager.dart';
import '../debrid/debrid_service.dart';
import '../p2p/p2p_settings_service.dart';

class SettingsImportSummary {
  final int installed;
  final int updated;
  final int skippedBuiltIns;
  final List<String> warnings;

  const SettingsImportSummary({
    required this.installed,
    required this.updated,
    required this.skippedBuiltIns,
    required this.warnings,
  });
}

/// Non-destructive import of PlayTorrio/Stremio addon settings.
///
/// Accepts backups containing an 'addons' or 'installedAddons' list, even
/// inside a 'settings', 'config', or 'data' wrapper. Preserves current addons.
/// Never sends or logs API keys to GitHub or other telemetry.
class SettingsTransferService {
  SettingsTransferService._();
  static final SettingsTransferService instance = SettingsTransferService._();

  static const int maxJsonLength = 4 * 1024 * 1024;

  Map<String, dynamic> _asMap(Map raw) {
    return raw.map((key, value) => MapEntry(key.toString(), value));
  }

  Map<String, dynamic>? _findConfig(dynamic node, {int depth = 0}) {
    if (depth > 6) return null;
    if (node is List) {
      if (node.every((e) => e is Map)) {
        return <String, dynamic>{'addons': node};
      }
      return null;
    }
    if (node is! Map) return null;
    final map = _asMap(node);
    for (final key in ['addons', 'installedAddons', 'installed_addons_v4']) {
      dynamic value = map[key];
      if (value is String) {
        try {
          value = jsonDecode(value);
        } catch (_) {}
      }
      if (value is List) return {...map, 'addons': value};
    }
    for (final key in ['settings', 'config', 'data', 'backup', 'preferences']) {
      final nested = _findConfig(map[key], depth: depth + 1);
      if (nested != null) {
        return {...map, ...nested};
      }
    }
    return null;
  }

  String _normalizeUrl(String text) {
    var url = text.trim();
    if (url.startsWith('stremio://')) {
      url = 'https://${url.substring(10)}';
    } else if (url.startsWith('stremio:')) {
      url = 'https://${url.substring(8)}';
    }
    if (url.endsWith('/manifest.json')) {
      url = url.substring(0, url.length - '/manifest.json'.length);
    }
    if (url.endsWith('/')) url = url.substring(0, url.length - 1);
    return url;
  }

  /// Data is validated before any changes to local settings are attempted.
  Future<SettingsImportSummary> importJson(String jsonText) async {
    if (jsonText.trim().isEmpty || jsonText.length > maxJsonLength) {
      throw const FormatException('Choose a JSON settings file under 4 MB.');
    }
    final dynamic decoded;
    try {
      decoded = jsonDecode(jsonText);
    } on FormatException {
      throw const FormatException('Invalid JSON. Export your settings as JSON and retry.');
    }

    final config = _findConfig(decoded);
    if (config == null || config['addons'] is! List) {
      throw const FormatException(
        'No addon settings found. Expected an "addons" list in the JSON.',
      );
    }
    final rows = config['addons'] as List;
    if (rows.length > 150) {
      throw const FormatException('Backup contains too many addons (maximum 150).');
    }

    final parsed = <Map<String, dynamic>>[];
    for (final raw in rows) {
      if (raw is! Map) {
        throw const FormatException('Addon entry must be a JSON object.');
      }
      final item = _asMap(raw);
      final url = item['baseUrl']?.toString() ?? item['url']?.toString() ?? '';
      if (url.trim().isEmpty) {
        throw const FormatException('An addon entry has no baseUrl.');
      }
      parsed.add(item);
    }

    await AddonManager.instance.initialize();
    var installed = 0;
    var updated = 0;
    var skippedBuiltIns = 0;
    final warnings = <String>[];

    for (final item in parsed) {
      final url = _normalizeUrl(
        item['baseUrl']?.toString() ?? item['url']?.toString() ?? '',
      );

      if (url.startsWith('builtin:')) {
        skippedBuiltIns++;
        if (url.toLowerCase().contains('playtorrio') &&
            !url.toLowerCase().contains('http') &&
            item['enabled'] is bool) {
          await P2pSettingsService.setP2pEnabled(item['enabled'] as bool);
        }
        continue;
      }

      final uri = Uri.tryParse(url);
      if (uri == null ||
          (uri.scheme != 'https' && uri.scheme != 'http') ||
          uri.host.isEmpty) {
        warnings.add('Skipped malformed addon URL.');
        continue;
      }

      try {
        final manager = AddonManager.instance;
        InstalledAddon? existing;
        for (final addon in manager.addons) {
          if (_normalizeUrl(addon.baseUrl) == url) {
            existing = addon;
            break;
          }
        }

        if (existing == null) {
          // A full backup carries a manifest; importing it doesn't require
          // a network call. A URL-only backup fetches the current manifest.
          if (item['manifest'] is Map) {
            final manifest = _asMap(item['manifest'] as Map);
            final imported = InstalledAddon.fromJson({
              ...item,
              'baseUrl': url,
              'manifest': manifest,
            });
            await manager.upsertFromSettingsImport(imported);
            existing = imported;
          } else {
            existing = await manager.addAddon(url);
          }
          installed++;
        } else {
          updated++;
        }

        await manager.updateAddonFeature(
          addonId: existing.manifest.id,
          enableCatalogs: item['enableCatalogs'] is bool
              ? item['enableCatalogs'] as bool
              : null,
          enableSearch: item['enableSearch'] is bool
              ? item['enableSearch'] as bool
              : null,
          enableStreams: item['enableStreams'] is bool
              ? item['enableStreams'] as bool
              : null,
          enableSubtitles: item['enableSubtitles'] is bool
              ? item['enableSubtitles'] as bool
              : null,
        );
        if (item['enabled'] is bool) {
          await manager.toggleAddon(
            existing.manifest.id,
            item['enabled'] as bool,
          );
        }
      } catch (_) {
        // Do not echo the URL or the underlying exception: the URL itself
        // can contain an embedded Torrentio configuration token.
        warnings.add('One addon could not be imported; check its configured manifest URL.');
      }
    }

    final bool? p2pEnabled = config['p2pEnabled'] is bool
        ? config['p2pEnabled'] as bool
        : null;
    if (p2pEnabled != null) {
      await P2pSettingsService.setP2pEnabled(p2pEnabled);
    }

    final provider = config['debridProvider'];
    if (provider is String && provider == 'TorBox') {
      await DebridService().saveSelectedService('TorBox');
    }
    final useDebrid = config['useDebridForStreams'];
    if (useDebrid is bool) {
      await DebridService().saveUseDebridForStreams(useDebrid);
    }

    // Only imports the API key if it was explicitly included in the file.
    // Exports omit API keys by default.
    final apiKey = config['torboxApiKey'];
    if (apiKey is String && apiKey.trim().isNotEmpty) {
      await DebridService().torBox.saveKey(apiKey.trim());
    }

    return SettingsImportSummary(
      installed: installed,
      updated: updated,
      skippedBuiltIns: skippedBuiltIns,
      warnings: warnings,
    );
  }

  Future<String> exportJson() async {
    await AddonManager.instance.initialize();
    final debrid = DebridService();
    final config = <String, dynamic>{
      'format': 'playtorrio-addons-settings-v1',
      'addons': AddonManager.instance.addons
          .map((addon) => addon.toJson())
          .toList(),
      'p2pEnabled': P2pSettingsService.isP2pEnabled.value,
      'debridProvider': await debrid.getSelectedService(),
      'useDebridForStreams': await debrid.getUseDebridForStreams(),
      // Do not export TorBox or any other API credentials.
    };
    return const JsonEncoder.withIndent('  ').convert(config);
  }
}
