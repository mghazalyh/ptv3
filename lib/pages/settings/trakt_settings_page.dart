import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/trakt/trakt_service.dart';
import '../../services/addon/connected_catalog_history_bridge.dart';
import '../../services/continue_watching/watched_history_service.dart';
import '../../services/config/env_service.dart';
import '../../services/my_list/my_list_service.dart';
import '../../services/continue_watching/continue_watching_service.dart';

class TraktSettingsPage extends StatefulWidget {
  const TraktSettingsPage({super.key});

  @override
  State<TraktSettingsPage> createState() => _TraktSettingsPageState();
}

class _TraktSettingsPageState extends State<TraktSettingsPage> {
  bool _isAuthed = false;
  bool _isLoading = true;
  bool _hasClientCredentials = false;
  String? _username;

  // Device Code Pairing
  bool _pairing = false;
  String? _userCode;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkStatus() async {
    setState(() => _isLoading = true);
    final authed = await TraktService.instance.isAuthenticated();
    String? user;
    if (authed) {
      user = await TraktService.instance.getUsername();
    }
    if (mounted) {
      setState(() {
        _isAuthed = authed;
        _hasClientCredentials = EnvService.traktClientId.isNotEmpty;
        _username = user;
        _isLoading = false;
      });
    }
  }

  Future<void> _configureTraktApplication() async {
    final clientId = TextEditingController(text: EnvService.traktClientId);
    final clientSecret = TextEditingController(text: EnvService.traktClientSecret);
    if (!mounted) {
      clientId.dispose();
      clientSecret.dispose();
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Trakt Application Credentials'),
        content: SizedBox(width: 460, child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Trakt uses a public Client ID and PKCE sign-in on Windows. '
              'No Client Secret is issued for new applications. You can override '
              'the preconfigured Client ID here.'),
            const SizedBox(height: 12),
            TextField(controller: clientId, autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                labelText: 'Trakt Client ID', border: OutlineInputBorder())),
            const SizedBox(height: 10),
            TextField(controller: clientSecret, obscureText: true,
              autocorrect: false, enableSuggestions: false,
              decoration: const InputDecoration(
                labelText: 'Legacy Client Secret (optional)',
                border: OutlineInputBorder())),
            const SizedBox(height: 8),
            const SelectableText('Create an API application at: '
              'https://developer.trakt.tv/apps',
              style: TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        )),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Save on this device')),
        ],
      ),
    );
    if (confirmed == true) {
      await EnvService.saveLocalTraktApplication(
        clientId.text, clientSecret.text);
      if (mounted) await _checkStatus();
    }
    clientId.dispose();
    clientSecret.dispose();
  }

  /// The Windows developer application uses the exact localhost redirect
  /// registered at developer.trakt.tv. Authorization remains owner-controlled.
  Future<void> _startPkce() async {
    if (_pairing) return;
    if (!_hasClientCredentials) {
      await _configureTraktApplication();
      if (!_hasClientCredentials) return;
    }
    setState(() {
      _pairing = true;
      _userCode = null;
    });
    final success = await TraktService.instance.authenticateWithPkce(
      (url) => launchUrl(url, mode: LaunchMode.externalApplication),
    );
    if (!mounted) return;
    setState(() => _pairing = false);
    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(
            'Trakt sign-in did not complete. Check the registered '
            'http://localhost:8080/callback redirect URI and try again.')),
      );
      return;
    }

    await _checkStatus();
    try {
      // Load the owner's private completed-watch events before import.
      await WatchedHistoryService.syncGitHubHistory(force: true);
      await ConnectedCatalogHistoryBridge.sync();
    } catch (error) {
      debugPrint('[Trakt] History bridge unavailable (${error.runtimeType})');
    }
    if (!mounted) return;
    unawaited(MyListService.syncAll(force: true));
    unawaited(ContinueWatchingService.syncCloudSessions());
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text(
          'Trakt connected. Check synced watch history in Trakt, then '
          'enable Trakt History in Xperience and add personalized Home rows.')),
    );
  }

  Future<void> _startPairing() async {
    if (!_hasClientCredentials) {
      await _configureTraktApplication();
      if (!_hasClientCredentials) return;
    }
    setState(() {
      _pairing = true;
      _userCode = null;
    });

    final res = await TraktService.instance.requestDeviceCode();
    if (!mounted) return;
    if (res == null) {
      setState(() => _pairing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to request Trakt pairing code.')),
      );
      return;
    }

    final userCode = res['user_code'] as String? ?? '';
    final deviceCode = res['device_code'] as String? ?? '';
    final verifyUrl = res['verification_url'] as String? ?? 'https://trakt.tv/activate';
    final interval = (res['interval'] as int? ?? 5).clamp(2, 30);

    setState(() {
      _userCode = userCode;
    });

    // Auto-launch URL
    _openBrowser(verifyUrl);

    // Start Polling
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(Duration(seconds: interval), (t) async {
      final status = await TraktService.instance.pollDeviceToken(deviceCode);
      if (status == null) {
        // Success!
        t.cancel();
        if (mounted) {
          setState(() {
            _pairing = false;
            _isAuthed = true;
          });
          _checkStatus();
          MyListService.syncAll(force: true);
          ContinueWatchingService.syncCloudSessions();
        }
      } else if (status == 'expired_token' || status == 'access_denied') {
        t.cancel();
        if (mounted) {
          setState(() => _pairing = false);
        }
      }
    });
  }

  Future<void> _openBrowser(String url) async {
    try {
      final uri = Uri.parse(url);
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      }
    } catch (_) {
      try {
        final uri = Uri.parse(url);
        await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
      } catch (e) {
        debugPrint('[Trakt] Browser launch error: $e');
      }
    }
  }

  Future<void> _logout() async {
    _pollTimer?.cancel();
    await TraktService.instance.logout();
    await _checkStatus();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080A0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1017),
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Trakt.tv Synchronization',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19),
        ),
        actions: [
          IconButton(
            tooltip: 'Configure local Trakt application credentials',
            icon: const Icon(Icons.key_outlined),
            onPressed: _configureTraktApplication,
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Text(
                  'Connect your Trakt.tv account to seamlessly synchronize your watch history, watchlist, continue watching progress, and ratings across all your devices.',
                  style: TextStyle(
                    fontSize: 13.5,
                    color: Colors.white.withValues(alpha: 0.5),
                    height: 1.4,
                  ),
                ),
              ),

              if (!_hasClientCredentials) ...[
                Card(
                  color: const Color(0xFF252030),
                  child: ListTile(
                    leading: const Icon(Icons.key_rounded),
                    title: const Text('Set up Trakt client credentials'),
                    subtitle: const Text(
                      'Only a Trakt Client ID is required for PKCE. '
                      'Your app ID is already preconfigured.'),
                    onTap: _configureTraktApplication,
                    trailing: const Icon(Icons.chevron_right),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Status Card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF12151E),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _isAuthed
                        ? const Color(0xFFED1C24).withValues(alpha: 0.35)
                        : Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: const Color(0xFFED1C24).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.movie_filter_rounded, color: Color(0xFFED1C24), size: 24),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Text(
                                    'Trakt.tv',
                                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: (_isAuthed ? const Color(0xFF10B981) : Colors.white24).withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      _isAuthed ? 'CONNECTED' : 'DISCONNECTED',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        color: _isAuthed ? const Color(0xFF10B981) : Colors.white54,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _isLoading
                                    ? 'Checking credentials...'
                                    : _isAuthed
                                        ? 'Logged in as ${_username ?? 'Trakt User'}'
                                        : 'Sign in to activate two-way cloud sync',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.white.withValues(alpha: 0.5),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_isAuthed)
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFFEF4444),
                              side: BorderSide(color: const Color(0xFFEF4444).withValues(alpha: 0.4)),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            ),
                            onPressed: _logout,
                            child: const Text('Disconnect', style: TextStyle(fontWeight: FontWeight.bold)),
                          )
                        else if (!_pairing)
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFED1C24),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            ),
                            onPressed: Platform.isWindows ? _startPkce : _startPairing,
                            icon: Icon(Platform.isWindows
                                ? Icons.open_in_browser_rounded
                                : Icons.qr_code_rounded, size: 18),
                            label: const Text('Connect Trakt', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                      ],
                    ),

                    if (_pairing && _userCode == null && Platform.isWindows) ...[
                      const SizedBox(height: 16),
                      const LinearProgressIndicator(),
                      const SizedBox(height: 8),
                      const Text(
                        'Finish the Trakt authorization in your browser. '
                        'PlayTorrio listens locally for the registered callback.',
                        style: TextStyle(fontSize: 12, color: Colors.white70),
                      ),
                    ],
                    if (_pairing && _userCode != null) ...[
                      const SizedBox(height: 20),
                      const Divider(color: Colors.white10),
                      const SizedBox(height: 16),
                      Center(
                        child: Column(
                          children: [
                            const Text(
                              'Enter this activation code at trakt.tv/activate:',
                              style: TextStyle(fontSize: 13, color: Colors.white70),
                            ),
                            const SizedBox(height: 12),
                            InkWell(
                              onTap: () {
                                Clipboard.setData(ClipboardData(text: _userCode!));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Code copied to clipboard!')),
                                );
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                                decoration: BoxDecoration(
                                  color: Colors.black45,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: const Color(0xFFED1C24).withValues(alpha: 0.5)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _userCode!,
                                      style: const TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 4,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    const Icon(Icons.copy_rounded, color: Colors.white70, size: 20),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white.withValues(alpha: 0.12),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              ),
                              onPressed: () => _openBrowser('https://trakt.tv/activate'),
                              icon: const Icon(Icons.open_in_browser_rounded, size: 16),
                              label: const Text('Open trakt.tv/activate', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                            ),
                            const SizedBox(height: 14),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFED1C24)),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  'Waiting for authorization on trakt.tv...',
                                  style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.6)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Cloud Sync Actions
              if (_isAuthed) ...[
                const Text(
                  'Cloud Sync Controls',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white70),
                ),
                const SizedBox(height: 12),
                ListTile(
                  tileColor: const Color(0xFF12151E),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
                  ),
                  leading: const Icon(Icons.sync_rounded, color: Color(0xFF7C5CFF)),
                  title: const Text('Sync Watchlist & Continue Watching Now', style: TextStyle(color: Colors.white, fontSize: 14)),
                  subtitle: const Text('Manually triggers an immediate pull from Trakt', style: TextStyle(color: Colors.white54, fontSize: 12)),
                  trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.white38),
                  onTap: () async {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Syncing with Trakt.tv...')),
                    );
                    await Future.wait([
                      MyListService.syncAll(force: true),
                      ContinueWatchingService.syncCloudSessions(),
                    ]);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Trakt sync complete!')),
                      );
                    }
                  },
                ),
                const SizedBox(height: 12),
                ListTile(
                  tileColor: const Color(0xFF12151E),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  leading: const Icon(Icons.history_rounded,
                      color: Color(0xFF7C5CFF)),
                  title: const Text('Seed Xperience from completed watch history',
                      style: TextStyle(color: Colors.white, fontSize: 14)),
                  subtitle: const Text(
                    'Imports only completed, independently dated movie and '
                    'episode events into your connected Trakt account. '
                    'Xperience must be linked separately.',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  onTap: () async {
                    try {
                      await WatchedHistoryService.syncGitHubHistory(force: true);
                      await ConnectedCatalogHistoryBridge.sync();
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text(
                          'Trakt history import attempted. Verify completed '
                          'events on Trakt, then select Trakt History in '
                          'Xperience Step 1 and personalized rows in Step 2.',
                        )),
                      );
                    } catch (error) {
                      debugPrint('[Trakt] Manual history sync error '
                          '(${error.runtimeType})');
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text(
                          'History synchronization unavailable. '
                          'Your local watch history was not changed.',
                        )),
                      );
                    }
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
