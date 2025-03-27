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

  void onChatSelected(String chatId, String chatName) {
    setState(() {
      selectedChatId = chatId;
      selectedChatName = chatName;
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
        chatId: selectedChatId!,
        chatName: selectedChatName!,
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
