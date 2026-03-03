import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:flutter_chat_app/providers/theme_provider.dart';
import 'package:flutter_chat_app/services/auth_service.dart';
import 'package:flutter_chat_app/services/platform_helper.dart';
import 'package:flutter_chat_app/widgets/glass_scaffold.dart';
import 'package:flutter_chat_app/widgets/glass_container.dart';
import 'package:flutter_chat_app/views/settings/appearance_settings_screen.dart';
import 'package:flutter_chat_app/views/settings/chat_settings_screen.dart';
import 'package:flutter_chat_app/views/settings/account_security_screen.dart';
import 'package:flutter_chat_app/views/settings/privacy_settings_screen.dart';
import 'package:flutter_chat_app/views/settings/notification_settings_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final AuthService _authService = AuthService();
  Map<String, dynamic>? _userProfile;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await _authService.getUserProfile();
      if (mounted) {
        setState(() {
          _userProfile = profile;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading profile: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await _authService.signOut();
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sign out failed: $e')),
        );
      }
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
              title: const Text('Settings'),
            )
          : AppBar(
              title: const Text('Settings'),
              centerTitle: true,
              elevation: 0,
            ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: PlatformHelper.isDesktop
                  ? const EdgeInsets.all(24)
                  : const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                children: [
                  // ── User Profile Header ──
                  _buildProfileHeader(colorScheme),
                  const SizedBox(height: 16),

                  // ── Settings Categories ──
                  _buildCategory(
                    context,
                    children: [
                      _buildSettingsTile(
                        icon: Icons.palette_outlined,
                        iconColor: Colors.purple,
                        title: 'Appearance',
                        subtitle: 'Theme, colors, fonts & visual effects',
                        onTap: () => _push(const AppearanceSettingsScreen()),
                      ),
                      _buildDivider(),
                      _buildSettingsTile(
                        icon: Icons.notifications_outlined,
                        iconColor: Colors.orange,
                        title: 'Notifications',
                        subtitle: 'Alerts, sounds & vibration',
                        onTap: () => _push(const EnhancedNotificationSettingsScreen()),
                      ),
                      _buildDivider(),
                      _buildSettingsTile(
                        icon: Icons.chat_bubble_outline,
                        iconColor: Colors.blue,
                        title: 'Chat',
                        subtitle: 'Bubble style, backup & media',
                        onTap: () => _push(const ChatSettingsScreen()),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildCategory(
                    context,
                    children: [
                      _buildSettingsTile(
                        icon: Icons.shield_outlined,
                        iconColor: Colors.green,
                        title: 'Account & Security',
                        subtitle: 'Password, online status & account',
                        onTap: () => _push(const AccountSecurityScreen()),
                      ),
                      _buildDivider(),
                      _buildSettingsTile(
                        icon: Icons.lock_outline,
                        iconColor: Colors.teal,
                        title: 'Privacy',
                        subtitle: 'Read receipts, last seen & policy',
                        onTap: () => _push(const PrivacySettingsScreen()),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildCategory(
                    context,
                    children: [
                      _buildSettingsTile(
                        icon: Icons.info_outline,
                        iconColor: Colors.grey,
                        title: 'About',
                        subtitle: 'Flutter Chat App v1.0.0',
                        onTap: () {
                          showAboutDialog(
                            context: context,
                            applicationName: 'Flutter Chat App',
                            applicationVersion: '1.0.0',
                            applicationIcon: Icon(Icons.chat,
                                size: 48, color: colorScheme.primary),
                            children: const [
                              Text(
                                'A modern chat application built with Flutter and Firebase.',
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // ── Sign Out ──
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _signOut,
                        icon: const Icon(Icons.logout, color: Colors.red),
                        label: const Text('Sign Out'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  // ── Helpers ──

  Widget _buildProfileHeader(ColorScheme colorScheme) {
    final username = _userProfile?['username'] as String? ?? 'User';
    final email = FirebaseAuth.instance.currentUser?.email ?? '';
    final profileImage = _userProfile?['profileImageUrl'] as String?;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          CircleAvatar(
            radius: 32,
            backgroundColor: colorScheme.primaryContainer,
            backgroundImage:
                (profileImage != null && profileImage.isNotEmpty)
                    ? NetworkImage(profileImage)
                    : null,
            child: (profileImage == null || profileImage.isEmpty)
                ? Text(
                    username.isNotEmpty ? username[0].toUpperCase() : '?',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  username,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (email.isNotEmpty)
                  Text(
                    email,
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategory(BuildContext context, {required List<Widget> children}) {
    final isGlass = Provider.of<ThemeProvider>(context, listen: false).isGlassMode;
    if (isGlass) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: GlassCard(
          child: Column(children: children),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
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

  Widget _buildSettingsTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: iconColor.withOpacity(0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: iconColor, size: 22),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 13, color: Colors.grey[600]),
      ),
      trailing: Icon(Icons.chevron_right, color: Colors.grey[400], size: 22),
      onTap: onTap,
    );
  }

  Widget _buildDivider() {
    return Divider(
      height: 1,
      indent: 72,
      endIndent: 16,
      color: Theme.of(context).dividerColor.withOpacity(0.1),
    );
  }

  void _push(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }
}
