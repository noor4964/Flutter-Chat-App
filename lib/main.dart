import 'package:flutter/material.dart';
import 'package:flutter_chat_app/services/firebase_config.dart';
import 'package:flutter_chat_app/services/platform_helper.dart';
import 'package:flutter_chat_app/views/auth/login_screen.dart';
import 'package:flutter_chat_app/views/chat/chat_detail_screen.dart';
import 'package:flutter_chat_app/views/chat/chat_list_screen.dart';
import 'package:flutter_chat_app/views/chat/desktop_chat_screen.dart';
import 'package:flutter_chat_app/services/navigator_observer.dart';
import 'package:flutter_chat_app/widgets/responsive_layout.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FirebaseConfig.initializeFirebase();
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Chat App',
      theme: ThemeData(
        primarySwatch: Colors.deepPurple,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const AuthenticationWrapper(),
      navigatorObservers: [MyNavigatorObserver()],
      debugShowCheckedModeBanner: false,
    );
  }
}

class AuthenticationWrapper extends StatelessWidget {
  const AuthenticationWrapper({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // You would typically check authentication status here
    // For now, we'll just show the login screen
    return const LoginScreen();
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Use responsive layout to determine which view to show
    return ResponsiveLayout(
      // Mobile view shows just the chat list
      mobileView: ChatListScreen(
        isDesktop: false,
        onChatSelected: (chatId, chatName) {
          // Navigate to chat detail screen on mobile
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ChatDetailScreen(
                chatId: chatId,
                chatName: chatName,
              ),
            ),
          );
        },
      ),

      // Desktop view shows a split screen with chat list and detail
      desktopView: const DesktopChatScreen(),
    );
  }
}
