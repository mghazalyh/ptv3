import 'package:flutter/material.dart';

import '../../services/cache/storage_cache_service.dart';

class StorageSettingsPage extends StatefulWidget {
  const StorageSettingsPage({super.key});

  @override
  State<StorageSettingsPage> createState() => _StorageSettingsPageState();
}

class _StorageSettingsPageState extends State<StorageSettingsPage> {
  StorageSnapshot? _snapshot;
  bool _busy = false;
  String? _message;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  static String _formatBytes(int bytes) {
    if (bytes >= 1073741824) {
      return (bytes / 1073741824).toStringAsFixed(2) + ' GB';
    }
    if (bytes >= 1048576) {
      return (bytes / 1048576).toStringAsFixed(1) + ' MB';
    }
    if (bytes >= 1024) {
      return (bytes / 1024).toStringAsFixed(1) + ' KB';
    }
    return bytes.toString() + ' B';
  }

  Future<void> _refresh() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final snapshot = await StorageCacheService.instance.scan();
      if (!mounted) return;
      setState(() => _snapshot = snapshot);
    } catch (error, stack) {
      debugPrint('[StorageSettings] Scan: ' + error.toString() + '\n' + stack.toString());
      if (mounted) setState(() => _error = 'Storage scan failed: ' + error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clear({
    required String title,
    required String explanation,
    required Future<StorageCleanupResult> Function() operation,
  }) async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(explanation),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() {
      _busy = true;
      _message = null;
      _error = null;
    });
    try {
      final result = await operation();
      final updated = await StorageCacheService.instance.scan();
      if (!mounted) return;
      setState(() {
        _snapshot = updated;
        _message = 'Freed ' + _formatBytes(result.freedBytes) + ' (' +
            result.deletedCount.toString() + ' entries).';
        if (result.errors.isNotEmpty) {
          _error = result.errors.length.toString() +
              ' item(s) could not be deleted. Close playback and retry.';
        }
      });
    } catch (error, stack) {
      debugPrint('[StorageSettings] Cleanup: ' + error.toString() + '\n' + stack.toString());
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _metric(String label, int bytes, {String? description}) {
    return Card(
      child: ListTile(
        title: Text(label),
        subtitle: description == null ? null : Text(description),
        trailing: Text(
          _formatBytes(bytes),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    return Scaffold(
      appBar: AppBar(title: const Text('Storage & Cache')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Free storage without reinstalling PlayTorrio. '
              'Close the video player before clearing streaming cache.',
            ),
            const SizedBox(height: 16),
            if (_busy) const LinearProgressIndicator(),
            if (snapshot != null) ...[
              _metric(
                'Temporary video & image cache',
                snapshot.temporaryBytes,
                description: 'Files stored in app cache folders',
              ),
              _metric(
                'Unused incomplete downloads',
                snapshot.incompleteBytes,
                description: snapshot.incompleteCount.toString() +
                    ' partial files; paused transfers are protected',
              ),
              _metric(
                'Saved offline videos',
                snapshot.savedBytes,
                description: 'Never removed by Clear Streaming Cache',
              ),
            ],
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _busy ? null : _refresh,
              icon: const Icon(Icons.refresh),
              label: const Text('Rescan Storage'),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy
                  ? null
                  : () => _clear(
                        title: 'Clear streaming cache?',
                        explanation: 'Remove disposable cached data and '
                            'inactive torrent streams. Saved offline videos '
                            'and app settings remain untouched. Pause '
                            'downloads and close the player first.',
                        operation: StorageCacheService.instance.clearStreamingCache,
                      ),
              icon: const Icon(Icons.cleaning_services_outlined),
              label: const Text('Clear Streaming Cache'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () => _clear(
                        title: 'Clear unused downloads?',
                        explanation: 'Remove abandoned .part and HLS metadata '
                            'files. Active and paused transfers, saved videos '
                            'and settings remain untouched.',
                        operation: StorageCacheService.instance.clearUnusedDownloads,
                      ),
              icon: const Icon(Icons.delete_sweep_outlined),
              label: const Text('Clear Unused Downloads'),
            ),
            if (_message != null) ...[
              const SizedBox(height: 12),
              Text(_message!, style: const TextStyle(color: Colors.greenAccent)),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            ],
            const SizedBox(height: 24),
            const Text(
              'Automatic cleanup prunes files older than 24 hours when app '
              'temporary storage exceeds 512 MB. This does not limit saved '
              'downloads or storage managed independently by iPadOS.',
            ),
          ],
        ),
      ),
    );
  }
}
