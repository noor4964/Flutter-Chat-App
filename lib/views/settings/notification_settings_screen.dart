import 'package:flutter/material.dart';
import 'package:flutter_chat_app/services/enhanced_notification_service.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({Key? key}) : super(key: key);

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  final EnhancedNotificationService _notificationService = EnhancedNotificationService();
  
  bool _isNotificationsEnabled = true;
  bool _isSoundEnabled = true;
  bool _isVibrationEnabled = true;
  bool _isGroupNotificationsEnabled = true;
  String _selectedTone = 'default';
  
  final List<String> _notificationTones = [
    'default',
    'classic',
    'whistle',
    'chime',
    'bell',
  ];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() {
      _isNotificationsEnabled = _notificationService.isNotificationsEnabled;
      _isSoundEnabled = _notificationService.isSoundsEnabled;
      _isVibrationEnabled = _notificationService.isVibrationEnabled;
      _isGroupNotificationsEnabled = _notificationService.isGroupNotificationsEnabled;
      _selectedTone = _notificationService.notificationTone;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notification Settings'),
        backgroundColor: theme.primaryColor,
        foregroundColor: Colors.white,
        elevation: 2,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Header section
          Container(
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  theme.primaryColor.withOpacity(0.1),
                  theme.primaryColor.withOpacity(0.05),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.primaryColor.withOpacity(0.2)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.notifications_active,
                  size: 32,
                  color: theme.primaryColor,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Notification Settings',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: theme.primaryColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Customize your notification experience',
                        style: TextStyle(
                          fontSize: 14,
                          color: colorScheme.onSurface.withOpacity(0.7),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Main notification toggle
          _buildNotificationCard(
            'Message Notifications',
            'Receive notifications for new messages',
            Icons.notifications,
            Switch.adaptive(
              value: _isNotificationsEnabled,
              activeColor: theme.primaryColor,
              onChanged: (value) async {
                await _notificationService.setNotificationsEnabled(value);
                setState(() {
                  _isNotificationsEnabled = value;
                });
                _showFeedback('Notifications ${value ? 'enabled' : 'disabled'}');
              },
            ),
          ),

          const SizedBox(height: 16),

          // Sound settings
          _buildNotificationCard(
            'Sound',
            'Play sound for notifications',
            Icons.volume_up,
            Switch.adaptive(
              value: _isSoundEnabled && _isNotificationsEnabled,
              activeColor: theme.primaryColor,
              onChanged: _isNotificationsEnabled
                  ? (value) async {
                      await _notificationService.setSoundsEnabled(value);
                      setState(() {
                        _isSoundEnabled = value;
                      });
                      _showFeedback('Sound ${value ? 'enabled' : 'disabled'}');
                    }
                  : null,
            ),
          ),

          const SizedBox(height: 16),

          // Vibration settings
          _buildNotificationCard(
            'Vibration',
            'Vibrate for notifications',
            Icons.vibration,
            Switch.adaptive(
              value: _isVibrationEnabled && _isNotificationsEnabled,
              activeColor: theme.primaryColor,
              onChanged: _isNotificationsEnabled
                  ? (value) async {
                      await _notificationService.setVibrationEnabled(value);
                      setState(() {
                        _isVibrationEnabled = value;
                      });
                      _showFeedback('Vibration ${value ? 'enabled' : 'disabled'}');
                    }
                  : null,
            ),
          ),

          const SizedBox(height: 16),

          // Group notifications
          _buildNotificationCard(
            'Group Notifications',
            'Group multiple messages from the same chat',
            Icons.group,
            Switch.adaptive(
              value: _isGroupNotificationsEnabled && _isNotificationsEnabled,
              activeColor: theme.primaryColor,
              onChanged: _isNotificationsEnabled
                  ? (value) async {
                      await _notificationService.setGroupNotifications(value);
                      setState(() {
                        _isGroupNotificationsEnabled = value;
                      });
                      _showFeedback('Group notifications ${value ? 'enabled' : 'disabled'}');
                    }
                  : null,
            ),
          ),

          const SizedBox(height: 16),

          // Notification tone selector
          Card(
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            shadowColor: theme.primaryColor.withOpacity(0.2),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.music_note, color: theme.primaryColor, size: 28),
                      const SizedBox(width: 12),
                      Text(
                        'Notification Tone',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Choose your notification sound',
                    style: TextStyle(
                      color: colorScheme.onSurface.withOpacity(0.7),
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: theme.primaryColor.withOpacity(0.3)),
                    ),
                    child: DropdownButtonFormField<String>(
                      value: _selectedTone,
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        labelText: 'Select Tone',
                        labelStyle: TextStyle(color: theme.primaryColor),
                      ),
                      items: _notificationTones.map((tone) {
                        return DropdownMenuItem(
                          value: tone,
                          child: Row(
                            children: [
                              Icon(
                                Icons.music_note,
                                size: 16,
                                color: theme.primaryColor.withOpacity(0.7),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                tone.replaceAll('_', ' ').toUpperCase(),
                                style: TextStyle(
                                  color: colorScheme.onSurface,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: _isNotificationsEnabled && _isSoundEnabled
                          ? (value) async {
                              if (value != null) {
                                await _notificationService.setNotificationTone(value);
                                setState(() {
                                  _selectedTone = value;
                                });
                                _showFeedback('Notification tone changed to $value');
                              }
                            }
                          : null,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Test notification section
          Card(
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            shadowColor: theme.primaryColor.withOpacity(0.2),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.bug_report, color: theme.primaryColor, size: 28),
                      const SizedBox(width: 12),
                      Text(
                        'Test Notifications',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Send a test notification to verify your settings',
                    style: TextStyle(
                      color: colorScheme.onSurface.withOpacity(0.7),
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isNotificationsEnabled ? _sendTestNotification : null,
                      icon: const Icon(Icons.send, size: 20),
                      label: const Text('Send Test Notification'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isNotificationsEnabled
                            ? theme.primaryColor
                            : colorScheme.onSurface.withOpacity(0.3),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // WhatsApp-like notification preview
          _buildNotificationPreview(),

          const SizedBox(height: 24),

          // Quick actions
          _buildQuickActions(),
        ],
      ),
    );
  }

  Widget _buildNotificationCard(
    String title,
    String subtitle,
    IconData icon,
    Widget trailing,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      shadowColor: theme.primaryColor.withOpacity(0.2),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            colors: [
              Colors.white,
              theme.primaryColor.withOpacity(0.02),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.all(16),
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: theme.primaryColor, size: 24),
          ),
          title: Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              subtitle,
              style: TextStyle(
                color: colorScheme.onSurface.withOpacity(0.7),
                fontSize: 13,
              ),
            ),
          ),
          trailing: trailing,
        ),
      ),
    );
  }

  Widget _buildNotificationPreview() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      shadowColor: theme.primaryColor.withOpacity(0.2),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.preview, color: theme.primaryColor, size: 28),
                const SizedBox(width: 12),
                Text(
                  'Notification Preview',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.primaryColor.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: theme.primaryColor.withOpacity(0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.chat, size: 20, color: theme.primaryColor),
                      const SizedBox(width: 8),
                      Text(
                        'Flutter Chat App',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'now',
                        style: TextStyle(
                          color: colorScheme.onSurface.withOpacity(0.6),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'John Doe',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  Text(
                    'Hey! How are you doing? 😊',
                    style: TextStyle(
                      fontSize: 14,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: theme.primaryColor,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Text(
                          'REPLY',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          border: Border.all(color: theme.primaryColor),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          'MARK AS READ',
                          style: TextStyle(
                            color: theme.primaryColor,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActions() {
    final theme = Theme.of(context);
    
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      shadowColor: theme.primaryColor.withOpacity(0.2),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.flash_on, color: theme.primaryColor, size: 28),
                const SizedBox(width: 12),
                const Text(
                  'Quick Actions',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildQuickActionButton(
                    'Enable All',
                    Icons.notifications_active,
                    () => _enableAllNotifications(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildQuickActionButton(
                    'Disable All',
                    Icons.notifications_off,
                    () => _disableAllNotifications(),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionButton(String label, IconData icon, VoidCallback onTap) {
    final theme = Theme.of(context);
    
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          border: Border.all(color: theme.primaryColor.withOpacity(0.3)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: theme.primaryColor),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: theme.primaryColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendTestNotification() async {
    try {
      final result = await _notificationService.sendTestNotification();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(
                  result['success'] ? Icons.check_circle : Icons.error,
                  color: Colors.white,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(result['message'])),
              ],
            ),
            backgroundColor: result['success'] ? Colors.green : Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        _showFeedback('Error: $e', isError: true);
      }
    }
  }

  Future<void> _enableAllNotifications() async {
    await _notificationService.setNotificationsEnabled(true);
    await _notificationService.setSoundsEnabled(true);
    await _notificationService.setVibrationEnabled(true);
    await _notificationService.setGroupNotifications(true);
    
    setState(() {
      _isNotificationsEnabled = true;
      _isSoundEnabled = true;
      _isVibrationEnabled = true;
      _isGroupNotificationsEnabled = true;
    });
    
    _showFeedback('All notifications enabled');
  }

  Future<void> _disableAllNotifications() async {
    await _notificationService.setNotificationsEnabled(false);
    
    setState(() {
      _isNotificationsEnabled = false;
    });
    
    _showFeedback('All notifications disabled');
  }

  void _showFeedback(String message, {bool isError = false}) {
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error : Icons.check_circle,
              color: Colors.white,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: isError ? Colors.red : Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}