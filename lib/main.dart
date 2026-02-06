import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_chat_app/providers/auth_provider.dart' as app_provider;
import 'package:flutter_chat_app/providers/chat_provider.dart';
import 'package:flutter_chat_app/providers/feed_provider.dart';
import 'package:flutter_chat_app/services/feed_service.dart';
import 'package:flutter_chat_app/services/firebase_config.dart';
import 'package:flutter_chat_app/services/firebase_error_handler.dart';
import 'package:flutter_chat_app/services/notification_service.dart';
import 'package:flutter_chat_app/services/enhanced_notification_service.dart';
import 'package:flutter_chat_app/services/platform_helper.dart';
import 'package:flutter_chat_app/services/presence_service.dart';
import 'package:flutter_chat_app/views/auth/login_screen.dart';
import 'package:flutter_chat_app/views/chat/desktop_chat_screen.dart';
import 'package:flutter_chat_app/services/navigator_observer.dart';
import 'package:flutter_chat_app/widgets/responsive_layout.dart';
import 'package:provider/provider.dart';
import 'package:flutter_chat_app/providers/theme_provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_chat_app/views/messenger_home_screen.dart';
import 'package:flutter_chat_app/services/calls/call_service.dart';
import 'package:flutter_chat_app/views/user_list_screen.dart';
import 'package:flutter_chat_app/screens/notification_test_screen.dart';
import 'package:flutter_chat_app/services/calls/enhanced_call_service.dart';
import 'package:flutter_chat_app/views/calls/enhanced_audio_call_screen.dart';

import 'services/story_service.dart';

// Define global navigatorKey for push notifications
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase with error handling
  try {
    await FirebaseConfig.initializeFirebase();

    // Create error handler immediately
    final errorHandler = FirebaseErrorHandler();
    errorHandler.suppressDialogs(true); // Prevent dialogs during startup

    // Only initialize platform-specific features on supported platforms
    if (PlatformHelper.isIOS || PlatformHelper.isAndroid) {
      // Initialize CallKit plugin for handling calls only on iOS/Android
      await _initCallKit();

      // Initialize the enhanced notification service
      final enhancedNotificationService = EnhancedNotificationService();
      await enhancedNotificationService.initialize();
      
      // Initialize the basic notification service as backup
      final notificationService = NotificationService();
      await notificationService.initialize();
    } else {
      print(
          'ℹ️ Skipping CallKit and notification initialization on ${PlatformHelper.isWeb ? 'web' : PlatformHelper.isDesktop ? 'desktop' : 'unknown'} platform');
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
        ChangeNotifierProvider(create: (context) {
          final chatProvider = ChatProvider();
          chatProvider.initialize();
          return chatProvider;
        }),
        ChangeNotifierProvider(create: (context) {
          final feedProvider = FeedProvider();
          feedProvider.initialize();
          return feedProvider;
        }),
      ],
      child: MyApp(),
    ),
  );
}

// Initialize CallKit for handling incoming/outgoing calls
Future<void> _initCallKit() async {
  // Skip if not on iOS or Android
  if (!PlatformHelper.isIOS && !PlatformHelper.isAndroid) {
    print('ℹ️ Skipping CallKit initialization on non-mobile platform');
    return;
  }

  try {
    // Set up CallKit event listeners
    FlutterCallkitIncoming.onEvent.listen((event) async {
      if (event == null) return;

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
        navigatorKey:
            navigatorKey, // Add global navigator key for notifications
        title: 'Flutter Chat App',
        theme: themeProvider.themeData,
        home: const AuthenticationWrapper(),
        navigatorObservers: [MyNavigatorObserver()],
        debugShowCheckedModeBanner: false,
        routes: {
          '/user_list': (context) => UserListScreen(),
          '/chat': (context) => const MessengerHomeScreen(isDesktop: false),
          '/requests': (context) => UserListScreen(),
          '/home': (context) => const HomeScreen(),
          '/notification_test': (context) => const NotificationTestScreen(),
        },
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
    // Simplified Firebase status check - no restart attempts
    print('🔍 Checking Firebase status...');
    
    if (FirebaseConfig.isInitialized) {
      print('✅ Firebase is initialized and ready');
      setState(() {
        _isInitializing = false;
        _errorMessage = null;
      });
    } else {
      print('⚠️ Firebase not initialized, but continuing...');
      setState(() {
        _isInitializing = false;
        _errorMessage = null; // Don't show error, let the app continue
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

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  // Add WidgetsBindingObserver to track app lifecycle
  
  StreamSubscription<Call>? _incomingCallSubscription;
  EnhancedCallService? _enhancedCallService;

  @override
  void initState() {
    super.initState();
    _initializeCollections();
    _initializePresence();
    _initializeCallListening();

    // Register lifecycle observer
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    // Unregister lifecycle observer
    WidgetsBinding.instance.removeObserver(this);
    _setUserOffline();
    _incomingCallSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // App in foreground - set user as online
      _setUserOnline();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      // App in background or closed - set user as offline
      _setUserOffline();
    }
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

  // Initialize presence and set user online
  Future<void> _initializePresence() async {
    try {
      // Import the presence service at the top of the file
      final presenceService = PresenceService();
      await presenceService.goOnline();
      print('✅ User set to online');
    } catch (e) {
      print('❌ Error initializing presence: $e');
    }
  }

  // Initialize incoming call listening
  Future<void> _initializeCallListening() async {
    try {
      _enhancedCallService = EnhancedCallService();
      await _enhancedCallService!.initialize();
      
      // Listen for incoming calls
      _incomingCallSubscription = _enhancedCallService!.listenForIncomingCalls().listen(
        (Call incomingCall) {
          print('📞 Incoming call detected: ${incomingCall.callId}');
          
          // Only handle actual incoming calls (not the empty placeholder)
          if (incomingCall.callId != 'no-call' && incomingCall.status == 'ringing') {
            _handleIncomingCall(incomingCall);
          }
        },
        onError: (error) {
          print('❌ Error listening for incoming calls: $error');
        },
      );
      
      print('✅ Call listening initialized');
    } catch (e) {
      print('❌ Error initializing call listening: $e');
    }
  }

  // Handle incoming call by navigating to the call screen
  void _handleIncomingCall(Call call) {
    print('🔔 Handling incoming call from: ${call.callerName}');
    
    // Navigate to the enhanced audio call screen
    if (mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => EnhancedAudioCallScreen(
            call: call,
            isIncoming: true,
          ),
        ),
      );
    }
  }

  // Set user as online
  Future<void> _setUserOnline() async {
    try {
      final presenceService = PresenceService();
      await presenceService.goOnline();
    } catch (e) {
      print('❌ Error setting user online: $e');
    }
  }

  // Set user as offline
  Future<void> _setUserOffline() async {
    try {
      final presenceService = PresenceService();
      await presenceService.goOffline();
    } catch (e) {
      print('❌ Error setting user offline: $e');
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
