import 'package:flutter/material.dart';
import 'package:flutter_chat_app/services/firebase_config.dart';
import 'package:flutter_chat_app/services/platform_helper.dart';
import 'package:flutter_chat_app/views/auth/login_screen.dart';
import 'package:flutter_chat_app/views/chat/chat_detail_screen.dart';
import 'package:flutter_chat_app/views/chat/desktop_chat_screen.dart';
import 'package:flutter_chat_app/services/navigator_observer.dart';
import 'package:flutter_chat_app/widgets/responsive_layout.dart';
import 'package:provider/provider.dart';
import 'package:flutter_chat_app/providers/theme_provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_chat_app/views/messenger_home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FirebaseConfig.initializeFirebase();
  runApp(
    ChangeNotifierProvider(
      create: (context) => ThemeProvider(),
      child: MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return MaterialApp(
          title: 'Flutter Chat App',
          theme: themeProvider.themeData,
          home: const AuthenticationWrapper(),
          navigatorObservers: [MyNavigatorObserver()],
          debugShowCheckedModeBanner: false,
        );
      },
    );
  }
}

class AuthenticationWrapper extends StatelessWidget {
  const AuthenticationWrapper({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
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

class HomeScreen extends StatelessWidget {
  const HomeScreen({Key? key}) : super(key: key);

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
