import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/addon/addon.dart';
import '../addon/addon_manager.dart';
import '../config/env_service.dart';
import '../continue_watching/github_sync_transport.dart';
import '../metadata/tvdb_series_service.dart';
import '../metadata/tmdb_discover_service.dart';
import '../home/home_section_order_service.dart';
import '../theme/dock_settings.dart';
import '../stream/watch_source_preferences.dart';
import '../my_list/github_library_cloud.dart';

/// Portable provider keys and addon settings stored in the OWNER'S PRIVATE
/// TorriODB GitHub repository. By the owner's explicit design these JSON files
/// are human-editable and NOT encrypted. The GitHub PAT itself never leaves
/// the device and no credential values enter diagnostics or public source.
class TorriodbPortableSync {
  TorriodbPortableSync._();
  static final instance = TorriodbPortableSync._();

  static const repo = 'mghazalyh/torriodb';
  static const ref = 'main';
  static const keyPath = 'playtorrio/api-keys-v1.json';
  static const settingsPath = 'playtorrio/settings-v1.json';
  static const _pendingKey = 'torriodb_portable_sync_dirty_v1';
  static const _deletedFieldsKey = 'torriodb_portable_sync_deleted_fields_v1';
  static const _syncedDigestsKey = 'torriodb_portable_sync_digests_v1';

  static const Map<String, Map<String, String>> preferenceFields = {
    'tmdb': {'apiKey': 'local_tmdb_discover_api_key'},
    'torbox': {'apiKey': 'torbox_api_key'},
    'realDebrid': {'apiKey': 'rd_access_token'},
    'allDebrid': {'apiKey': 'alldebrid_api_key'},
    'premiumize': {'apiKey': 'premiumize_api_key'},
    'debridLink': {'apiKey': 'debridlink_api_key'},
    'trakt': {
      'clientId': 'local_config_TRAKT_CLIENT_ID',
      'clientSecret': 'local_config_TRAKT_CLIENT_SECRET',
      'accessToken': 'trakt_access_token',
      'refreshToken': 'trakt_refresh_token',
      'username': 'trakt_username',
      'expiryMs': 'trakt_token_expiry_ms',
    },
    'simkl': {
      'clientId': 'local_config_SIMKL_CLIENT_ID',
      'accessToken': 'simkl_access_token',
      'refreshToken': 'simkl_oauth2_refresh_token',
      'username': 'simkl_username',
      'expiryMs': 'simkl_oauth2_expiry_ms',
    },
  };

  final ValueNotifier<String> status =
      ValueNotifier<String>('Private TorriODB settings not connected');
  DateTime? lastSuccessfulSync;
  bool _busy = false;
  bool _applying = false;
  DateTime? _lastAttempt;
  Timer? _debounce;
  @visibleForTesting
  http.Client? clientOverride;

  /// The active GitHub Library Sync PAT is always device-local.
  bool get configured {
    final cloud = GitHubLibraryCloud.instance;
    return (Platform.isIOS || Platform.isWindows) &&
        cloud.configured &&
        cloud.repository.toLowerCase() == repo &&
        cloud.branch == ref;
  }

  static bool isVerifiedPrivateRepository(Object? value) {
    if (value is! Map) return false;
    return value['private'] == true &&
        value['full_name']?.toString().toLowerCase() == repo &&
        value['default_branch'] == ref;
  }

  static Map<String, dynamic> parseKeys(String text) {
    if (text.length > 1000000) throw const FormatException('Key vault too large');
    final raw = jsonDecode(text);
    if (raw is! Map || raw['schemaVersion'] != 1 ||
        raw['providers'] is! Map || raw['initialized'] is! bool) {
      throw const FormatException('Invalid key vault schema');
    }
    final providers = Map<String, dynamic>.from(raw['providers'] as Map);
    for (final entry in providers.entries) {
      if (entry.value is! Map) {
        throw const FormatException('Invalid provider configuration');
      }
      for (final field in (entry.value as Map).entries) {
        if (field.key is! String ||
            (field.value is! String && field.value is! int) ||
            field.value.toString().length > 8192) {
          throw const FormatException('Invalid provider field');
        }
      }
    }
    return {
      'schemaVersion': 1,
      'initialized': raw['initialized'],
      'providers': providers,
    };
  }

  /// The private settings schema remains v1 for older installed devices.
  /// Revision is optional to preserve their read compatibility.
  static int safeSettingsRevision(Object? raw) {
    if (raw == null) return 0;
    if (raw is! int || raw < 0 || raw > 2000000000) {
      throw const FormatException('Invalid settings revision');
    }
    return raw;
  }

  static int nextSettingsRevision(Object? current) {
    final revision = safeSettingsRevision(current);
    return revision >= 2000000000 ? revision : revision + 1;
  }

  static Map<String, dynamic> parseSettings(String text) {
    if (text.length > 1000000) throw const FormatException('Settings too large');
    final raw = jsonDecode(text);
    if (raw is! Map || raw['schemaVersion'] != 1 ||
        raw['initialized'] is! bool || raw['addons'] is! List) {
      throw const FormatException('Invalid portable settings schema');
    }
    final revision = safeSettingsRevision(raw['syncRevision']);
    final entries = raw['addons'] as List;
    if (entries.length > 100) {
      throw const FormatException('Too many portable addons');
    }
    for (final entry in entries) {
      if (entry is! Map<String, dynamic>) {
        throw const FormatException('Invalid portable addon');
      }
      final addon = InstalledAddon.fromJson(entry);
      if (addon.baseUrl.trim().isEmpty || addon.manifest.id.trim().isEmpty ||
          !addon.baseUrl.startsWith('https://')) {
        throw const FormatException('Unsafe portable addon URL');
      }
    }
    final hasOrder = raw.containsKey('homeSectionOrder');
    final hasHidden = raw.containsKey('homeHiddenSections');
    final order = hasOrder
        ? HomeSectionOrderService.normalize(raw['homeSectionOrder'])
        : null;
    final hidden = hasHidden
        ? HomeSectionOrderService.normalize(raw['homeHiddenSections'])
        : null;
    return {
      'schemaVersion': 1,
      'initialized': raw['initialized'],
      'syncRevision': revision,
      'addons': entries,
      if (order != null) 'homeSectionOrder': order,
      if (hidden != null) 'homeHiddenSections': hidden,
      if (raw.containsKey('dockPreferences'))
        'dockPreferences': DockSettings.normalize(raw['dockPreferences']),
      if (raw.containsKey('watchSourcePreferences'))
        'watchSourcePreferences': WatchSourcePreferencesService.normalize(
            raw['watchSourcePreferences']),
    };
  }

  static Map<String, dynamic> mergeProviderEdits(
      Map<String, dynamic> remote,
      Map<String, dynamic> local,
      Set<String> changed) {
    final merged = Map<String, dynamic>.from(remote);
    for (final name in changed) {
      if (!preferenceFields.containsKey(name) && name != 'tvdb') continue;
      merged[name] = local[name] ?? <String, dynamic>{};
    }
    return merged;
  }

  /// An initialized vault can still lack locally configured keys (notably
  /// TorBox on devices upgraded from older installations). Backfill missing
  /// or empty remote fields without overwriting populated manual cloud edits.
  /// Tombstones prevent later backfilling after a deliberate local deletion.
  static Map<String, dynamic> backfillMissingProviderFields(
      Map<String, dynamic> remote, Map<String, dynamic> local,
      {Set<String> deletedFields = const {}}) {
    final merged = Map<String, dynamic>.from(remote);
    for (final entry in local.entries) {
      if (!preferenceFields.containsKey(entry.key) && entry.key != 'tvdb') continue;
      if (entry.value is! Map) continue;
      final localFields = Map<String, dynamic>.from(entry.value as Map);
      final remoteFields = merged[entry.key] is Map
          ? Map<String, dynamic>.from(merged[entry.key] as Map)
          : <String, dynamic>{};
      for (final field in localFields.entries) {
        if (deletedFields.contains(entry.key + '.' + field.key) ||
            remoteFields.containsKey('_deleted_' + field.key)) continue;
        final existing = remoteFields[field.key];
        if (existing == null || existing == '') {
          if (field.value.toString().isNotEmpty) {
            remoteFields[field.key] = field.value;
          }
        }
      }
      if (remoteFields.isNotEmpty) merged[entry.key] = remoteFields;
    }
    return merged;
  }

  /// Mark an intentional deletion rather than interpreting missing values
  /// as a request to destroy credentials on other devices.
  Future<void> markCredentialDeleted(String provider, String field) async {
    if (!preferenceFields.containsKey(provider) ||
        !preferenceFields[provider]!.containsKey(field)) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final old = prefs.getStringList(_deletedFieldsKey) ?? <String>[];
      final identifier = provider + '.' + field;
      await prefs.setStringList(_deletedFieldsKey, {...old, identifier}.toList());
    } catch (error) {
      debugPrint('[TorriODB] Delete marker save failed (' +
          error.runtimeType.toString() + ')');
    }
    await markChanged(provider);
  }

  Future<void> clearCredentialDeletion(String provider, String field) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final old = prefs.getStringList(_deletedFieldsKey) ?? <String>[];
      final identifier = provider + '.' + field;
      await prefs.setStringList(_deletedFieldsKey,
          old.where((s) => s != identifier).toList());
    } catch (error) {
      debugPrint('[TorriODB] Clear marker unavailable (' +
          error.runtimeType.toString() + ')');
    }
  }

  /// Records only which provider was changed, never its secret in the journal.
  Future<void> markChanged(String provider) async {
    if (_applying) return;
    if (provider != 'settings' && provider != 'homeOrder' &&
        provider != 'dock' && provider != 'watchSources' &&
        provider != 'tvdb' &&
        !preferenceFields.containsKey(provider)) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final dirty = prefs.getStringList(_pendingKey)?.toSet() ?? <String>{};
      dirty.add(provider);
      await prefs.setStringList(_pendingKey, dirty.toList()..sort());
    } catch (_) {
      status.value = 'Private settings saved locally; sync will retry';
    }
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 3), () {
      unawaited(refresh(force: true));
    });
  }

  /// Safe to call after app startup, manual Sync Now, or app resume.
  Future<void> refresh({bool force = false}) async {
    if (_busy) return;
    if (!force && _lastAttempt != null &&
        DateTime.now().difference(_lastAttempt!) <
        const Duration(minutes: 10)) return;
    _lastAttempt = DateTime.now();
    _busy = true;
    http.Client? ownedClient;
    try {
      final cloud = GitHubLibraryCloud.instance;
      await cloud.initialize();
      if (!configured) {
        status.value = 'Keys stay local until private TorriODB is connected';
        return;
      }
      final token = cloud.progressAccessToken;
      if (token == null || token.isEmpty) return;
      ownedClient = clientOverride == null ? http.Client() : null;
      final client = clientOverride ?? ownedClient!;
      final headers = <String, String>{
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
        'User-Agent': 'PlayTorrio-TorriODB-Portable-Sync',
        'Authorization': 'Bearer $token',
      };
      // Never PUT a secret until the API confirms this exact PRIVATE repo.
      final meta = await client.get(
        Uri.https('api.github.com', '/repos/$repo'),
        headers: headers,
      ).timeout(const Duration(seconds: 12));
      GitHubSyncGate.inspect(meta);
      if (meta.statusCode != 200) {
        throw StateError('Unable to verify private TorriODB access');
      }
      final identity = jsonDecode(meta.body);
      if (!isVerifiedPrivateRepository(identity)) {
        throw StateError('Credential sync requires private TorriODB main');
      }

      final prefs = await SharedPreferences.getInstance();
      final dirty = prefs.getStringList(_pendingKey)?.toSet() ?? <String>{};
      final local = await _snapshotProviders(prefs);
      final remoteKeys = await _read(client, headers, keyPath);
      final keyDoc = remoteKeys == null
          ? parseKeys('{"schemaVersion":1,"initialized":false,"providers":{}}')
          : parseKeys(remoteKeys.content);
      final remoteProviders =
          Map<String, dynamic>.from(keyDoc['providers'] as Map);
      final wasInitialized = keyDoc['initialized'] == true;

      // Remote manual edits win unless the current device actually changed a
      // specific provider since its last successful upload.
      final wanted = wasInitialized
          ? dirty.where((name) => name != 'settings' &&
              name != 'homeOrder' && name != 'dock' &&
              name != 'watchSources').toSet()
          : {...local.keys};
      final localDeleted = prefs.getStringList(_deletedFieldsKey)?.toSet()
          ?? <String>{};
      final changed = mergeProviderEdits(remoteProviders, local, wanted);
      final merged = backfillMissingProviderFields(changed, local,
          deletedFields: localDeleted);
      // Explicit deletes are represented as tombstones, rather than an empty
      // field that another device could later backfill.
      for (final identifier in localDeleted) {
        final dot = identifier.indexOf('.');
        if (dot < 1) continue;
        final provider = identifier.substring(0, dot);
        final field = identifier.substring(dot + 1);
        final providerMap = merged[provider] is Map
            ? Map<String, dynamic>.from(merged[provider] as Map)
            : <String, dynamic>{};
        providerMap.remove(field);
        providerMap['_deleted_' + field] =
            DateTime.now().millisecondsSinceEpoch;
        merged[provider] = providerMap;
      }
      final remoteChanged = jsonEncode(remoteProviders) != jsonEncode(merged);
      if (wanted.isNotEmpty || remoteChanged ||
          (!wasInitialized && merged.isNotEmpty)) {
        await _write(client, headers, keyPath, remoteKeys?.sha, {
          'schemaVersion': 1,
          'initialized': true,
          'providers': merged,
        });
        dirty.removeAll(wanted);
        if (localDeleted.isNotEmpty) {
          await prefs.remove(_deletedFieldsKey);
        }
      }
      _applying = true;
      try {
        await _applyProviders(prefs, merged,
            except: dirty.where((s) => s != 'settings').toSet());
      } finally {
        _applying = false;
      }

      final remoteSettings = await _read(client, headers, settingsPath);
      final settingDoc = remoteSettings == null
          ? parseSettings('{"schemaVersion":1,"initialized":false,"addons":[]}')
          : parseSettings(remoteSettings.content);
      final localAddons = _localAddons(prefs);
      final settingWasInitialized = settingDoc['initialized'] == true;
      final changedAddons = dirty.contains('settings');
      final changedOrder = dirty.contains('homeOrder');
      final changedDock = dirty.contains('dock');
      final changedWatchSources = dirty.contains('watchSources');
      final initialAddons = !settingWasInitialized && localAddons.isNotEmpty;
      final localOrder = HomeSectionOrderService.normalize(
        prefs.getStringList(HomeSectionOrderService.storageKey) ?? <String>[]);
      final localHidden = HomeSectionOrderService.normalize(
        prefs.getStringList(HomeSectionOrderService.hiddenStorageKey) ??
            <String>[]);
      final initialLayout = !settingWasInitialized &&
          (localOrder.isNotEmpty || localHidden.isNotEmpty);

      Future<void> applyRemoteLayout() async {
        if (!settingDoc.containsKey('homeSectionOrder') &&
            !settingDoc.containsKey('homeHiddenSections')) return;
        await HomeSectionOrderService.restoreLayoutFromCloud(
          order: settingDoc['homeSectionOrder'] as List<String>?,
          hidden: settingDoc['homeHiddenSections'] as List<String>?,
        );
      }

      Future<void> applyRemotePreferences() async {
        if (!changedDock && settingDoc.containsKey('dockPreferences')) {
          await DockSettings.restoreFromCloud(settingDoc['dockPreferences']);
        }
        if (!changedWatchSources && settingDoc.containsKey('watchSourcePreferences')) {
          await WatchSourcePreferencesService.restoreFromCloud(
              settingDoc['watchSourcePreferences']);
        }
      }

      if (changedAddons || changedOrder || changedDock ||
          changedWatchSources || initialAddons || initialLayout) {
        // A layout-only change retains the remote addons and vice versa.
        // Both layout fields travel as one change to avoid partial updates.
        final useLocalLayout = changedOrder || initialLayout;
        await _write(client, headers, settingsPath, remoteSettings?.sha, {
          'schemaVersion': 1,
          'initialized': true,
          // Monotonic version allows future client upgrades to identify
          // stale exports. GitHub's conditional SHA still prevents races.
          'syncRevision': nextSettingsRevision(settingDoc['syncRevision']),
          'addons': changedAddons || initialAddons
              ? localAddons : settingDoc['addons'],
          if (changedDock) 'dockPreferences': DockSettings.snapshot()
          else if (settingDoc.containsKey('dockPreferences'))
            'dockPreferences': settingDoc['dockPreferences'],
          if (changedWatchSources)
            'watchSourcePreferences': WatchSourcePreferencesService.current.value.toJson()
          else if (settingDoc.containsKey('watchSourcePreferences'))
            'watchSourcePreferences': settingDoc['watchSourcePreferences'],
          if (useLocalLayout) ...{
            'homeSectionOrder': localOrder,
            'homeHiddenSections': localHidden,
          } else ...{
            if (settingDoc.containsKey('homeSectionOrder'))
              'homeSectionOrder': settingDoc['homeSectionOrder'],
            if (settingDoc.containsKey('homeHiddenSections'))
              'homeHiddenSections': settingDoc['homeHiddenSections'],
          },
        });
        dirty.remove('settings');
        dirty.remove('homeOrder');
        dirty.remove('dock');
        dirty.remove('watchSources');
        if (!useLocalLayout && settingWasInitialized) {
          _applying = true;
          try {
            await applyRemoteLayout();
            await applyRemotePreferences();
          } finally {
            _applying = false;
          }
        }
      } else if (settingWasInitialized) {
        _applying = true;
        try {
          await _restoreAddons(settingDoc['addons'] as List, prefs);
          await applyRemoteLayout();
          await applyRemotePreferences();
        } finally {
          _applying = false;
        }
      }
      await prefs.setStringList(_pendingKey, dirty.toList()..sort());
      lastSuccessfulSync = DateTime.now();
      status.value = 'Private TorriODB keys and preferences synchronized';
    } on GitHubSyncDeferred {
      status.value = 'GitHub rate limited; credentials preserved locally';
    } on FormatException {
      status.value = 'Invalid remote settings; local values preserved';
    } catch (error) {
      debugPrint('[TorriODB] Portable sync skipped (${error.runtimeType})');
      status.value = 'Private settings sync unavailable; local values preserved';
    } finally {
      ownedClient?.close();
      _busy = false;
    }
  }

  Future<({String content, String sha})?> _read(
      http.Client client, Map<String, String> headers, String path) async {
    GitHubSyncGate.checkAllowed();
    final response = await client.get(
      Uri.https('api.github.com', '/repos/$repo/contents/$path', {'ref': ref}),
      headers: headers,
    ).timeout(const Duration(seconds: 15));
    GitHubSyncGate.inspect(response);
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw StateError('Unable to read private settings');
    }
    final data = jsonDecode(response.body);
    if (data is! Map || data['content'] is! String ||
        data['sha'] is! String) {
      throw const FormatException('Invalid GitHub content payload');
    }
    final decoded = utf8.decode(base64Decode(
        (data['content'] as String).replaceAll(RegExp(r'\s+'), '')));
    return (content: decoded, sha: data['sha'] as String);
  }

  Future<void> _write(http.Client client, Map<String, String> headers,
      String path, String? sha, Map<String, dynamic> data) async {
    final response = await GitHubSyncGate.write(() => client.put(
      Uri.https('api.github.com', '/repos/$repo/contents/$path'),
      headers: {...headers, 'Content-Type': 'application/json'},
      body: jsonEncode({
        'message': 'settings: sync portable provider configuration',
        'branch': ref,
        if (sha != null) 'sha': sha,
        'content': base64Encode(utf8.encode(jsonEncode(data))),
      }),
    ).timeout(const Duration(seconds: 25)));
    if (response.statusCode != 200 && response.statusCode != 201) {
      // A SHA conflict is NOT retried without first reading new remote data.
      throw StateError(response.statusCode == 409
          ? 'Settings changed on another device'
          : 'Unable to save private settings');
    }
  }

  Future<Map<String, dynamic>> _snapshotProviders(
      SharedPreferences prefs) async {
    final out = <String, dynamic>{};
    for (final provider in preferenceFields.entries) {
      final values = <String, dynamic>{};
      for (final field in provider.value.entries) {
        final key = field.value;
        final value = key.endsWith('_expiry_ms')
            ? prefs.getInt(key) : prefs.getString(key);
        if (value != null && value.toString().isNotEmpty) {
          values[field.key] = value;
        }
      }
      if (values.isNotEmpty) out[provider.key] = values;
    }
    try {
      const storage = FlutterSecureStorage();
      final key = await storage.read(key: 'tvdb_v4_api_key');
      final pin = await storage.read(key: 'tvdb_v4_subscriber_pin');
      if (key != null && key.isNotEmpty) {
        out['tvdb'] = {'apiKey': key, if (pin != null) 'subscriberPin': pin};
      }
    } catch (_) {
      // No TVDB secure-storage availability: never clear saved remote fields.
    }
    return out;
  }

  Future<void> _applyProviders(SharedPreferences prefs,
      Map<String, dynamic> providers, {Set<String> except = const {}}) async {
    final previousJson = prefs.getString(_syncedDigestsKey);
    final previousDigests = <String, String>{};
    try {
      if (previousJson != null) {
        final parsed = jsonDecode(previousJson);
        if (parsed is Map) {
          for (final item in parsed.entries) {
            if (item.key is String && item.value is String) {
              previousDigests[item.key as String] = item.value as String;
            }
          }
        }
      }
    } catch (error) {
      debugPrint('[TorriODB] Last-sync digest unavailable (' +
          error.runtimeType.toString() + ')');
    }
    final nextDigests = Map<String, String>.from(previousDigests);
    String digest(String value) =>
        crypto.sha256.convert(utf8.encode(value)).toString();
    for (final entry in preferenceFields.entries) {
      if (except.contains(entry.key) || !providers.containsKey(entry.key)) continue;
      final raw = providers[entry.key];
      if (raw is! Map) continue;
      for (final field in entry.value.entries) {
        final identity = entry.key + '.' + field.key;
        if (raw.containsKey('_deleted_' + field.key)) {
          await prefs.remove(field.value);
          nextDigests.remove(identity);
          continue;
        }
        if (!raw.containsKey(field.key)) continue;
        final value = raw[field.key];
        if (field.key == 'expiryMs') {
          if (value is int && value >= 0) {
            await prefs.setInt(field.value, value);
          } else if (value == '' || value == 0) {
            await prefs.remove(field.value);
          }
        } else if (value is String) {
          if (value.isNotEmpty) {
            final existing = prefs.getString(field.value);
            if (existing == null || existing.isEmpty || existing == value ||
                previousDigests[identity] == digest(existing)) {
              // Known remote rotations win only when the local field still
              // matches the value last synchronized on this device.
              await prefs.setString(field.value, value);
              nextDigests[identity] = digest(value);
            } else {
              // First-sync conflicts fail safely: protect working local keys.
              debugPrint('[TorriODB] Credential conflict preserved locally: ' +
                  identity);
              nextDigests.remove(identity);
            }
          }
        }
      }
    }
    await prefs.setString(_syncedDigestsKey, jsonEncode(nextDigests));
    final tmdb = providers['tmdb'];
    if (tmdb is Map && !except.contains('tmdb')) {
      await TmdbDiscoverService.instance.saveKey(
        prefs.getString('local_tmdb_discover_api_key') ?? '',
      );
    }
    final trakt = providers['trakt'];
    if (trakt is Map && !except.contains('trakt')) {
      await EnvService.saveLocalTraktApplication(
        prefs.getString('local_config_TRAKT_CLIENT_ID') ?? '',
        prefs.getString('local_config_TRAKT_CLIENT_SECRET') ?? '',
      );
    }
    final simkl = providers['simkl'];
    if (simkl is Map && !except.contains('simkl')) {
      await EnvService.saveLocalSimklClientId(
        prefs.getString('local_config_SIMKL_CLIENT_ID') ?? '',
      );
    }
    final tvdb = providers['tvdb'];
    if (tvdb is Map && !except.contains('tvdb')) {
      await TvdbSeriesService.instance.saveCredentials(
        tvdb['apiKey'] is String ? tvdb['apiKey'] as String : '',
        tvdb['subscriberPin'] is String ? tvdb['subscriberPin'] as String : '',
      );
    }
  }

  static List<Map<String, dynamic>> _localAddons(SharedPreferences prefs) {
    try {
      final raw = prefs.getString('installed_addons_v4');
      if (raw == null || raw.isEmpty) return [];
      final entries = jsonDecode(raw);
      if (entries is! List || entries.length > 100) return [];
      return [
        for (final entry in entries)
          if (entry is Map<String, dynamic> &&
              (entry['baseUrl'] is String &&
               (entry['baseUrl'] as String).startsWith('https://')))
            InstalledAddon.fromJson(entry).toJson(),
      ];
    } catch (_) {
      return [];
    }
  }

  Future<void> _restoreAddons(
      List<dynamic> remote, SharedPreferences prefs) async {
    final current = _localAddons(prefs);
    final byId = <String, Map<String, dynamic>>{
      for (final item in current)
        InstalledAddon.fromJson(item).manifest.id: item,
    };
    for (final entry in remote) {
      final addon = InstalledAddon.fromJson(
          Map<String, dynamic>.from(entry as Map));
      byId[addon.manifest.id] = addon.toJson();
    }
    if (byId.isEmpty) return;
    final serialized = jsonEncode(byId.values.toList());
    await prefs.setString('installed_addons_v4', serialized);
    // After first initialization the in-memory manager must be refreshed too.
    if (AddonManager.instance.isInitializedForSync) {
      for (final entry in remote) {
        final addon = InstalledAddon.fromJson(
            Map<String, dynamic>.from(entry as Map));
        await AddonManager.instance.upsertFromSettingsImport(addon);
      }
    }
  }
}
