import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_chat_app/services/platform_helper.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class FirebaseConfig {
  // Add a static getter to check if we are on web
  static bool get isWeb => kIsWeb;

  // Add a flag to track initialization state
  static bool _initialized = false;

  // Add a getter to check if Firebase is initialized
  static bool get isInitialized => _initialized;

  // Flag to determine if Firebase is enabled on Windows platform
  static bool get isFirebaseEnabledOnWindows =>
      true; // Set to false if you want to disable Firebase on Windows

  static Future<void> initializeFirebase() async {
    print('🔥 Starting Firebase initialization...');

    // Skip initialization if already initialized
    if (_initialized) {
      print('🔥 Firebase already initialized, skipping...');
      return;
    }

    // Check if Firebase is already initialized
    if (Firebase.apps.isNotEmpty) {
      _initialized = true;
      print('🔥 Firebase already has apps, skipping...');
      return;
    }

    FirebaseOptions? options;

    try {
      // Get proper Firebase options based on platform
      if (kIsWeb) {
        // Web-specific configuration
        print('🔥 Initializing Firebase for Web with explicit config');
        options = const FirebaseOptions(
          apiKey: "AIzaSyCOhaSVRuqOWoYmhC4Bv72rII8i8C9kTIc",
          authDomain: "flutter-chat-app-e52b5.firebaseapp.com",
          projectId: "flutter-chat-app-e52b5",
          storageBucket: "flutter-chat-app-e52b5.appspot.com",
          messagingSenderId: "218916781771",
          appId: "1:218916781771:web:0aa64d025f00d98e24a54e",
          databaseURL:
              "https://flutter-chat-app-e52b5-default-rtdb.firebaseio.com",
        );
      } else if (PlatformHelper.isWindows ||
          PlatformHelper.isMacOS ||
          PlatformHelper.isLinux) {
        // Desktop-specific configuration (using the same details for desktop platforms)
        print('🔥 Initializing Firebase for Desktop with explicit config');
        options = const FirebaseOptions(
          apiKey: "AIzaSyCOhaSVRuqOWoYmhC4Bv72rII8i8C9kTIc",
          appId: "1:218916781771:web:0aa64d025f00d98e24a54e",
          messagingSenderId: "218916781771",
          projectId: "flutter-chat-app-e52b5",
          databaseURL:
              "https://flutter-chat-app-e52b5-default-rtdb.firebaseio.com",
          storageBucket: "flutter-chat-app-e52b5.appspot.com",
        );
      }

      // Initialize Firebase with platform-specific options or default configuration
      if (options != null) {
        print('🔥 Initializing Firebase with platform-specific options');
        await Firebase.initializeApp(options: options);
      } else {
        // For Android and iOS that use google-services.json/GoogleService-Info.plist
        print('🔥 Initializing Firebase for mobile platform');
        await Firebase.initializeApp();
      }

      // Configure Firestore settings with safer defaults
      FirebaseFirestore.instance.settings = Settings(
        persistenceEnabled: true,
        cacheSizeBytes: 10485760, // 10 MB - more conservative than unlimited
      );
      print('🔥 Configured Firestore with custom settings');

      // Configure Firebase Auth persistence for web
      if (kIsWeb) {
        try {
          await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
          print('🔥 Set Firebase Auth persistence to LOCAL for web');
        } catch (authError) {
          print('⚠️ Auth persistence error (non-critical): $authError');
        }
      }

      _initialized = true;
      print('✅ Firebase initialization successful');
    } catch (e) {
      print('❌ Error initializing Firebase: $e');

      // More specific error logging to help diagnose the issue
      if (e is FirebaseException) {
        print('❌ Firebase error code: ${e.code}');
        print('❌ Firebase error message: ${e.message}');
      }

      // Try fallback initialization if initial attempt fails
      if (Firebase.apps.isEmpty) {
        print('⚠️ Trying fallback initialization');
        try {
          await Firebase.initializeApp();

          FirebaseFirestore.instance.settings = Settings(
            persistenceEnabled: true,
            cacheSizeBytes:
                10485760, // 10 MB - more conservative than unlimited
          );

          _initialized = true;
          print('✅ Fallback initialization successful');
        } catch (fallbackError) {
          print('❌ Fallback initialization also failed: $fallbackError');
          _initialized = false;
          rethrow; // Re-throw to be handled by the application
        }
      }
    }
  }

  // Add a method to clear Firestore cache - can be called when errors occur
  static Future<void> clearFirestoreCache() async {
    try {
      print('🧹 Attempting to clear Firestore cache...');
      await FirebaseFirestore.instance.clearPersistence();
      print('✅ Firestore cache cleared successfully');
    } catch (e) {
      print('❌ Error clearing Firestore cache: $e');
    }
  }

  // Add a method to restart Firebase (useful for error recovery)
  static Future<void> restartFirebase() async {
    try {
      print('🔄 Restarting Firebase...');

      // First terminate all Firebase apps
      for (final app in Firebase.apps) {
        await app.delete();
      }

      // Clear the initialization flag
      _initialized = false;

      // Re-initialize Firebase
      await initializeFirebase();

      print('✅ Firebase restart completed successfully');
    } catch (e) {
      print('❌ Error during Firebase restart: $e');
      rethrow; // Re-throw to be handled by the application
    }
  }
}
