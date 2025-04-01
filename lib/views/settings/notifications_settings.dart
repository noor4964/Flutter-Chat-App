import 'package:flutter/material.dart';
import 'package:flutter_chat_app/services/notification_service.dart';
import 'package:flutter_chat_app/widgets/custom_button.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({Key? key}) : super(key: key);

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  final NotificationService _notificationService = NotificationService();
  bool _isNotificationsEnabled = true;
  bool _isSoundEnabled = true;
  bool _isSendingTestNotification = false;
  String? _testNotificationResult;
  bool _isTestSuccess = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() {
      _isNotificationsEnabled = _notificationService.isNotificationsEnabled;
      _isSoundEnabled = _notificationService.isSoundsEnabled;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notification Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Notifications toggle
          Card(
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Notification Preferences',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: const Text('Notifications'),
                    subtitle: const Text('Receive message notifications'),
                    value: _isNotificationsEnabled,
                    onChanged: (bool value) async {
                      await _notificationService.setNotificationsEnabled(value);
                      setState(() {
                        _isNotificationsEnabled = value;
                      });
                    },
                  ),
                  SwitchListTile(
                    title: const Text('Sounds'),
                    subtitle: const Text('Play sound with notifications'),
                    value: _isSoundEnabled,
                    onChanged: _isNotificationsEnabled
                        ? (bool value) async {
                            await _notificationService.setSoundsEnabled(value);
                            setState(() {
                              _isSoundEnabled = value;
                            });
                          }
                        : null,
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
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Test Notifications',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Send a test notification to verify that notifications are working properly on your device.',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: _isSendingTestNotification
                        ? const CircularProgressIndicator()
                        : CustomButton(
                            onPressed: () {
                              // Only proceed if notifications are enabled and not currently sending a test
                              if (_isNotificationsEnabled &&
                                  !_isSendingTestNotification) {
                                _sendTestNotification();
                              }
                            },
                            text: 'Send Test Notification',
                            color: _isNotificationsEnabled
                                ? Theme.of(context).primaryColor
                                : Colors.grey,
                          ),
                  ),
                  if (_testNotificationResult != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _isTestSuccess
                            ? Colors.green.withOpacity(0.1)
                            : Colors.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _isTestSuccess ? Colors.green : Colors.red,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _isTestSuccess ? Icons.check_circle : Icons.error,
                            color: _isTestSuccess ? Colors.green : Colors.red,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _testNotificationResult!,
                              style: TextStyle(
                                color: _isTestSuccess
                                    ? Colors.green.shade800
                                    : Colors.red.shade800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Notification permissions info
          Card(
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Troubleshooting',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'If you are not receiving notifications, check the following:',
                    style: TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '• Make sure notifications are enabled in your device settings\n'
                    '• Check that the app has notification permissions\n'
                    '• Verify your device is connected to the internet\n'
                    '• Make sure battery optimization settings are not restricting the app',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _sendTestNotification() async {
    if (_isSendingTestNotification) return;

    setState(() {
      _isSendingTestNotification = true;
      _testNotificationResult = null;
    });

    try {
      final response = await _notificationService.sendTestNotification();

      if (response['success'] == true) {
        setState(() {
          _testNotificationResult =
              'Test notification sent successfully! You should receive it shortly.';
          _isTestSuccess = true;
        });
      } else {
        setState(() {
          _testNotificationResult =
              'Failed to send test notification: ${response['message'] ?? 'Unknown error'}';
          _isTestSuccess = false;
        });
      }
    } catch (e) {
      setState(() {
        _testNotificationResult = 'Error sending test notification: $e';
        _isTestSuccess = false;
      });
    } finally {
      setState(() {
        _isSendingTestNotification = false;
      });
    }
  }
}
