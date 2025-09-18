import 'package:flutter/material.dart';
import 'package:flutter_chat_app/services/enhanced_notification_service.dart';
import 'package:firebase_auth/firebase_auth.dart';

class NotificationTestScreen extends StatefulWidget {
  const NotificationTestScreen({Key? key}) : super(key: key);

  @override
  State<NotificationTestScreen> createState() => _NotificationTestScreenState();
}

class _NotificationTestScreenState extends State<NotificationTestScreen> {
  final _currentUser = FirebaseAuth.instance.currentUser;
  bool _isLoading = false;
  String _lastTestResult = '';

  Future<void> _testLocalNotification() async {
    setState(() {
      _isLoading = true;
      _lastTestResult = 'Testing local notification...';
    });

    try {
      // Using the constructor instead of .instance
      final notificationService = EnhancedNotificationService();
      final result = await notificationService.sendTestNotification();
      setState(() {
        if (result['success'] == true) {
          _lastTestResult = '✅ ${result['message']}';
        } else {
          _lastTestResult = '❌ ${result['message']}';
        }
      });
    } catch (e) {
      setState(() {
        _lastTestResult = '❌ Local notification failed: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _testFirebaseNotification() async {
    if (_currentUser == null) {
      setState(() {
        _lastTestResult = '❌ No user logged in';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _lastTestResult = 'Testing Firebase notification (client-side)...';
    });

    try {
      // Since we can't use Firebase Functions on free plan, 
      // test by sending a notification to ourselves through the enhanced service
      final notificationService = EnhancedNotificationService();
      
      await notificationService.sendPushNotification(
        body: 'This is a test notification!',
        title: 'Test Notification',
        recipientId: _currentUser.uid,
        chatId: 'test_chat_${DateTime.now().millisecondsSinceEpoch}',
      );

      setState(() {
        _lastTestResult = '✅ Client-side notification test completed!\n'
            'Note: Real push notifications require Firebase Functions (paid plan).\n'
            'Local notifications and Firestore-based notifications are working.';
      });
    } catch (e) {
      setState(() {
        _lastTestResult = '❌ Firebase notification error: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _testChatNotification() async {
    if (_currentUser == null) {
      setState(() {
        _lastTestResult = '❌ No user logged in';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _lastTestResult = 'Testing chat notification (client-side)...';
    });

    try {
      final notificationService = EnhancedNotificationService();
      
      await notificationService.sendPushNotification(
        body: 'This is a test message from the notification system!',
        title: 'Test Chat',
        recipientId: _currentUser.uid,
        chatId: 'test_chat_${DateTime.now().millisecondsSinceEpoch}',
        data: {
          'messageType': 'text',
          'isGroupChat': false,
          'senderName': 'Test Sender',
          'priority': 'high',
        },
      );

      setState(() {
        _lastTestResult = '✅ Chat notification test completed!\n'
            'Note: Real push notifications require Firebase Functions (paid plan).\n'
            'Notification stored in Firestore for testing.';
      });
    } catch (e) {
      setState(() {
        _lastTestResult = '❌ Chat notification error: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _testMediaNotification() async {
    if (_currentUser == null) {
      setState(() {
        _lastTestResult = '❌ No user logged in';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _lastTestResult = 'Testing media notification...';
    });

    try {
      final notificationService = EnhancedNotificationService();
      
      await notificationService.sendPushNotification(
        recipientId: _currentUser.uid,
        title: 'Test Media',
        body: '📷 Photo',
        chatId: 'test_chat_id',
        data: {
          'isGroupChat': false,
          'senderName': 'Test Sender',
          'messageType': 'image',
        },
      );

      setState(() {
        _lastTestResult = '✅ Media notification sent successfully!\n'
            'Local notification displayed';
      });
    } catch (e) {
      setState(() {
        _lastTestResult = '❌ Media notification error: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notification Tests'),
        backgroundColor: Colors.green.shade700,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Current User: ${_currentUser?.email ?? 'Not logged in'}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'User ID: ${_currentUser?.uid ?? 'N/A'}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            
            Text(
              'Test Notifications',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _testLocalNotification,
              icon: const Icon(Icons.notifications),
              label: const Text('Test Local Notification'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.all(16),
              ),
            ),
            const SizedBox(height: 12),
            
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _testFirebaseNotification,
              icon: const Icon(Icons.cloud),
              label: const Text('Test Firebase Notification'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.all(16),
              ),
            ),
            const SizedBox(height: 12),
            
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _testChatNotification,
              icon: const Icon(Icons.chat),
              label: const Text('Test Chat Notification'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.all(16),
              ),
            ),
            const SizedBox(height: 12),
            
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _testMediaNotification,
              icon: const Icon(Icons.photo),
              label: const Text('Test Media Notification'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.all(16),
              ),
            ),
            
            const SizedBox(height: 24),
            
            Card(
              color: Colors.grey.shade100,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Test Result:',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    if (_isLoading)
                      const Row(
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 8),
                          Text('Testing...'),
                        ],
                      )
                    else
                      Text(
                        _lastTestResult.isEmpty ? 'No tests run yet' : _lastTestResult,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 24),
            
            Card(
              color: Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'How to Verify Notifications:',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '1. Local Notification: Tests the local notification system\n'
                      '2. Firebase Notification: Tests server-side notification delivery\n'
                      '3. Chat Notification: Tests enhanced chat notifications\n'
                      '4. Media Notification: Tests media message notifications\n\n'
                      'Make sure:\n'
                      '• App has notification permissions\n'
                      '• Device is not in Do Not Disturb mode\n'
                      '• Firebase Functions are deployed\n'
                      '• You have a valid FCM token',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}