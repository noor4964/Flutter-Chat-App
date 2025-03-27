import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;

class FirebaseConfig {
  static Future<void> initializeFirebase() async {
    FirebaseOptions? options;

    if (kIsWeb) {
      // Web-specific configuration
      options = const FirebaseOptions(
        apiKey: "AIzaSyCOhaSVRuqOWoYmhC4Bv72rII8i8C9kTIc",
        authDomain: "flutter-chat-app-e52b5.firebaseapp.com",
        projectId: "flutter-chat-app-e52b5",
        storageBucket: "flutter-chat-app-e52b5.firebasestorage.app",
        messagingSenderId: "218916781771",
        appId: "1:218916781771:web:0aa64d025f00d98e24a54e",
        databaseURL:
            "https://flutter-chat-app-e52b5-default-rtdb.firebaseio.com",
      );
    } else if (Platform.isWindows) {
      // Windows-specific configuration (using the same details for Windows)
      options = const FirebaseOptions(
        apiKey: "AIzaSyCOhaSVRuqOWoYmhC4Bv72rII8i8C9kTIc",
        appId: "1:218916781771:web:0aa64d025f00d98e24a54e",
        messagingSenderId: "218916781771",
        projectId: "flutter-chat-app-e52b5",
        databaseURL:
            "https://flutter-chat-app-e52b5-default-rtdb.firebaseio.com",
        storageBucket: "flutter-chat-app-e52b5.firebasestorage.app",
      );
    }

    // Initialize Firebase with platform-specific options
    if (options != null) {
      await Firebase.initializeApp(options: options);
    } else {
      // For Android and other platforms that use google-services.json
      await Firebase.initializeApp();
    }
  }
}
