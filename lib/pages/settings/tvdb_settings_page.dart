import 'package:flutter/material.dart';

import '../../services/metadata/tvdb_series_service.dart';

/// Optional, on-device TVDB v4 credentials for related TV series metadata.
/// No credentials are committed to git, sent to analytics, or uploaded to CI.
class TvdbSettingsPage extends StatefulWidget {
  const TvdbSettingsPage({super.key});

  @override
  State<TvdbSettingsPage> createState() => _TvdbSettingsPageState();
}

class _TvdbSettingsPageState extends State<TvdbSettingsPage> {
  final _key = TextEditingController();
  final _pin = TextEditingController();
  bool _hasKey = false;
  bool _saving = false;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final configured = await TvdbSeriesService.instance.hasCredentials;
    if (mounted) setState(() => _hasKey = configured);
  }

  Future<void> _save() async {
    if (_key.text.trim().isEmpty) {
      setState(() => _notice = 'Enter a TVDB v4 API key, or use Remove key.');
      return;
    }
    setState(() { _saving = true; _notice = null; });
    try {
      await TvdbSeriesService.instance.saveCredentials(
        _key.text, _pin.text);
      _key.clear();
      _pin.clear();
      if (mounted) {
        setState(() {
          _hasKey = true;
          _notice = 'TVDB credentials saved securely on this device.';
        });
      }
    } catch (_) {
      if (mounted) setState(() => _notice =
          'Could not save credentials securely on this device.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _remove() async {
    setState(() { _saving = true; _notice = null; });
    try {
      await TvdbSeriesService.instance.saveCredentials('', '');
      _key.clear();
      _pin.clear();
      if (mounted) setState(() {
        _hasKey = false;
        _notice = 'TVDB credentials removed.';
      });
    } catch (_) {
      if (mounted) setState(() =>
          _notice = 'Could not remove credentials.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _key.dispose();
    _pin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('TVDB Series Metadata')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text('TVDB is optional. When BestSimilar has no related shows, '
          'PlayTorrio can use TVDB to check the series identity and '
          'enrich TMDB recommendations. It never sends bulk lookups of '
          'your private library.'),
        const SizedBox(height: 20),
        Text(_hasKey ? 'TVDB key configured on this device' :
          'No TVDB key configured',
          style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        TextField(
          controller: _key,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'TVDB v4 project API key',
            hintText: 'Enter a new key',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _pin,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Subscriber PIN (only if your key requires it)',
          ),
        ),
        const SizedBox(height: 16),
        Wrap(spacing: 12, runSpacing: 8, children: [
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Save TVDB credentials'),
          ),
          TextButton(
            onPressed: _saving || !_hasKey ? null : _remove,
            child: const Text('Remove key'),
          ),
        ]),
        if (_notice != null) ...[
          const SizedBox(height: 12),
          Text(_notice!, style: Theme.of(context).textTheme.bodyMedium),
        ],
        const SizedBox(height: 24),
        const Text('Your TVDB key and optional subscriber PIN are stored '
          'in secure device storage. Credentials are never included in '
          'PlayTorrio builds or synced through GitHub. TVDB access is '
          'subject to its API licensing and subscription rules.'),
        const SizedBox(height: 12),
        const Text('Metadata provided by TheTVDB (thetvdb.com). '
          'TMDB recommendations continue to require your TMDB key '
          'configured under Discover.'),
      ],
    ),
  );
}
