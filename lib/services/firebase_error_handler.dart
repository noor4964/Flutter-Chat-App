import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chat_app/services/firebase_config.dart';

/// A utility class for handling Firebase-related errors and providing recovery options
class FirebaseErrorHandler {
  // Singleton pattern
  static final FirebaseErrorHandler _instance = FirebaseErrorHandler._internal();
  factory FirebaseErrorHandler() => _instance;
  FirebaseErrorHandler._internal();

  // Flag to track if we're currently in the recovery process
  bool _isRecovering = false;
  
  // Flag to track if we should show error dialogs
  bool _suppressDialogs = false;

  /// Handle a Firebase exception, providing appropriate recovery steps
  Future<bool> handleFirebaseException(
    dynamic error,
    BuildContext? context, {
    bool showDialog = true,
  }) async {
    // If we're already trying to recover, don't stack recovery attempts
    if (_isRecovering) {
      print('🔄 Already attempting to recover from an error, skipping new recovery attempt');
      return false;
    }

    _isRecovering = true;
    bool recovered = false;

    try {
      print('❌ Firebase error detected: $error');
      
      // Check for specific Firestore error patterns
      if (error.toString().contains('INTERNAL ASSERTION FAILED') || 
          error.toString().contains('Unexpected state')) {
        print('🔍 Detected a Firestore assertion error, attempting recovery...');
        
        // Clear Firestore cache and restart Firebase
        await FirebaseConfig.clearFirestoreCache();
        await FirebaseConfig.restartFirebase();
        
        recovered = true;
        print('✅ Recovery process completed');
      }
      // Handle other Firebase error types as needed
      else if (error is FirebaseException) {
        if (error.code == 'unavailable' || error.code == 'resource-exhausted') {
          print('🔌 Firebase service unavailable, attempting to reconnect...');
          await FirebaseConfig.restartFirebase();
          recovered = true;
        }
      }
      
      // Show dialog if requested and we have a context
      if (showDialog && context != null && !_suppressDialogs) {
        _showErrorDialog(context, error, recovered);
      }
      
      return recovered;
    } catch (e) {
      print('❌ Error during recovery process: $e');
      return false;
    } finally {
      _isRecovering = false;
    }
  }
  
  /// Suppress error dialogs (useful during initial app load)
  void suppressDialogs(bool suppress) {
    _suppressDialogs = suppress;
  }

  /// Show an error dialog with recovery information
  void _showErrorDialog(BuildContext context, dynamic error, bool recovered) {
    // Don't show dialog if we don't have a valid context
    if (!context.mounted) return;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(recovered ? 'Recovered from Error' : 'Firebase Error'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                recovered
                    ? 'We detected a problem with the database connection and have fixed it automatically.'
                    : 'There was a problem with the database connection.',
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 16),
              if (!recovered) ...[
                const Text(
                  'Recommendation:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text('• Restart the app'),
                const Text('• Check your internet connection'),
                const Text('• Try again in a few minutes'),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
          if (!recovered)
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await FirebaseConfig.restartFirebase();
              },
              child: const Text('Try to Fix'),
            ),
        ],
      ),
    );
  }
}