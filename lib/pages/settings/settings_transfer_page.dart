import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/config/settings_transfer_service.dart';

class SettingsTransferPage extends StatefulWidget {
  const SettingsTransferPage({super.key});

  @override
  State<SettingsTransferPage> createState() => _SettingsTransferPageState();
}

class _SettingsTransferPageState extends State<SettingsTransferPage> {
  final TextEditingController _jsonController = TextEditingController();
  bool _busy = false;
  String? _status;
  String? _error;

  @override
  void dispose() {
    _jsonController.dispose();
    super.dispose();
  }

  Future<void> _pickJsonFile() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = null;
      _error = null;
    });
    try {
      final selection = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json', 'txt'],
        withData: true,
      );
      if (selection == null || selection.files.isEmpty) return;
      final picked = selection.files.single;
      if (picked.size > SettingsTransferService.maxJsonLength) {
        throw const FormatException('Settings file must be under 4 MB.');
      }
      String? jsonText;
      if (picked.bytes != null) {
        jsonText = utf8.decode(picked.bytes!);
      } else if (picked.path != null && picked.path!.isNotEmpty) {
        jsonText = await File(picked.path!).readAsString();
      }
      if (jsonText == null || jsonText.trim().isEmpty) {
        throw const FormatException('Selected settings file was empty.');
      }
      if (!mounted) return;
      setState(() {
        _jsonController.text = jsonText!;
        _status = 'Settings file loaded. Review and tap Import.';
      });
    } catch (error) {
      // Do not log raw backup content: addon URLs can contain secrets.
      if (mounted) {
        setState(() => _error = 'Could not open JSON file: $error');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pasteJson() async {
    try {
      final clip = await Clipboard.getData(Clipboard.kTextPlain);
      if (!mounted) return;
      final text = clip?.text;
      if (text == null || text.trim().isEmpty) {
        setState(() => _error = 'Clipboard does not contain settings JSON.');
        return;
      }
      setState(() {
        _jsonController.text = text;
        _error = null;
        _status = 'JSON pasted. Review and tap Import.';
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Clipboard unavailable: $error');
      }
    }
  }

  Future<void> _import() async {
    if (_busy) return;
    if (_jsonController.text.trim().isEmpty) {
      setState(() => _error = 'Select a JSON file or paste settings first.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Import settings?'),
        content: const Text(
          'This merges addon settings with existing addons. Matched addons '
          'will have their enabled and feature flags updated. Other addons '
          'and downloaded videos will be kept. A backup can contain private '
          'addon URLs. Import only files you trust.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Import'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() {
      _busy = true;
      _error = null;
      _status = null;
    });
    try {
      final result = await SettingsTransferService.instance.importJson(
        _jsonController.text,
      );
      if (!mounted) return;
      setState(() {
        _status = 'Imported ${result.installed} new addons, updated '
            '${result.updated} existing addons, and processed '
            '${result.skippedBuiltIns} built-in source settings.';
        if (result.warnings.isNotEmpty) {
          _error = result.warnings.join('\n');
        }
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Import failed: $error');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _status = null;
    });
    try {
      final text = await SettingsTransferService.instance.exportJson();
      await Clipboard.setData(ClipboardData(text: text));
      if (!mounted) return;
      setState(() => _status =
          'Settings JSON copied to clipboard. API keys are excluded. '
          'Configured addon URLs may themselves contain private tokens, '
          'so store the copied text securely.');
    } catch (error) {
      if (mounted) setState(() => _error = 'Export failed: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Import / Export Settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Import your PlayTorrio settings backup or a JSON configuration '
              'with an "addons" list. URLs from Torrentio and your existing '
              'addon feature toggles are supported.',
            ),
            const SizedBox(height: 16),
            if (_busy) const LinearProgressIndicator(),
            OutlinedButton.icon(
              onPressed: _busy ? null : _pickJsonFile,
              icon: const Icon(Icons.folder_open),
              label: const Text('Choose JSON Settings File'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _busy ? null : _pasteJson,
              icon: const Icon(Icons.content_paste),
              label: const Text('Paste Settings from Clipboard'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _jsonController,
              maxLines: 8,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Settings JSON',
                hintText: '{"addons":[{"baseUrl":"https://example.com/config"}]}',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy ? null : _import,
              icon: const Icon(Icons.file_download_outlined),
              label: const Text('Import Settings'),
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _busy ? null : _export,
              icon: const Icon(Icons.copy),
              label: const Text('Export Settings (Copy JSON)'),
            ),
            const SizedBox(height: 8),
            const Text(
              'Export never includes TorBox API keys or passwords. '
              'However, Torrentio addon URLs can contain configuration tokens. '
              'Keep your JSON backup private.',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            if (_status != null) ...[
              const SizedBox(height: 16),
              Text(_status!, style: const TextStyle(color: Colors.greenAccent)),
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
