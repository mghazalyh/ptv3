import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/debrid/debrid_service.dart';

/// Quick access for TorBox credentials. The built-in debrid settings page
/// also supports TorBox, but the card is located far below other providers.
class TorBoxQuickSettingsPage extends StatefulWidget {
  const TorBoxQuickSettingsPage({super.key});

  @override
  State<TorBoxQuickSettingsPage> createState() =>
      _TorBoxQuickSettingsPageState();
}

class _TorBoxQuickSettingsPageState extends State<TorBoxQuickSettingsPage> {
  final TextEditingController _keyController = TextEditingController();
  final DebridService _debrid = DebridService();
  bool _loading = true;
  bool _visible = false;
  String? _message;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  String _normalizeKey(String raw) {
    var key = raw.trim();
    if (key.toLowerCase().startsWith('bearer ')) {
      key = key.substring(7).trim();
    }
    if (key.length >= 2 &&
        ((key.startsWith('"') && key.endsWith('"')) ||
         (key.startsWith("'") && key.endsWith("'")))) {
      key = key.substring(1, key.length - 1).trim();
    }
    return key;
  }

  Future<void> _load() async {
    try {
      final key = await _debrid.torBox.getKey();
      if (!mounted) return;
      setState(() {
        _keyController.text = key ?? '';
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to load the stored TorBox key.';
        _loading = false;
      });
    }
  }

  Future<void> _paste() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (!mounted) return;
      final input = data?.text?.trim();
      if (input == null || input.isEmpty) {
        setState(() => _error = 'Clipboard is empty.');
        return;
      }
      setState(() {
        _keyController.text = _normalizeKey(input);
        _error = null;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Unable to read the clipboard.');
    }
  }

  Future<void> _save() async {
    if (_loading) return;
    final key = _normalizeKey(_keyController.text);
    if (key.isEmpty) {
      setState(() => _error = 'Paste your TorBox API key first.');
      return;
    }
    setState(() {
      _loading = true;
      _message = null;
      _error = null;
    });
    try {
      await _debrid.torBox.saveKey(key);
      await _debrid.saveSelectedService('TorBox');
      await _debrid.saveUseDebridForStreams(true);
      final profile = await _debrid.torBox.verifyKey(key);
      if (!mounted) return;
      setState(() {
        _message = profile == null
            ? 'TorBox key saved locally and TorBox selected. '
                'Verification was unavailable; test a stream.'
            : 'TorBox key verified and set as the active debrid provider.';
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'Could not save or verify the TorBox key. Check network access.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _clear() async {
    if (_loading) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove TorBox API key?'),
        content: const Text(
          'This only removes the key stored within PlayTorrio. '
          'Your configured Torrentio addon will not be removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove Key'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() => _loading = true);
    try {
      await _debrid.torBox.saveKey('');
      if (await _debrid.getSelectedService() == 'TorBox') {
        await _debrid.saveUseDebridForStreams(false);
        await _debrid.saveSelectedService('None');
      }
      if (mounted) {
        setState(() {
          _keyController.clear();
          _message = 'TorBox key removed. Torrentio addons were not changed.';
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Unable to remove the key.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('TorBox API Key')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Enter the TorBox API key from your TorBox account settings. '
              'Use this for magnet-only streams that PlayTorrio must resolve '
              'through TorBox.',
            ),
            const SizedBox(height: 12),
            const Text(
              'When your configured Torrentio addon already returns a '
              'playable TorBox HTTPS video URL, a separate key in PlayTorrio '
              'is not required.',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _keyController,
              obscureText: !_visible,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: 'TorBox API Key',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: _visible ? 'Hide key' : 'Show key',
                  icon: Icon(_visible ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _visible = !_visible),
                ),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _loading ? null : _paste,
              icon: const Icon(Icons.content_paste),
              label: const Text('Paste API Key'),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _loading ? null : _save,
              icon: const Icon(Icons.save),
              label: const Text('Save & Verify TorBox Key'),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: _loading ? null : _clear,
              icon: const Icon(Icons.delete_outline),
              label: const Text('Remove Saved Key'),
            ),
            if (_loading) const LinearProgressIndicator(),
            if (_message != null) ...[
              const SizedBox(height: 16),
              Text(_message!, style: const TextStyle(color: Colors.greenAccent)),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.orangeAccent)),
            ],
          ],
        ),
      ),
    );
  }
}
