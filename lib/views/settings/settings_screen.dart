import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_chat_app/services/platform_helper.dart';
import 'package:provider/provider.dart';
import 'package:flutter_chat_app/providers/theme_provider.dart';
import 'package:flutter_chat_app/services/notification_service.dart';
import 'package:flutter_chat_app/services/settings_service.dart';
import 'package:flutter_chat_app/views/settings/notifications_settings.dart';

class SettingsScreen extends StatefulWidget {
  @override
  _SettingsScreenState createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with SingleTickerProviderStateMixin {
  bool _notificationsEnabled = false;
  String _selectedTheme = 'Light';
  bool _isLoading = true;
  final NotificationService _notificationService = NotificationService();
  final SettingsService _settingsService = SettingsService();

  // New settings options
  bool _soundEnabled = true;
  String _selectedFontSize = 'Medium';
  bool _chatBackupEnabled = false;
  String _selectedLanguage = 'English';

  // For animations
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    // Setup animations
    _animationController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));

    _fadeAnimation =
        Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeIn,
    ));

    _loadSettings();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    try {
      // Load all settings from the SettingsService
      bool notificationsEnabled =
          await _settingsService.areNotificationsEnabled();
      bool soundEnabled = await _settingsService.isSoundEnabled();
      String fontSize = await _settingsService.getFontSize();
      bool chatBackupEnabled = await _settingsService.isChatBackupEnabled();
      String language = await _settingsService.getLanguage();

      // Load theme settings from provider if available
      bool isDarkMode = false;
      try {
        if (mounted) {
          final themeProvider =
              Provider.of<ThemeProvider>(context, listen: false);
          isDarkMode = themeProvider.isDarkMode;

          // Also get the font size from the provider
          fontSize = themeProvider.fontSize;
        }
      } catch (e) {
        print('ThemeProvider not available: $e');
        // Fallback to settings service
        isDarkMode = await _settingsService.isDarkMode();
      }

      if (mounted) {
        setState(() {
          _notificationsEnabled = notificationsEnabled;
          _selectedTheme = isDarkMode ? 'Dark' : 'Light';
          _soundEnabled = soundEnabled;
          _selectedFontSize = fontSize;
          _chatBackupEnabled = chatBackupEnabled;
          _selectedLanguage = language;
          _isLoading = false;
        });

        // Start the animation once data is loaded
        _animationController.forward();
      }
    } catch (e) {
      print('Error loading settings: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        _animationController.forward();
      }
    }
  }

  Future<void> _updateSettings() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Update all settings through the SettingsService
      await _settingsService.setNotificationsEnabled(_notificationsEnabled);
      await _settingsService.setSoundEnabled(_soundEnabled);
      await _settingsService.setFontSize(_selectedFontSize);
      await _settingsService.setChatBackupEnabled(_chatBackupEnabled);
      await _settingsService.setLanguage(_selectedLanguage);

      // Update notification service settings
      await _notificationService.setNotificationsEnabled(_notificationsEnabled);
      await _notificationService.setSoundsEnabled(_soundEnabled);

      // Update theme
      final isDarkMode = _selectedTheme == 'Dark';
      await _settingsService.setDarkMode(isDarkMode);

      try {
        // Update the theme provider
        final themeProvider = context.read<ThemeProvider>();
        themeProvider.setTheme(isDarkMode);

        // Update font size in the theme provider
        themeProvider.setFontSize(_selectedFontSize);
      } catch (e) {
        print('ThemeProvider not available: $e');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Text('Settings updated successfully'),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.error, color: Colors.white),
                SizedBox(width: 8),
                Text('Failed to update settings: $e'),
              ],
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _resetToDefaults() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Reset all settings to defaults through SettingsService
      await _settingsService.resetToDefaults();

      // Update UI state
      setState(() {
        _notificationsEnabled = false;
        _selectedTheme = 'Light';
        _soundEnabled = true;
        _selectedFontSize = 'Medium';
        _chatBackupEnabled = false;
        _selectedLanguage = 'English';
      });

      // Update theme provider
      try {
        final themeProvider = context.read<ThemeProvider>();
        themeProvider.setTheme(false); // Light theme
        themeProvider.setFontSize('Medium');
      } catch (e) {
        print('ThemeProvider not available: $e');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.refresh, color: Colors.white),
                SizedBox(width: 8),
                Text('Settings reset to defaults'),
              ],
            ),
            backgroundColor: Colors.blue,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } catch (e) {
      print('Error resetting settings: $e');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to reset settings: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Widget _buildSettingCategory(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
        Card(
          elevation: 2,
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.0),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Column(
              children: children,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final iconColor = colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        centerTitle: true,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.info_outline),
            tooltip: 'About',
            onPressed: () {
              showAboutDialog(
                  context: context,
                  applicationName: 'Flutter Chat App',
                  applicationVersion: '1.0.0',
                  applicationIcon:
                      Icon(Icons.chat, size: 48, color: colorScheme.primary),
                  children: [
                    const Text(
                        'A modern chat application built with Flutter and Firebase.'),
                  ]);
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : FadeTransition(
              opacity: _fadeAnimation,
              child: SingleChildScrollView(
                child: Padding(
                  padding: PlatformHelper.isDesktop
                      ? const EdgeInsets.all(24.0)
                      : const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      // App appearance settings
                      _buildSettingCategory('App Appearance', [
                        ListTile(
                          leading: Icon(Icons.palette, color: iconColor),
                          title: const Text('App Theme'),
                          subtitle:
                              const Text('Change the appearance of the app'),
                          trailing: DropdownButton<String>(
                            value: _selectedTheme,
                            isDense: true,
                            underline: Container(),
                            onChanged: (String? newValue) {
                              if (newValue != null) {
                                setState(() {
                                  _selectedTheme = newValue;
                                });
                              }
                            },
                            items: <String>[
                              'Light',
                              'Dark',
                              //'System', // Future enhancement
                            ].map<DropdownMenuItem<String>>((String value) {
                              return DropdownMenuItem<String>(
                                value: value,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      value == 'Light'
                                          ? Icons.light_mode
                                          : value == 'Dark'
                                              ? Icons.dark_mode
                                              : Icons.settings_suggest,
                                      size: 18,
                                    ),
                                    SizedBox(width: 8),
                                    Text(value),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                        ListTile(
                          leading: Icon(Icons.text_fields, color: iconColor),
                          title: const Text('Font Size'),
                          subtitle: const Text(
                              'Adjust the text size throughout the app'),
                          trailing: DropdownButton<String>(
                            value: _selectedFontSize,
                            isDense: true,
                            underline: Container(),
                            onChanged: (String? newValue) {
                              if (newValue != null) {
                                setState(() {
                                  _selectedFontSize = newValue;
                                });

                                // Preview font size change immediately
                                final themeProvider =
                                    Provider.of<ThemeProvider>(context,
                                        listen: false);
                                themeProvider.setFontSize(newValue);
                              }
                            },
                            items: <String>[
                              'Small',
                              'Medium',
                              'Large',
                            ].map<DropdownMenuItem<String>>((String value) {
                              return DropdownMenuItem<String>(
                                value: value,
                                child: Text(value),
                              );
                            }).toList(),
                          ),
                        ),
                      ]),

                      SizedBox(height: 16),

                      // Notification settings
                      _buildSettingCategory('Notifications', [
                        SwitchListTile(
                          secondary:
                              Icon(Icons.notifications, color: iconColor),
                          title: const Text('Enable Notifications'),
                          subtitle: const Text(
                              'Receive alerts for new messages and requests'),
                          value: _notificationsEnabled,
                          activeColor: colorScheme.primary,
                          onChanged: (bool value) {
                            setState(() {
                              _notificationsEnabled = value;

                              // If notifications are turned off, disable sounds too
                              if (!value) {
                                _soundEnabled = false;
                              }
                            });
                          },
                        ),
                        SwitchListTile(
                          secondary: Icon(Icons.volume_up, color: iconColor),
                          title: const Text('Enable Sounds'),
                          subtitle: const Text(
                              'Play sounds for notifications and messages'),
                          value: _soundEnabled,
                          activeColor: colorScheme.primary,
                          onChanged: _notificationsEnabled
                              ? (bool value) {
                                  setState(() {
                                    _soundEnabled = value;
                                  });
                                }
                              : null, // Disable if notifications are off
                        ),
                        ListTile(
                          leading: Icon(Icons.settings_applications,
                              color: iconColor),
                          title: const Text('Notification Settings'),
                          subtitle: const Text(
                              'Advanced notification options and testing'),
                          trailing: Icon(Icons.arrow_forward_ios, size: 16),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) =>
                                    const NotificationSettingsScreen(),
                              ),
                            );
                          },
                        ),
                        ListTile(
                          leading: Icon(Icons.notifications_active,
                              color: iconColor),
                          title: const Text('Test Notifications'),
                          subtitle: const Text(
                              'Test if your notifications are working properly'),
                          trailing: Icon(Icons.bug_report, size: 16),
                          onTap: () {
                            Navigator.of(context).pushNamed('/notification_test');
                          },
                        ),
                      ]),

                      SizedBox(height: 16),

                      // Security and backup settings
                      _buildSettingCategory('Data & Security', [
                        SwitchListTile(
                          secondary: Icon(Icons.backup, color: iconColor),
                          title: const Text('Chat Backup'),
                          subtitle: const Text('Backup your chat history'),
                          value: _chatBackupEnabled,
                          activeColor: colorScheme.primary,
                          onChanged: (bool value) {
                            setState(() {
                              _chatBackupEnabled = value;
                            });

                            if (value) {
                              // Show backup frequency dialog when enabling
                              showDialog(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: Text('Backup Frequency'),
                                  content: SingleChildScrollView(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                            'How often would you like to backup your chat history?'),
                                        SizedBox(height: 16),
                                        ListTile(
                                          title: Text('Daily'),
                                          leading: Radio<String>(
                                            value: 'Daily',
                                            groupValue:
                                                'Daily', // Default selection
                                            onChanged: (String? value) {
                                              Navigator.of(context).pop();
                                            },
                                          ),
                                        ),
                                        ListTile(
                                          title: Text('Weekly'),
                                          leading: Radio<String>(
                                            value: 'Weekly',
                                            groupValue: 'Daily',
                                            onChanged: (String? value) {
                                              Navigator.of(context).pop();
                                            },
                                          ),
                                        ),
                                        ListTile(
                                          title: Text('Monthly'),
                                          leading: Radio<String>(
                                            value: 'Monthly',
                                            groupValue: 'Daily',
                                            onChanged: (String? value) {
                                              Navigator.of(context).pop();
                                            },
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(),
                                      child: Text('Cancel'),
                                    ),
                                    ElevatedButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(),
                                      child: Text('Confirm'),
                                    ),
                                  ],
                                ),
                              );
                            }
                          },
                        ),
                        ListTile(
                          leading: Icon(Icons.translate, color: iconColor),
                          title: const Text('Language'),
                          subtitle: const Text('Set your preferred language'),
                          trailing: DropdownButton<String>(
                            value: _selectedLanguage,
                            isDense: true,
                            underline: Container(),
                            onChanged: (String? newValue) {
                              if (newValue != null) {
                                setState(() {
                                  _selectedLanguage = newValue;
                                });

                                // Show language change confirmation
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                        'Language will be changed to $newValue after saving settings'),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              }
                            },
                            items: <String>[
                              'English',
                              'Spanish',
                              'French',
                              'German',
                              'Chinese',
                            ].map<DropdownMenuItem<String>>((String value) {
                              return DropdownMenuItem<String>(
                                value: value,
                                child: Text(value),
                              );
                            }).toList(),
                          ),
                        ),
                        ListTile(
                          leading: Icon(Icons.privacy_tip, color: iconColor),
                          title: const Text('Privacy Policy'),
                          subtitle: const Text('View our privacy policy'),
                          trailing: Icon(Icons.arrow_forward_ios, size: 16),
                          onTap: () {
                            // Show privacy policy dialog or navigate to privacy policy screen
                            showDialog(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: Text('Privacy Policy'),
                                content: SingleChildScrollView(
                                  child: Text(
                                      'This is a placeholder for the privacy policy content. '
                                      'In a real app, this would contain the full privacy policy text.'),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(context).pop(),
                                    child: Text('Close'),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ]),

                      SizedBox(height: 24),

                      // Save settings button
                      Align(
                        alignment: Alignment.center,
                        child: ElevatedButton.icon(
                          onPressed: _isLoading ? null : _updateSettings,
                          icon: _isLoading
                              ? SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Icon(Icons.save),
                          label:
                              Text(_isLoading ? 'Saving...' : 'Save Settings'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 32, vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                          ),
                        ),
                      ),

                      SizedBox(height: 16),

                      // Reset settings option
                      if (!_isLoading)
                        Align(
                          alignment: Alignment.center,
                          child: TextButton.icon(
                            icon: Icon(Icons.refresh),
                            label: Text('Reset to Defaults'),
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: Text('Reset Settings'),
                                  content: Text(
                                      'Are you sure you want to reset all settings to default values?'),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(),
                                      child: Text('Cancel'),
                                    ),
                                    TextButton(
                                      onPressed: () {
                                        Navigator.of(context).pop();
                                        _resetToDefaults();
                                      },
                                      child: Text('Reset'),
                                      style: TextButton.styleFrom(
                                        foregroundColor: Colors.red,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),

                      SizedBox(height: 20),

                      // Version info at bottom
                      Center(
                        child: Text(
                          'Flutter Chat App v1.0.0',
                          style: TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
