import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_chat_app/services/platform_helper.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class FirebaseConfig {
  // Add a static getter to check if Firebase is enabled on Windows
  static bool get isFirebaseEnabledOnWindows =>
      true; // Change to false to disable Firebase on Windows

  // Add a static getter to check if we are on web
  static bool get isWeb => kIsWeb;

  // Add a flag to track initialization state
  static bool _initialized = false;

  // Add a getter to check if Firebase is initialized
  static bool get isInitialized => _initialized;

  static Future<void> initializeFirebase() async {
    print('🔥 Starting Firebase initialization...');

    // Skip initialization if already initialized
    if (_initialized || Firebase.apps.isNotEmpty) {
      print('🔥 Firebase already initialized, skipping...');
      return;
    }

    FirebaseOptions? options;

    if (kIsWeb) {
      // Web-specific configuration
      print('🔥 Initializing Firebase for Web with explicit config');
      options = const FirebaseOptions(
        apiKey: "AIzaSyCOhaSVRuqOWoYmhC4Bv72rII8i8C9kTIc",
        authDomain: "flutter-chat-app-e52b5.firebaseapp.com",
        projectId: "flutter-chat-app-e52b5",
        storageBucket:
            "flutter-chat-app-e52b5.appspot.com", // Fixed storage bucket URL
        messagingSenderId: "218916781771",
        appId: "1:218916781771:web:0aa64d025f00d98e24a54e",
        databaseURL:
            "https://flutter-chat-app-e52b5-default-rtdb.firebaseio.com",
      );
    } else if (PlatformHelper.isWindows) {
      // Windows-specific configuration (using the same details for Windows)
      print('🔥 Initializing Firebase for Windows with explicit config');
      options = const FirebaseOptions(
        apiKey: "AIzaSyCOhaSVRuqOWoYmhC4Bv72rII8i8C9kTIc",
        appId: "1:218916781771:web:0aa64d025f00d98e24a54e",
        messagingSenderId: "218916781771",
        projectId: "flutter-chat-app-e52b5",
        databaseURL:
            "https://flutter-chat-app-e52b5-default-rtdb.firebaseio.com",
        storageBucket:
            "flutter-chat-app-e52b5.appspot.com", // Fixed storage bucket URL
      );
    }

    try {
      // Initialize Firebase with platform-specific options
      if (options != null) {
        print('🔥 Initializing Firebase with platform-specific options');
        await Firebase.initializeApp(options: options);
      } else {
        // For Android and other platforms that use google-services.json
        print('🔥 Initializing Firebase for non-web platform');
        await Firebase.initializeApp();
      }

      // Configure Firestore settings to prevent potential issues
      final firestoreSettings = Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );

      FirebaseFirestore.instance.settings = firestoreSettings;
      print('🔥 Configured Firestore with custom settings');

      // Configure Firebase Auth persistence for web
      if (kIsWeb) {
        try {
          await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
          print('🔥 Set Firebase Auth persistence to LOCAL for web');
        } catch (authError) {
          print('⚠️ Auth persistence error (non-critical): $authError');
          // Continue despite auth persistence error as it's not critical
        }
      }

      // Check if there's a logged-in user after initialization
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        print(
            '🔥 Found logged in user after initialization: ${currentUser.uid}');
      } else {
        print('🔥 No logged in user found after initialization');
      }

      _initialized = true;
      print('✅ Firebase initialization successful');
    } catch (e) {
      print('❌ Error initializing Firebase: $e');
      // If initialization fails, try to recover
      if (Firebase.apps.isEmpty) {
        print('⚠️ Trying fallback initialization');
        try {
          await Firebase.initializeApp();

          // Also set up basic Firestore settings in fallback mode
          FirebaseFirestore.instance.settings = Settings(
            persistenceEnabled: true,
            cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
          );

          _initialized = true;
          print('✅ Fallback initialization successful');
        } catch (fallbackError) {
          print('❌ Fallback initialization also failed: $fallbackError');
          _initialized = false;
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
    }
  }
}
