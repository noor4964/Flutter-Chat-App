import 'package:flutter/material.dart';
import 'package:flutter_chat_app/services/platform_helper.dart';
import 'package:flutter_chat_app/widgets/responsive_layout.dart';
import 'package:flutter_chat_app/views/chat/chat_list_screen.dart';
import 'package:flutter_chat_app/views/chat/chat_detail_screen.dart';

class DesktopChatScreen extends StatefulWidget {
  const DesktopChatScreen({Key? key}) : super(key: key);

  @override
  State<DesktopChatScreen> createState() => _DesktopChatScreenState();
}

class _DesktopChatScreenState extends State<DesktopChatScreen> {
  String? selectedChatId;
  String? selectedChatName;
  String? selectedProfileImageUrl;
  bool selectedIsOnline = false;

  void onChatSelected(
      String chatId, String chatName, String? profileImageUrl, bool isOnline) {
    print('=== DesktopChatScreen - Chat Selection ===');
    print('Chat ID: $chatId');
    print('Chat Name: $chatName');
    print('Profile URL: $profileImageUrl');
    print('Is Online: $isOnline');
    print('Previous Profile URL: $selectedProfileImageUrl');
    print('==========================================');

    setState(() {
      selectedChatId = chatId;
      selectedChatName = chatName;
      selectedProfileImageUrl = profileImageUrl;
      selectedIsOnline = isOnline;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Default right panel when no chat is selected
    Widget rightPanel = const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.chat_bubble_outline, size: 100, color: Colors.grey),
          SizedBox(height: 16),
          Text(
            'Select a conversation to start chatting',
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
        ],
      ),
    );

    // Show chat details if a chat is selected
    if (selectedChatId != null && selectedChatName != null) {
      rightPanel = ChatDetailScreen(
        key: ValueKey(
            'chat_${selectedChatId}_${selectedChatName.hashCode}_${selectedProfileImageUrl?.hashCode ?? 0}'), // Unique key for each chat/profile combo
        chatId: selectedChatId!,
        chatName: selectedChatName!,
        profileImageUrl: selectedProfileImageUrl,
        isOnline: selectedIsOnline,
      );
    }

    // Create a split-view layout for desktop
    return Scaffold(
      body: ResponsiveLayout.createSplitView(
        context: context,
        leftPanel: ChatListScreen(
          isDesktop: true,
          onChatSelected: onChatSelected,
        ),
        rightPanel: rightPanel,
        leftPanelWidth: PlatformHelper.getChatListWidth(context),
      ),
    );
  }
}
