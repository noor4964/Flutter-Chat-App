import 'package:flutter/material.dart';

class UserFriendlyErrorHandler {
  static String getReadableErrorMessage(dynamic error) {
    String errorStr = error.toString().toLowerCase();
    
    // Network-related errors
    if (errorStr.contains('network') || errorStr.contains('connection') || errorStr.contains('host lookup')) {
      return 'Please check your internet connection and try again.';
    }
    
    // Authentication errors
    if (errorStr.contains('permission') || errorStr.contains('unauthorized')) {
      return 'You don\'t have permission to perform this action.';
    }
    
    // Firebase/Firestore errors
    if (errorStr.contains('firestore') || errorStr.contains('firebase')) {
      return 'Service temporarily unavailable. Please try again in a moment.';
    }
    
    // File/media errors
    if (errorStr.contains('file') || errorStr.contains('image') || errorStr.contains('media') || errorStr.contains('cloudinary')) {
      return 'Unable to process the file. Please try with a different file.';
    }
    
    // Chat-specific errors
    if (errorStr.contains('chat') || errorStr.contains('message')) {
      return 'Unable to send message. Please check your connection.';
    }
    
    // Story/post errors
    if (errorStr.contains('story') || errorStr.contains('post')) {
      return 'Unable to process your content. Please try again.';
    }
    
    // Call errors
    if (errorStr.contains('call') || errorStr.contains('agora')) {
      return 'Call failed to connect. Please check your connection and try again.';
    }
    
    // User account errors
    if (errorStr.contains('user not found') || errorStr.contains('account')) {
      return 'Account not found. Please check your credentials.';
    }
    
    // Validation errors
    if (errorStr.contains('password') && errorStr.contains('match')) {
      return 'Passwords do not match. Please try again.';
    }
    
    // Default friendly message
    return 'Something went wrong. Please try again.';
  }

  static void showErrorSnackBar(BuildContext context, dynamic error, {
    Duration duration = const Duration(seconds: 4),
    SnackBarAction? action,
  }) {
    final message = getReadableErrorMessage(error);
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.white, size: 20),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(fontSize: 14),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.red.shade600,
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        duration: duration,
        action: action ?? SnackBarAction(
          label: 'OK',
          textColor: Colors.white,
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ),
      ),
    );
  }

  static void showSuccessSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(fontSize: 14),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        duration: Duration(seconds: 3),
      ),
    );
  }

  static void showInfoSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.info_outline, color: Colors.white, size: 20),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(fontSize: 14),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.blue.shade600,
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        duration: Duration(seconds: 3),
      ),
    );
  }

  static void showWarningSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.warning_outlined, color: Colors.white, size: 20),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(fontSize: 14),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.orange.shade600,
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        duration: Duration(seconds: 3),
      ),
    );
  }
}