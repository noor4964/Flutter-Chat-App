import 'package:flutter/material.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_chat_app/providers/auth_provider.dart' as app_provider;
import 'package:flutter_chat_app/services/feed_service.dart';
import 'package:flutter_chat_app/services/firebase_config.dart';
import 'package:flutter_chat_app/services/firebase_error_handler.dart';
import 'package:flutter_chat_app/services/platform_helper.dart';
import 'package:flutter_chat_app/services/story_service.dart';
import 'package:flutter_chat_app/views/auth/login_screen.dart';
import 'package:flutter_chat_app/views/chat/desktop_chat_screen.dart';
import 'package:flutter_chat_app/services/navigator_observer.dart';
import 'package:flutter_chat_app/widgets/responsive_layout.dart';
import 'package:provider/provider.dart';
import 'package:flutter_chat_app/providers/theme_provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_chat_app/views/messenger_home_screen.dart';
import 'package:flutter_chat_app/services/calls/call_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase with error handling
  try {
    await FirebaseConfig.initializeFirebase();

    // Verify Firestore connection by making a simple query
    print('🔍 Verifying Firestore connection...');
    await FirebaseConfig
        .clearFirestoreCache(); // Clear cache to prevent assertion errors

    // Create error handler immediately
    final errorHandler = FirebaseErrorHandler();
    errorHandler.suppressDialogs(true); // Prevent dialogs during startup

    // Initialize CallKit plugin for handling calls
    if (!PlatformHelper.isDesktop) {
      await _initCallKit();
    }
  } catch (e) {
    print('❌ Error during app initialization: $e');
    // We'll handle this in the app UI since we can't show dialogs here
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => ThemeProvider()),
        ChangeNotifierProvider(
            create: (context) => app_provider.AuthProvider()),
      ],
      child: MyApp(),
    ),
  );
}

// Initialize CallKit for handling incoming/outgoing calls
Future<void> _initCallKit() async {
  try {
    // Set up CallKit event listeners
    FlutterCallkitIncoming.onEvent.listen((event) async {
      final Map<String, dynamic> callEvent = event as Map<String, dynamic>;
      print('CallKit event: ${callEvent['event']}');

      switch (callEvent['event']) {
        case 'ACTION_CALL_ACCEPT':
          // User accepted the call
          print('Call accepted: ${callEvent['body']}');
          final CallService callService = CallService();
          await callService.initialize();
          await callService.answerCall(callEvent['body']['id']);
          break;

        case 'ACTION_CALL_DECLINE':
          // User declined the call
          print('Call declined: ${callEvent['body']}');
          final CallService callService = CallService();
          await callService.endCall(isDeclined: true);
          break;

        case 'ACTION_CALL_ENDED':
          // Call ended
          print('Call ended: ${callEvent['body']}');
          break;

        default:
          print('Unhandled call event: ${callEvent['event']}');
          break;
      }
    });

    print('✅ CallKit initialized successfully');
  } catch (e) {
    print('❌ Error initializing CallKit: $e');
  }
}

class MyApp extends StatelessWidget {
  final FirebaseErrorHandler _errorHandler = FirebaseErrorHandler();

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(builder: (context, themeProvider, child) {
      return MaterialApp(
        title: 'Flutter Chat App',
        theme: themeProvider.themeData,
        home: const AuthenticationWrapper(),
        navigatorObservers: [MyNavigatorObserver()],
        debugShowCheckedModeBanner: false,
        builder: (context, child) {
          // Enable error dialogs after app is built
          _errorHandler.suppressDialogs(false);

          // Return the child with error handling
          return child ?? const SizedBox.shrink();
        },
      );
    });
  }
}

class AuthenticationWrapper extends StatefulWidget {
  const AuthenticationWrapper({Key? key}) : super(key: key);

  @override
  State<AuthenticationWrapper> createState() => _AuthenticationWrapperState();
}

class _AuthenticationWrapperState extends State<AuthenticationWrapper> {
  bool _isInitializing = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _checkFirebaseStatus();
  }

  Future<void> _checkFirebaseStatus() async {
    try {
      // Verify Firebase is properly initialized
      if (!FirebaseConfig.isInitialized) {
        await FirebaseConfig.restartFirebase();
      }

      setState(() {
        _isInitializing = false;
        _errorMessage = null;
      });
    } catch (e) {
      setState(() {
        _isInitializing = false;
        _errorMessage =
            "Could not connect to the database. Please check your internet connection.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show loading or error state if initializing
    if (_isInitializing) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Connecting to database...'),
            ],
          ),
        ),
      );
    }

    // Show error message if there was a problem
    if (_errorMessage != null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () async {
                  setState(() {
                    _isInitializing = true;
                  });
                  await _checkFirebaseStatus();
                },
                child: const Text('Retry Connection'),
              ),
            ],
          ),
        ),
      );
    }

    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // Handle connection states
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        // Check if user is logged in
        if (snapshot.hasData && snapshot.data != null) {
          // User is logged in, show the appropriate screen
          return const HomeScreen();
        } else {
          // User is not logged in, show login screen
          return const LoginScreen();
        }
      },
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    _initializeCollections();
  }

  Future<void> _initializeCollections() async {
    try {
      // Initialize the posts collection if needed
      final feedService = FeedService();
      await feedService.initializePostsCollection(context: context);

      // Initialize the stories collection if needed
      final storyService = StoryService();
      await storyService.initializeStoriesCollection(context: context);
    } catch (e) {
      print('❌ Error initializing collections: $e');
      // Error is handled within the services
    }
  }

  @override
  Widget build(BuildContext context) {
    // Use responsive layout to determine which view to show
    return ResponsiveLayout(
      // Mobile view shows the messenger-style home screen with three sections (Chats, Stories, Menu)
      mobileView: const MessengerHomeScreen(isDesktop: false),

      // Desktop view shows a split screen with chat list and detail
      desktopView: const DesktopChatScreen(),
    );
  }
}
