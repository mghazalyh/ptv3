import 'dart:collection';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../my_list/github_library_cloud.dart';

/// Read-only analysis of the owner's private Windows and iOS diagnostics.
/// No tokens, signed streaming URLs or raw reports are persisted.
class TelemetryInsightsData {
  int discovered = 0, loaded = 0, failed = 0, sampleCount = 0;
  int bufferingSamples = 0, droppedFrames = 0, decoderDrops = 0;
  int lateFrames = 0, sourceEvents = 0, identityRejections = 0;
  int cacheSamples = 0, fpsSamples = 0, syncSamples = 0;
  double totalCache = 0, totalFps = 0, totalSyncMs = 0;
  bool incomplete = false;
  String? warning;
  DateTime? newest;
  final Map<String, int> platforms = {}, reasons = {}, events = {};
  final Map<String, int> sources = {}, resolutions = {}, codecs = {};
  final Map<String, int> titles = {}, builds = {};
  final SplayTreeMap<String, int> dailyReports = SplayTreeMap();
  final SplayTreeMap<String, int> dailyFailures = SplayTreeMap();
  final List<double> cacheTrend = [], fpsTrend = [], dropTrend = [], syncTrend = [];
  final Map<String, Map<String, String>> devices = {};

  double get bufferingPercent => sampleCount == 0 ? 0 : 100 * bufferingSamples / sampleCount;
  double get averageCache => cacheSamples == 0 ? 0 : totalCache / cacheSamples;
  double get averageFps => fpsSamples == 0 ? 0 : totalFps / fpsSamples;
  double get averageSyncMs => syncSamples == 0 ? 0 : totalSyncMs / syncSamples;
  int get failureReports => reasons.entries.where((e) => e.key.contains('failure'))
      .fold<int>(0, (n, e) => n + e.value);
  double get failurePercent => loaded == 0 ? 0 : 100 * failureReports / loaded;

  static Map<String, dynamic> map(Object? v) =>
      v is Map ? v.map((k, value) => MapEntry(k.toString(), value)) : {};
  static List<dynamic> list(Object? v) => v is List ? v : const [];
  static double? number(Object? v) {
    final n = v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '');
    return n != null && n.isFinite ? n : null;
  }
  static String? text(Object? v) {
    final s = v?.toString().trim() ?? '';
    return s.isEmpty ? null : s;
  }
  static void add(Map<String, int> values, String? key) {
    if (key != null) values.update(key, (v) => v + 1, ifAbsent: () => 1);
  }

  void ingest(Map<String, dynamic> report) {
    final at = DateTime.tryParse(report['timestampUtc']?.toString() ?? '');
    if (at == null || report['platform'] == null) { failed++; return; }
    loaded++;
    if (newest == null || newest!.isBefore(at)) newest = at;
    final day = at.toUtc().toIso8601String().substring(0, 10);
    dailyReports.update(day, (v) => v + 1, ifAbsent: () => 1);
    final platform = text(report['platform']) ?? 'unknown';
    final reason = text(report['reason']) ?? 'unspecified';
    add(platforms, platform); add(reasons, reason); add(builds, text(report['buildRun']));
    if (reason.contains('failure')) {
      dailyFailures.update(day, (v) => v + 1, ifAbsent: () => 1);
    }
    for (final code in list(report['codes'])) { add(events, text(code)); }
    // iOS uses a separate historical schema for the same event stream.
    for (final code in list(report['nativeErrorCodes'])) {
      add(events, text(code));
    }
    add(titles, text(map(report['mediaContext'])['title']));
    add(codecs, text(map(report['capabilities'])['audioCodec']));
    for (final row in list(report['performanceSamples'])) {
      final s = map(row); if (s.isEmpty) continue;
      sampleCount++;
      if (s['buffering'] == true) bufferingSamples++;
      final cache = number(s['cacheSeconds']);
      if (cache != null && cache >= 0 && cache < 3600) {
        totalCache += cache; cacheSamples++; cacheTrend.add(cache);
      }
      final fps = number(s['videoFps']);
      if (fps != null && fps > 0 && fps < 240) {
        totalFps += fps; fpsSamples++; fpsTrend.add(fps);
      }
      final sync = number(s['avsyncSeconds']);
      if (sync != null && sync.abs() <= 10) {
        totalSyncMs += sync.abs() * 1000; syncSamples++;
        syncTrend.add(sync.abs() * 1000);
      }
      final drop = (number(s['voDroppedDelta']) ?? 0).round();
      final decoder = (number(s['decoderDroppedDelta']) ?? 0).round();
      final late = (number(s['lateFramesDelta']) ?? 0).round();
      droppedFrames += drop; decoderDrops += decoder; lateFrames += late;
      dropTrend.add((drop + decoder + late).toDouble());
      final w = number(s['videoWidth'])?.round();
      if (w != null && w > 0) {
        add(resolutions, w >= 7600 ? '8K' : w >= 3800 ? '4K' :
            w >= 2500 ? '1440p' : w >= 1800 ? '1080p' :
            w >= 1200 ? '720p' : 'SD');
      }
    }
    for (final row in list(report['sourceTrace'])) {
      final s = map(row); if (s.isEmpty) continue;
      sourceEvents++; add(sources, text(s['addon']));
      add(resolutions, text(s['resolution']));
      if (text(s['identityVerdict']) == 'rejected' ||
          text(s['action']) == 'source_identity_rejected') {
        identityRejections++;
      }
    }
    final inventory = map(report['deviceInventory']);
    if (inventory.isEmpty) {
      final deviceClass = text(report['deviceClass']);
      if (deviceClass != null) {
        devices[platform] = {
          'Device class': deviceClass,
          if (report['buildRun'] != null)
            'Application build': report['buildRun'].toString(),
        };
      }
      return;
    }
    final hardware = map(inventory['windowsHardware']);
    final summary = <String, String>{};
    final processor = list(hardware['processor']);
    final graphics = list(hardware['graphicsAdapters']);
    final system = list(hardware['computerSystem']);
    if (processor.isNotEmpty) summary['CPU'] = text(map(processor.first)['Name']) ?? 'Unknown';
    if (graphics.isNotEmpty) summary['GPU'] = text(map(graphics.first)['Name']) ?? 'Unknown';
    if (system.isNotEmpty) {
      final memory = number(map(system.first)['TotalPhysicalMemory']);
      if (memory != null) summary['RAM'] = (memory / 1073741824).toStringAsFixed(1) + ' GiB';
    }
    final os = text(inventory['operatingSystemVersion']);
    if (os != null) summary['OS'] = os;
    final app = map(inventory['application']);
    if (app['buildNumber'] != null) summary['Application build'] = app['buildNumber'].toString();
    if (summary.isNotEmpty) devices[platform] = summary;
  }

  List<MapEntry<String, int>> top(Map<String, int> source, {int limit = 8}) {
    final rows = source.entries.toList()
      ..sort((a, b) => b.value != a.value ? b.value.compareTo(a.value) :
          a.key.compareTo(b.key));
    return rows.take(limit).toList();
  }

  List<String> get insights => [
    if (loaded == 0) 'No readable telemetry reports for the selected filter.',
    if (failureReports > 0)
      '$failureReports of $loaded uploads have a failure reason (' +
          failurePercent.toStringAsFixed(1) +
          '%). Uploads are event-driven, so this is NOT an application failure rate.',
    if ((events['addon_meta_unresolved'] ?? 0) > 0)
      'Unresolved metadata lookups appear in ' +
          (events['addon_meta_unresolved'] ?? 0).toString() + ' event slots.',
    if (sampleCount > 0)
      'Playback buffering appeared in $bufferingSamples of $sampleCount samples (' +
          bufferingPercent.toStringAsFixed(1) + '%).',
    if (droppedFrames + decoderDrops + lateFrames > 0)
      'Fresh frame drops and late frames recorded: ' +
          (droppedFrames + decoderDrops + lateFrames).toString() + '.',
    if (identityRejections > 0)
      '$identityRejections source traces were rejected for content identity.',
    if (cacheSamples > 0)
      'Mean observed demuxer buffer: ' + averageCache.toStringAsFixed(1) + ' seconds.',
    if (incomplete)
      'Dataset incomplete: read $loaded of $discovered discovered report files.',
  ];
}

class TelemetryInsightsRepository {
  TelemetryInsightsRepository({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;
  static const repo = 'mghazalyh/torriodb';
  static const roots = <String>[
    'playtorrio/diagnostics/windows/player',
    'playtorrio/diagnostics/ios/night-mode',
  ];

  Future<Object?> _get(String path, String token, {Map<String, String>? query}) async {
    final response = await _client.get(Uri.https('api.github.com',
      '/repos/' + repo + '/' + path, query), headers: {
        'Authorization': 'Bearer ' + token,
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
        'User-Agent': 'PlayTorrio-Telemetry-Insights',
      }).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw StateError('GitHub diagnostics returned HTTP ' +
          response.statusCode.toString());
    }
    return jsonDecode(response.body);
  }

  Future<List<Map<String, dynamic>>> _dir(String path, String token) async {
    final result = await _get('contents/' + path, token, query: {'ref': 'main'});
    if (result is! List) throw const FormatException('Invalid telemetry directory');
    return result.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<Map<String, dynamic>?> _read(Map<String, dynamic> file, String token) async {
    final path = file['path']?.toString() ?? '';
    if (!path.startsWith('playtorrio/diagnostics/') || !path.endsWith('.json')) {
      return null;
    }
    var response = map(await _get('contents/' + path, token, query: {'ref': 'main'}));
    final responseContent = response['content']?.toString() ?? '';
    if (response['encoding'] == 'none' || responseContent.isEmpty) {
      final sha = file['sha']?.toString();
      if (sha == null || sha.isEmpty) return null;
      response = map(await _get('git/blobs/' + sha, token));
    }
    if (response['encoding'] != 'base64') return null;
    final data = base64.decode(response['content'].toString().replaceAll('\n', ''));
    final decoded = jsonDecode(utf8.decode(data));
    return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
  }

  static Map<String, dynamic> map(Object? value) => TelemetryInsightsData.map(value);

  /// days=null loads the full discoverable archive. Progress includes exact
  /// coverage; errors never masquerade as successful measurements.
  Future<TelemetryInsightsData> load({
    int? days = 7,
    String platform = 'all',
    void Function(TelemetryInsightsData)? onProgress,
    bool Function()? isCancelled,
  }) async {
    await GitHubLibraryCloud.instance.initialize();
    final token = GitHubLibraryCloud.instance.progressAccessToken;
    if (token == null || token.isEmpty) {
      throw StateError('Enable private GitHub Library in Settings to read telemetry.');
    }
    final data = TelemetryInsightsData();
    final cutoff = days == null ? null :
        DateTime.now().toUtc().subtract(Duration(days: days));
    final files = <Map<String, dynamic>>[];
    try {
      for (final root in roots.where((v) =>
          platform == 'all' || v.contains('/' + platform + '/'))) {
        if (isCancelled?.call() == true) break;
        try {
          final rootEntries = await _dir(root, token);
          if (cutoff == null) {
            // Preserve older flat-file upload layouts as well as /YYYY/MM/DD.
            files.addAll(rootEntries.where((e) => e['type'] == 'file' &&
                e['name'].toString().endsWith('.json')));
          }
          for (final year in rootEntries.where((e) => e['type'] == 'dir')) {
            final y = int.tryParse(year['name']?.toString() ?? '');
            if (y == null || cutoff != null && y < cutoff.year) continue;
            for (final month in (await _dir(year['path'].toString(), token))
                .where((e) => e['type'] == 'dir')) {
              final m = int.tryParse(month['name']?.toString() ?? '');
              if (m == null || m < 1 || m > 12) continue;
              if (cutoff != null && DateTime.utc(y, m + 1).isBefore(cutoff)) continue;
              for (final day in (await _dir(month['path'].toString(), token))
                  .where((e) => e['type'] == 'dir')) {
                final d = int.tryParse(day['name']?.toString() ?? '');
                if (d == null || d < 1 || d > 31) continue;
                final date = DateTime.utc(y, m, d);
                if (date.month != m || date.day != d ||
                    date.isAfter(DateTime.now().toUtc())) continue;
                if (cutoff != null &&
                    date.add(const Duration(days: 1)).isBefore(cutoff)) continue;
                final entries = await _dir(day['path'].toString(), token);
                files.addAll(entries.where((e) => e['type'] == 'file' &&
                    e['name'].toString().endsWith('.json')));
              }
            }
          }
        } catch (error) {
          data.incomplete = true;
          data.warning = 'Some diagnostic folders could not be listed (' +
              error.runtimeType.toString() + ').';
          debugPrint('[TelemetryInsights] Directory error: ' + error.runtimeType.toString());
        }
      }
      files.sort((a, b) => a['path'].toString().compareTo(b['path'].toString()));
      data.discovered = files.length;
      onProgress?.call(data);
      for (var i = 0; i < files.length; i += 4) {
        if (isCancelled?.call() == true) {
          data.incomplete = true;
          data.warning = 'Loading cancelled; charts show a partial dataset.';
          break;
        }
        await Future.wait(files.skip(i).take(4).map((file) async {
          try {
            final record = await _read(file, token);
            if (record == null) { data.failed++; } else { data.ingest(record); }
          } catch (error) {
            data.failed++;
            data.warning ??= 'Some reports failed to download (' +
                error.runtimeType.toString() + ').';
          }
        }));
        onProgress?.call(data);
        if (data.failed >= 24 && data.failed > data.loaded ~/ 2) {
          data.incomplete = true;
          data.warning = 'Stopped after repeated API errors or rate limiting.';
          break;
        }
      }
      if (data.failed > 0 || data.loaded + data.failed < data.discovered) {
        data.incomplete = true;
      }
      return data;
    } finally {
      _client.close();
    }
  }
}
