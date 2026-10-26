import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/my_list/github_library_cloud.dart';
import '../../services/my_list/my_list_service.dart';

class GitHubLibrarySettingsPage extends StatefulWidget {
  const GitHubLibrarySettingsPage({super.key});

  @override
  State<GitHubLibrarySettingsPage> createState() =>
      _GitHubLibrarySettingsPageState();
}

class _GitHubLibrarySettingsPageState extends State<GitHubLibrarySettingsPage> {
  final _repo = TextEditingController();
  final _branch = TextEditingController();
  final _key = TextEditingController();
  bool _working = false;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await GitHubLibraryCloud.instance.initialize();
    if (!mounted) return;
    _repo.text = GitHubLibraryCloud.instance.repository;
    _branch.text = GitHubLibraryCloud.instance.branch;
    setState(() => _ready = true);
  }

  @override
  void dispose() {
    _repo.dispose();
    _branch.dispose();
    _key.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (_working) return;
    setState(() => _working = true);
    try {
      await GitHubLibraryCloud.instance.configure(
        repo: _repo.text,
        targetBranch: _branch.text,
        accessToken: _key.text,
      );
      _key.clear();
      await MyListService.syncAll(force: true);
      if (!mounted) return;
      final state = GitHubLibraryCloud.instance.state.value;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(state == GitHubLibraryState.synced
            ? 'My List connected and synced on GitHub'
            : GitHubLibraryCloud.instance.status.value),
      ));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _sync() async {
    setState(() => _working = true);
    await MyListService.syncAll(force: true);
    if (mounted) setState(() => _working = false);
  }

  Future<void> _disconnect() async {
    setState(() => _working = true);
    try {
      await GitHubLibraryCloud.instance.disconnect();
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cloud = GitHubLibraryCloud.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('GitHub Library Sync')),
      backgroundColor: const Color(0xFF111117),
      body: !_ready
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 650),
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    const Icon(Icons.cloud_sync_rounded,
                        color: Color(0xFF9C7BFF), size: 45),
                    const SizedBox(height: 12),
                    const Text(
                      'One watchlist on all your devices',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Your movies and TV library lives in one small JSON file. '
                      'Edits work offline and are uploaded when sync succeeds. '
                      'Trakt and Simkl will no longer change My List.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70, height: 1.5),
                    ),
                    const SizedBox(height: 24),
                    ValueListenableBuilder<GitHubLibraryState>(
                      valueListenable: cloud.state,
                      builder: (context, state, _) => ValueListenableBuilder<String>(
                        valueListenable: cloud.status,
                        builder: (context, message, _) => Card(
                          child: ListTile(
                            leading: Icon(
                              state == GitHubLibraryState.synced
                                  ? Icons.cloud_done_rounded
                                  : Icons.cloud_outlined,
                              color: state == GitHubLibraryState.failed
                                  ? Colors.orangeAccent
                                  : const Color(0xFF9C7BFF),
                            ),
                            title: Text(cloud.enabled.value
                                ? 'GitHub sync enabled'
                                : 'Local-only library'),
                            subtitle: Text(message),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _repo,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'GitHub repository',
                        hintText: 'owner/repository',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _branch,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Database branch',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _key,
                      obscureText: true,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: const InputDecoration(
                        labelText: 'GitHub access token',
                        helperText: 'Stored securely on this device. Leave empty to keep saved key.',
                        helperMaxLines: 2,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Create a fine-grained personal access token restricted '
                      'to this repository with Contents: Read and write. '
                      'Paste the same token on your other devices.',
                      style: TextStyle(color: Colors.white70, height: 1.5),
                    ),
                    TextButton.icon(
                      onPressed: () => launchUrl(
                        Uri.parse('https://github.com/settings/personal-access-tokens/new'),
                        mode: LaunchMode.externalApplication,
                      ),
                      icon: const Icon(Icons.open_in_new_rounded, size: 18),
                      label: const Text('Create a GitHub access key'),
                    ),
                    const SizedBox(height: 12),
                    const Card(
                      color: Color(0xFF3B2D14),
                      child: Padding(
                        padding: EdgeInsets.all(14),
                        child: Text(
                          'Privacy: the default ptv3 repository is PUBLIC. '
                          'Your watchlist titles will be publicly readable. '
                          'For private storage, use a dedicated private GitHub '
                          'repository with the same database JSON file.',
                          style: TextStyle(color: Color(0xFFFFD591)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _working ? null : _connect,
                      icon: const Icon(Icons.link_rounded),
                      label: Text(_working ? 'Working...' : 'Connect & Sync Now'),
                    ),
                    if (cloud.enabled.value) ...[
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: _working ? null : _sync,
                        icon: const Icon(Icons.sync_rounded),
                        label: const Text('Refresh all devices'),
                      ),
                      const SizedBox(height: 6),
                      TextButton(
                        onPressed: _working ? null : _disconnect,
                        child: const Text('Disconnect (keep local watchlist)'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
    );
  }
}
