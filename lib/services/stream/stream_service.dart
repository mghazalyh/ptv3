import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../models/addon/addon.dart';
import '../../models/stream/stream_model.dart';
import '../addon/addon_manager.dart';
import '../scraper/stream_scraper.dart';
import '../scraper/sites/knaben.dart';
import '../scraper/sites/torrent_galaxy.dart';
import '../scraper/sites/fourkhdhub.dart';
import '../scraper/sites/xdownloader.dart';
import '../scraper/sites/videasy.dart';
import '../scraper/sites/vidsrc.dart';
import '../scraper/sites/multiembed.dart';
import '../scraper/sites/vidcore.dart';
import '../scraper/sites/flystream.dart';
import '../scraper/sites/movienight.dart';
import '../scraper/sites/downloadeverything.dart';
import '../scraper/sites/movy.dart';
import '../scraper/sites/vuflix.dart';
import '../scraper/sites/rivestream.dart';
import '../scraper/sites/cinejoy.dart';
import '../scraper/sites/a111477.dart';
import '../scraper/sites/vadapav.dart';
import '../anime/anime_scraper_service.dart';
import '../anime_arabic/anime_arabic_service.dart';
import '../anime_arabic/anime_arabic_extractor.dart';
import '../p2p/p2p_settings_service.dart';
import '../player/player_debug_telemetry.dart';
import '../player/windows_playback_telemetry.dart';
import 'source_content_identity.dart';
import '../player/live_tv/live_stream_detector.dart';

/// Service that fetches playback streams from all installed Stremio addons
/// and built-in scrapers.
class StreamService {
  StreamService._();

  @visibleForTesting
  static Future<http.Response> Function(Uri)? streamGetOverride;

  @visibleForTesting
  static Future<List<StreamSource>> fetchAddonStreamsForTesting(
      InstalledAddon addon, String type, String id) =>
      _fetchFromAddon(addon, type, id);

  /// A Stremio tv channel is never an on-demand title match.
  /// Canonical channel IDs override a mislabeled navigation media type.
  static bool isLiveStreamRequest({
    required String type,
    required String id,
    int? season,
    int? episode,
  }) {
    if (season != null || episode != null) return false;
    final cleanId = id.trim().toLowerCase();
    return type.trim().toLowerCase() == 'tv' ||
        cleanId.startsWith('nltv:') || cleanId.startsWith('iptv:');
  }

  static bool isEligibleLiveStreamSource(StreamSource source) =>
      LiveStreamDetector.isHttpMedia(source.url) &&
      (source.infoHash?.trim().isEmpty ?? true);

  /// Resolve native diagnostic candidates from this specific installed addon
  /// only, never from an arbitrary command-supplied URL or local scraper.
  static Future<List<StreamSource>> fetchLiveStreamsFromAddon(
      InstalledAddon addon, String channelId) async {
    if (!addon.isStreamsActive ||
        !isLiveStreamRequest(type: 'tv', id: channelId) ||
        !addon.manifest.supportsRequest('stream', 'tv', channelId)) {
      return const <StreamSource>[];
    }
    final sources = await _fetchFromAddon(addon, 'tv', channelId);
    return sources.where(isEligibleLiveStreamSource).toList(growable: false);
  }

  static void _registerBuiltInScrapers() {
    if (P2pSettingsService.isP2pEnabled.value) {
      ScraperManager.instance.registerScraper(KnabenScraper());
      ScraperManager.instance.registerScraper(TorrentGalaxyScraper());
    } else {
      ScraperManager.instance.unregisterTorrentScrapers();
    }
    ScraperManager.instance.registerScraper(A111477Scraper());
    ScraperManager.instance.registerScraper(VadapavScraper());
    ScraperManager.instance.registerScraper(FourKHDHubScraper());
    ScraperManager.instance.registerScraper(XDownloaderScraper());
    ScraperManager.instance.registerScraper(VideasyScraper());
    ScraperManager.instance.registerScraper(VidSrcScraper());
    ScraperManager.instance.registerScraper(MultiEmbedScraper());
    ScraperManager.instance.registerScraper(VidCoreScraper());
    ScraperManager.instance.registerScraper(FlyStreamScraper());
    ScraperManager.instance.registerScraper(MovieNightScraper());
    ScraperManager.instance.registerScraper(DownloadEverythingScraper());
    ScraperManager.instance.registerScraper(MovyScraper());
    ScraperManager.instance.registerScraper(VuflixScraper());
    ScraperManager.instance.registerScraper(RiveStreamScraper());
    ScraperManager.instance.registerScraper(CinejoyScraper());
  }

  /// Fetches streams from all active stream-capable addons for the given
  /// content type and ID.
  static Stream<StreamSource> fetchStreams({
    required String type,
    required String id,
    required String title,
    int? year,
    int? season,
    int? episode,
  }) {
    final controller = StreamController<StreamSource>();

    final isLive = isLiveStreamRequest(
      type: type, id: id, season: season, episode: episode);
    final requestType = isLive ? 'tv' : type;
    final addons = AddonManager.instance.activeStreamAddons
        .where((addon) => !isLive ||
            addon.manifest.supportsRequest('stream', 'tv', id))
        .toList();

    if (!isLive) _registerBuiltInScrapers();

    int pending = addons.length + (isLive ? 0 : 1);
    var rejected = 0;
    void accept(StreamSource source) {
      if (isLive && !isEligibleLiveStreamSource(source)) {
        rejected++;
        PlayerDebugTelemetry.record('live_source_rejected', failure: true);
        return;
      }
      final identity = isLive
          ? SourceIdentityVerdict.verified
          : SourceContentIdentity.assess(source, title: title,
              year: year, season: season, episode: episode);
      WindowsPlaybackTelemetry.instance.captureSourceCandidate(
          stage: 'discovered_source', source: source,
          title: title, mediaId: id, type: type,
          year: year, season: season, episode: episode,
          verdict: isLive ? 'live_channel_resource' : identity.name);
      if (identity == SourceIdentityVerdict.rejected) {
        rejected++;
        return;
      }
      if (!controller.isClosed) controller.add(source);
    }
    void finish() {
      if (pending != 0 || controller.isClosed) return;
      if (rejected > 0) PlayerDebugTelemetry.record('source_identity_rejected', failure: true);
      controller.close();
    }

    // Local scrapers
    final isImdb = id.startsWith('tt');
    final cleanImdbId = isImdb ? id.split(':')[0] : null;

    if (!isLive) {
      ScraperManager.instance.scrapeAll(
        type: type,
        title: title,
        year: year,
        season: season,
        episode: episode,
        imdbId: cleanImdbId,
      ).listen(accept, onDone: () {
        pending--;
        finish();
      });
    }

    for (final addon in addons) {
      _fetchFromAddon(addon, requestType, id).then((sources) {
        if (!controller.isClosed) {
          for (final source in sources) {
            accept(source);
          }
        }
      }).catchError((_) {}).whenComplete(() {
        pending--;
        finish();
      });
    }

    finish(); // Completes empty Live TV requests without eligible addons.
    return controller.stream;
  }

  /// Fetches streams specifically for a targeted provider/addon that was previously used by the user.
  ///
  /// - If [targetAddonName] == 'PlayTorrioHTTP': Only scrapes built-in alive HTTP scrapers.
  /// - If [targetAddonName] == 'PlayTorrio': Only scrapes built-in torrent scrapers.
  /// - If [targetAddonName] matches a Stremio addon (e.g. 'Torrentio', 'CyberFlix'): Only calls that specific addon.
  static Stream<StreamSource> fetchStreamsForTargetAddon({
    required String targetAddonName,
    required String type,
    required String id,
    required String title,
    int? year,
    int? season,
    int? episode,
  }) {
    final controller = StreamController<StreamSource>();
    final normalizedTarget = targetAddonName.trim().toLowerCase();
    if (isLiveStreamRequest(
        type: type, id: id, season: season, episode: episode)) {
      final eligible = AddonManager.instance.activeStreamAddons.where((addon) {
        final name = addon.manifest.name.toLowerCase();
        return addon.manifest.supportsRequest('stream', 'tv', id) &&
            (name == normalizedTarget || name.contains(normalizedTarget) ||
                normalizedTarget.contains(name));
      }).toList();
      if (eligible.isEmpty) {
        return fetchStreams(type: 'tv', id: id, title: title);
      }
      _fetchFromAddon(eligible.first, 'tv', id).then((sources) {
        if (!controller.isClosed) {
          for (final source in sources) {
            if (isEligibleLiveStreamSource(source)) controller.add(source);
          }
        }
      }).catchError((Object error) {
        PlayerDebugTelemetry.record('addon_stream_request_failed',
            failure: true);
      }).whenComplete(() {
        if (!controller.isClosed) controller.close();
      });
      return controller.stream;
    }

    final isArabicAnime = id.startsWith('arabic_anime:') ||
        normalizedTarget == 'arabicanime' ||
        normalizedTarget.contains('arabic');

    if (isArabicAnime) {
      () async {
        try {
          String slug = '';
          if (id.startsWith('arabic_anime:')) {
            final parts = id.split(':');
            if (parts.length >= 2) slug = parts[1];
          } else if (id.isNotEmpty) {
            slug = id;
          }
          if (slug.isEmpty && title.isNotEmpty) {
            final searchResults = await AnimeArabicService.instance.search(title);
            if (searchResults.isNotEmpty) {
              slug = searchResults.first.slug;
            }
          }
          final epNum = episode ?? 1;
          if (slug.isNotEmpty) {
            final details = await AnimeArabicService.instance.getDetails(slug);
            final targetEp = details.episodes.firstWhere(
              (e) => e.number == epNum,
              orElse: () => ArabicEpisode(
                number: epNum,
                title: 'الحلقة $epNum',
                encodedHref: '',
                watchPath: '/e/$slug-$epNum#tok',
              ),
            );
            final hits = await AnimeArabicExtractor.instance.resolveEpisode(targetEp);
            final sources = AnimeArabicExtractor.toSources(
              hits,
              animeTitle: details.title,
              episodeNumber: epNum,
            );
            for (final s in sources) {
              if (!controller.isClosed) controller.add(s);
            }
          }
        } catch (_) {}
        if (!controller.isClosed) controller.close();
      }();
      return controller.stream;
    }

    // Check if targeting general anime providers
    final isAnime = type == 'anime' ||
        id.startsWith('anilist:') ||
        normalizedTarget == 'megaplay' ||
        normalizedTarget == 'anidb' ||
        normalizedTarget == 'watchhentai' ||
        normalizedTarget == 'hentaini' ||
        normalizedTarget == 'anime';

    if (isAnime) {
      int? anilistId;
      if (id.startsWith('anilist:')) {
        final parts = id.split(':');
        if (parts.length >= 2) {
          anilistId = int.tryParse(parts[1]);
        }
      }
      return AnimeScraperService.instance.scrapeStreamsByDetails(
        title: title,
        anilistId: anilistId,
        episodeNumber: episode ?? 1,
      );
    }

    // Check if targeting built-in PlayTorrioHTTP / PlayTorrio
    final isLocalPlayTorrio = normalizedTarget == 'playtorriohttp' ||
        normalizedTarget == 'playtorrio' ||
        normalizedTarget.contains('playtorrio');

    if (isLocalPlayTorrio) {
      _registerBuiltInScrapers();

      final isImdb = id.startsWith('tt');
      final cleanImdbId = isImdb ? id.split(':')[0] : null;

      ScraperManager.instance.scrapeAll(
        type: type,
        title: title,
        year: year,
        season: season,
        episode: episode,
        imdbId: cleanImdbId,
      ).listen(
        (source) {
          if (!controller.isClosed) {
            // If target was specifically PlayTorrioHTTP, only yield HTTP streams
            if (normalizedTarget == 'playtorriohttp' &&
                (source.infoHash != null && source.infoHash!.isNotEmpty)) {
              return;
            }
            // If target was specifically PlayTorrio (torrent), only yield torrent streams
            if (normalizedTarget == 'playtorrio' &&
                (source.infoHash == null || source.infoHash!.isEmpty)) {
              return;
            }
            if (SourceContentIdentity.isEligible(source,
                title: title, year: year, season: season, episode: episode)) {
              controller.add(source);
            }
          }
        },
        onError: (_) {},
        onDone: () {
          if (!controller.isClosed) controller.close();
        },
      );

      return controller.stream;
    }

    // Otherwise, find the matching Stremio addon
    final matchingAddons = AddonManager.instance.activeStreamAddons.where(
      (a) =>
          a.manifest.name.toLowerCase() == normalizedTarget ||
          a.manifest.name.toLowerCase().contains(normalizedTarget) ||
          normalizedTarget.contains(a.manifest.name.toLowerCase()),
    ).toList();

    if (matchingAddons.isNotEmpty) {
      final matchingAddon = matchingAddons.first;
      _fetchFromAddon(matchingAddon, type, id).then((sources) {
        if (!controller.isClosed) {
          for (final source in sources) {
            if (SourceContentIdentity.isEligible(source,
                title: title, year: year, season: season, episode: episode)) {
              controller.add(source);
            }
          }
        }
      }).catchError((_) {}).whenComplete(() {
        if (!controller.isClosed) controller.close();
      });
    } else {
      // Fallback: If no exact addon match found, run general fetch
      return fetchStreams(
        type: type,
        id: id,
        title: title,
        year: year,
        season: season,
        episode: episode,
      );
    }

    return controller.stream;
  }

  static Future<List<StreamSource>> _fetchFromAddon(
    InstalledAddon addon,
    String type,
    String id,
  ) async {
    try {
      // SDK advanced resource descriptors override top-level filters.
      // Do not contact addons with no compatible stream resource.
      if (!addon.manifest.supportsRequest('stream', type, id)) {
        PlayerDebugTelemetry.record('addon_stream_unsupported_id');
        return [];
      }

      final pathId = Uri.encodeComponent(id);
      final url = '${addon.baseUrl}/stream/$type/$pathId.json';

      final uri = Uri.parse(url);
      final response = await (streamGetOverride == null
          ? http.get(uri, headers: {
              'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
              'Accept': 'application/json',
            })
          : streamGetOverride!(uri))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        PlayerDebugTelemetry.record('addon_stream_response_failed', failure: true);
        return [];
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map || decoded['streams'] is! List) {
        PlayerDebugTelemetry.record('addon_stream_invalid', failure: true);
        return [];
      }
      final streams = decoded['streams'] as List;
      final candidates = <StreamSource>[];
      for (final entry in streams) {
        if (entry is! Map) continue;
        try {
          final source = StreamSource.fromJson(
              Map<String, dynamic>.from(entry), addon.manifest.name);
          if ((source.url?.isNotEmpty ?? false) ||
              (source.infoHash?.isNotEmpty ?? false) ||
              (source.externalUrl?.isNotEmpty ?? false)) {
            candidates.add(source);
          }
        } catch (_) {
          // A single invalid stream must not discard good sources.
        }
      }
      PlayerDebugTelemetry.record(
          candidates.isEmpty ? 'addon_stream_empty' : 'addon_stream_ready');
      return candidates;
    } on FormatException {
      PlayerDebugTelemetry.record('addon_stream_invalid', failure: true);
      return [];
    } on TypeError {
      PlayerDebugTelemetry.record('addon_stream_invalid', failure: true);
      return [];
    } catch (_) {
      PlayerDebugTelemetry.record('addon_stream_request_failed', failure: true);
      return [];
    }
  }
}
