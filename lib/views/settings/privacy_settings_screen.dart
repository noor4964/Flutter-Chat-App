import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_chat_app/providers/theme_provider.dart';
import 'package:flutter_chat_app/services/settings_service.dart';
import 'package:flutter_chat_app/widgets/glass_scaffold.dart';
import 'package:flutter_chat_app/widgets/glass_container.dart';

class PrivacySettingsScreen extends StatefulWidget {
  const PrivacySettingsScreen({super.key});

  @override
  State<PrivacySettingsScreen> createState() => _PrivacySettingsScreenState();
}

class _PrivacySettingsScreenState extends State<PrivacySettingsScreen> {
  final SettingsService _settings = SettingsService();

  bool _readReceipts = true;
  bool _showLastSeen = true;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final receipts = await _settings.isReadReceiptsEnabled();
    final lastSeen = await _settings.isShowLastSeen();
    if (mounted) {
      setState(() {
        _readReceipts = receipts;
        _showLastSeen = lastSeen;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isGlass = themeProvider.isGlassMode;

    return GlassScaffold(
      appBar: isGlass
          ? GlassAppBar(
              title: const Text('Privacy'),
            )
          : AppBar(
              title: const Text('Privacy'),
              centerTitle: true,
              elevation: 0,
            ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                // ── Visibility ──
                _buildSectionHeader('Visibility'),
                _buildCard([
                  SwitchListTile(
                    secondary: const Icon(Icons.done_all),
                    title: const Text('Read Receipts'),
                    subtitle: const Text(
                        'Let others see when you\'ve read their messages'),
                    value: _readReceipts,
                    activeColor: colorScheme.primary,
                    onChanged: (value) async {
                      setState(() => _readReceipts = value);
                      await _settings.setReadReceiptsEnabled(value);
                    },
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  SwitchListTile(
                    secondary: const Icon(Icons.access_time),
                    title: const Text('Last Seen'),
                    subtitle: const Text(
                        'Show others when you were last active'),
                    value: _showLastSeen,
                    activeColor: colorScheme.primary,
                    onChanged: (value) async {
                      setState(() => _showLastSeen = value);
                      await _settings.setShowLastSeen(value);
                    },
                  ),
                ]),
                const SizedBox(height: 12),

                // ── Blocked Users ──
                _buildSectionHeader('Blocked Users'),
                _buildCard([
                  ListTile(
                    leading: const Icon(Icons.block),
                    title: const Text('Blocked Users'),
                    subtitle: const Text('Manage your blocked contacts'),
                    trailing:
                        const Icon(Icons.chevron_right, color: Colors.grey),
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Blocked users list coming soon'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                  ),
                ]),
                const SizedBox(height: 24),

                // ── Privacy Policy ──
                _buildSectionHeader('Legal'),
                _buildCard([
                  ExpansionTile(
                    leading: const Icon(Icons.description_outlined),
                    title: const Text('Privacy Policy'),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    children: [
                      Text(
                        'Your privacy matters to us. This chat application '
                        'collects and stores only the data necessary to '
                        'provide the messaging service.\n\n'
                        'Data we collect:\n'
                        '• Account information (email, display name)\n'
                        '• Messages and media you send\n'
                        '• Online status and activity timestamps\n'
                        '• Device tokens for push notifications\n\n'
                        'Your data is stored securely using Firebase services '
                        'with encryption in transit and at rest. We do not '
                        'sell or share your personal data with third parties.\n\n'
                        'You can delete your account and all associated data '
                        'at any time from Account & Security settings.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[700],
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  ExpansionTile(
                    leading: const Icon(Icons.gavel_outlined),
                    title: const Text('Terms of Service'),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    children: [
                      Text(
                        'By using this application, you agree to:\n\n'
                        '• Use the service for lawful purposes only\n'
                        '• Not harass, abuse, or harm other users\n'
                        '• Not distribute spam or malicious content\n'
                        '• Keep your account credentials secure\n'
                        '• Respect the intellectual property of others\n\n'
                        'We reserve the right to suspend or terminate '
                        'accounts that violate these terms.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[700],
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ]),
                const SizedBox(height: 32),
              ],
            ),
    );
  }

  // ── Helpers ──

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _buildCard(List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: Theme.of(context).dividerColor.withOpacity(0.15),
          ),
        ),
        child: Column(children: children),
      ),
    );
  }
}
