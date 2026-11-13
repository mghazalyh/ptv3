import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../services/addon/addon_manager.dart';
import '../../services/stream/watch_source_preferences.dart';

/// Dedicated, device-safe filter/sort editor. All controls start from defaults
/// when no configuration has been saved. Writes are local-first and queued for
/// private TorriODB without blocking the UI when offline.
class WatchSourcePreferencesPage extends StatefulWidget {
  const WatchSourcePreferencesPage({super.key});

  @override
  State<WatchSourcePreferencesPage> createState() =>
      _WatchSourcePreferencesPageState();
}

class _WatchSourcePreferencesPageState
    extends State<WatchSourcePreferencesPage> {
  bool _episode = false;
  String? _error;

  WatchSourceProfile get profile =>
      WatchSourcePreferencesService.current.value.forEpisode(_episode);

  void _save(WatchSourceProfile next) {
    setState(() => _error = null);
    unawaited(WatchSourcePreferencesService.saveProfile(
      next, isEpisode: _episode,
    ).catchError((Object error) {
      debugPrint('[WatchSources] Preference save failed: ' +
          error.runtimeType.toString());
      if (mounted) setState(() => _error = 'Could not save this preference.');
    }));
  }

  void _preset(String name) {
    final next = WatchSourceProfile.preset(name);
    unawaited(WatchSourcePreferencesService.save(
      WatchSourcePreferences(movie: next, episode: next, preset: name),
    ).then((_) {
      if (mounted) setState(() => _error = null);
    }).catchError((Object error) {
      debugPrint('[WatchSources] Preset save failed: ' +
          error.runtimeType.toString());
      if (mounted) setState(() => _error = 'Could not save the preset.');
    }));
    setState(() {});
  }

  Widget _heading(String label, String description) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(
          fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(description, style: const TextStyle(
          color: Colors.white60, fontSize: 12)),
      ],
    ),
  );

  Widget _choices(String label, List<String> values,
      List<String> selected, ValueChanged<List<String>> onChange) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(label, style: const TextStyle(
            fontWeight: FontWeight.w600)),
      ),
      Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final value in values)
            FilterChip(
              key: ValueKey('watch-source-chip-' + label + '-' + value),
              label: Text(value),
              selected: selected.contains(value),
              onSelected: (enabled) {
                final changed = List<String>.from(selected);
                if (enabled) {
                  if (!changed.contains(value)) changed.add(value);
                } else {
                  changed.remove(value);
                }
                onChange(changed);
              },
            ),
        ],
      ),
      const SizedBox(height: 12),
    ],
  );

  static const _cachePolicyLabels = <String, String>{
    'prefer': 'Prefer cached, show other sources',
    'cachedOnly': 'Verified cached only',
    'readyOnly': 'Verified or addon-reported ready',
    'all': 'All sources',
  };

  Widget _select(String label, String selected, List<String> choices,
      ValueChanged<String> onChanged) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: DropdownButtonFormField<String>(
      value: choices.contains(selected) ? selected : choices.first,
      decoration: InputDecoration(
        labelText: label, border: const OutlineInputBorder()),
      isExpanded: true,
      items: [
        for (final value in choices)
          DropdownMenuItem(
            value: value,
            child: Text(label == 'TorBox cache'
                ? (_cachePolicyLabels[value] ?? value)
                : value),
          ),
      ],
      onChanged: (value) {
        if (value != null) onChanged(value);
      },
    ),
  );

  Widget _sortRule(int index) {
    final rules = profile.sorting;
    final rule = rules[index];
    const labels = <String, String>{
      'cache': 'Cache availability',
      'resolution': 'Resolution',
      'size': 'File size',
      'provider': 'Preferred addon',
      'seeders': 'Seeder count',
      'release': 'Release quality',
      'codec': 'Video codec',
      'hdr': 'HDR',
      'audio': 'Audio language',
      'subtitles': 'Subtitles',
      'original': 'Original arrival order',
    };
    void update(SourceSortRule next) {
      final updated = List<SourceSortRule>.from(rules);
      updated[index] = next;
      if (updated.map((e) => e.criterion).toSet().length < 3) return;
      _save(profile.copyWith(sorting: updated));
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(['Primary', 'Secondary', 'Third'][index] + ' sort',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            DropdownButtonFormField<String>(
              value: rule.criterion,
              isExpanded: true,
              items: [
                for (final entry in labels.entries)
                  DropdownMenuItem(
                    value: entry.key, child: Text(entry.value)),
              ],
              onChanged: (value) {
                if (value != null) {
                  update(SourceSortRule(value, rule.descending));
                }
              },
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text(rule.descending ? 'Descending ↓' : 'Ascending ↑'),
              value: rule.descending,
              onChanged: (value) =>
                  update(SourceSortRule(rule.criterion, value)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final installed = AddonManager.instance.activeStreamAddons
        .map((a) => a.manifest.name).toSet().toList()..sort();
    return ValueListenableBuilder<WatchSourcePreferences>(
      valueListenable: WatchSourcePreferencesService.current,
      builder: (context, preferences, _) {
        final p = preferences.forEpisode(_episode);
        return Scaffold(
          appBar: AppBar(
            title: const Text('Watch Sources Preferences'),
            actions: [
              IconButton(
                tooltip: 'Restore balanced defaults',
                icon: const Icon(Icons.restart_alt_rounded),
                onPressed: () => _preset('Balanced'),
              ),
            ],
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text(
                    'Torrentio, Comet, MediaFusion and other stream addons. '
                    'Unknown metadata is included by default; saved settings '
                    'never change playback URLs or device credentials.',
                    style: TextStyle(color: Colors.white70)),
                  const SizedBox(height: 16),
                  _select('Preset', preferences.preset,
                    const ['Balanced', 'Best Quality', 'Fast Playback',
                      'Small Files', 'Custom'], _preset),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment<bool>(value: false, label: Text('Movies')),
                      ButtonSegment<bool>(value: true, label: Text('Episodes')),
                    ],
                    selected: {_episode},
                    onSelectionChanged: (selected) =>
                        setState(() => _episode = selected.first),
                  ),
                  if (_error != null)
                    Padding(padding: const EdgeInsets.only(top: 10),
                      child: Text(_error!, style:
                          const TextStyle(color: Colors.orangeAccent))),
                  _heading('Allowed sources', 'Select allowed quality and addon values. '
                      'Deselect all values in a group to allow any.'),
                  _choices('Resolution', WatchSourceProfile.allResolutions,
                      p.resolutions, (v) => _save(p.copyWith(resolutions: v))),
                  if (installed.isNotEmpty)
                    _choices('Addons', installed, p.addons,
                        (v) => _save(p.copyWith(addons: v))),
                  _choices('Video codec', WatchSourceProfile.allCodecs,
                      p.codecs, (v) => _save(p.copyWith(codecs: v))),
                  _choices('HDR formats', WatchSourceProfile.allHdr,
                      p.hdrFormats, (v) => _save(p.copyWith(hdrFormats: v))),
                  _choices('Release quality', WatchSourceProfile.allReleases,
                      p.releaseTypes,
                      (v) => _save(p.copyWith(releaseTypes: v))),
                  _choices('Audio formats', WatchSourceProfile.allAudioFormats,
                      p.audioFormats, (v) => _save(p.copyWith(audioFormats: v))),
                  _choices('Audio channels', WatchSourceProfile.allAudioChannels,
                      p.audioChannels, (v) => _save(p.copyWith(audioChannels: v))),
                  SwitchListTile.adaptive(
                    title: const Text('Exclude CAM, telesync and screener'),
                    value: p.excludeLowQuality,
                    onChanged: (v) => _save(p.copyWith(excludeLowQuality: v)),
                  ),
                  _heading('Addon priority',
                      'Choose the order used by Preferred Addon sorting.'),
                  for (var i = 0; i < 3; i++)
                    _select('Addon rank ' + (i + 1).toString(),
                      p.addonPriority.length > i ? p.addonPriority[i] : 'Torrentio',
                      const ['Torrentio', 'Comet', 'MediaFusion'],
                      (value) {
                        final next = List<String>.from(p.addonPriority);
                        while (next.length < 3) { next.add('Torrentio'); }
                        final old = next.indexOf(value);
                        if (old >= 0 && old != i) {
                          next[old] = next[i];
                        }
                        next[i] = value;
                        _save(p.copyWith(addonPriority: next));
                      }),
                  _heading('Cache and subtitles',
                      'Verified cache requires your local TorBox key. '
                      'Verified cached only hides uncached, unverified and '
                      'pending sources without an automatic fallback.'),
                  _select('TorBox cache', p.cachePolicy,
                      WatchSourceProfile.cachePolicies, (v) =>
                          _save(p.copyWith(cachePolicy: v))),
                  _select('Subtitle source', p.subtitleSource,
                      WatchSourceProfile.subtitleSources,
                      (v) => _save(p.copyWith(subtitleSource: v))),
                  _select('Subtitle requirement', p.subtitlePolicy,
                      WatchSourceProfile.subtitlePolicies, (v) =>
                          _save(p.copyWith(subtitlePolicy: v))),
                  _select('Subtitle preference language', p.subtitleLanguage,
                      const ['English', 'Japanese', 'Spanish', 'French',
                        'German', 'Arabic', 'Chinese', 'Any'],
                      (v) => _save(p.copyWith(subtitleLanguage: v))),
                  _heading('Size and seeders', '0 GB means no size limit. '
                      'Unknown values remain visible by default.'),
                  ListTile(
                    title: Text('Minimum size: ' +
                        p.minSizeGb.toStringAsFixed(0) + ' GB'),
                    subtitle: Slider(
                      min: 0, max: 60, divisions: 60,
                      value: p.minSizeGb.clamp(0.0, 60.0).toDouble(),
                      onChanged: (v) => _save(p.copyWith(minSizeGb: v)),
                    ),
                  ),
                  ListTile(
                    title: Text('Maximum size: ' +
                        (p.maxSizeGb == 0 ? 'Unlimited' :
                          p.maxSizeGb.toStringAsFixed(0) + ' GB')),
                    subtitle: Slider(
                      min: 0, max: 100, divisions: 100,
                      value: p.maxSizeGb.clamp(0.0, 100.0).toDouble(),
                      onChanged: (v) => _save(p.copyWith(maxSizeGb: v)),
                    ),
                  ),
                  ListTile(
                    title: Text('Minimum seeders: ' +
                        p.minSeeders.toString()),
                    subtitle: Slider(
                      min: 0, max: 100, divisions: 100,
                      value: p.minSeeders.clamp(0, 100).toDouble(),
                      onChanged: (v) => _save(
                          p.copyWith(minSeeders: v.round())),
                    ),
                  ),
                  SwitchListTile.adaptive(
                    title: const Text('Prefer English audio'),
                    subtitle: const Text('Best-effort release metadata; actual '
                        'audio tracks are checked by the player.'),
                    value: p.preferEnglishAudio,
                    onChanged: (v) =>
                        _save(p.copyWith(preferEnglishAudio: v)),
                  ),
                  SwitchListTile.adaptive(
                    title: const Text('Include unknown metadata'),
                    subtitle: const Text('Do not hide otherwise playable '
                        'sources missing quality or size labels.'),
                    value: p.allowUnknown,
                    onChanged: (v) =>
                        _save(p.copyWith(allowUnknown: v)),
                  ),
                  SwitchListTile.adaptive(
                    title: const Text('Collapse identical torrents'),
                    subtitle: const Text('Deduplicate matching hashes and '
                        'file indexes, preserving original addon data.'),
                    value: p.deduplicate,
                    onChanged: (v) => _save(p.copyWith(deduplicate: v)),
                  ),
                  _heading('Three-level sorting',
                      'Primary first; secondary and third break ties. '
                      'Unavailable values always sort after known values.'),
                  for (var i = 0; i < 3; i++) _sortRule(i),
                  const SizedBox(height: 24),
                  OutlinedButton.icon(
                    onPressed: () => _preset('Balanced'),
                    icon: const Icon(Icons.restore_rounded),
                    label: const Text('Restore Balanced Defaults'),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
