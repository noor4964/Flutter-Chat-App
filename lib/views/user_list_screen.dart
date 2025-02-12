import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_chat_app/services/chat_service.dart';
import 'package:flutter_chat_app/services/auth_service.dart';
import 'package:flutter_chat_app/views/chat/chat_screen.dart';

class UserListScreen extends StatefulWidget {
  @override
  _UserListScreenState createState() => _UserListScreenState();
}

class _UserListScreenState extends State<UserListScreen> {
  final ChatService _chatService = ChatService();
  final AuthService _authService = AuthService();
  final User? user = FirebaseAuth.instance.currentUser;
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];

  void _searchUsers(String query) async {
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
      });
      return;
    }

    QuerySnapshot userSnapshot = await FirebaseFirestore.instance
        .collection('users')
        .where('username', isEqualTo: query)
        .get();

    setState(() {
      _searchResults = userSnapshot.docs.map((doc) {
        if (doc.exists) {
          return doc.data() as Map<String, dynamic>;
        } else {
          return {};
        }
      }).toList().cast<Map<String, dynamic>>();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('User List'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by username',
                suffixIcon: IconButton(
                  icon: Icon(Icons.search),
                  onPressed: () {
                    _searchUsers(_searchController.text);
                  },
                ),
              ),
            ),
          ),
          Expanded(
            child: _searchResults.isEmpty
                ? Center(child: Text('No users found'))
                : ListView.builder(
                    itemCount: _searchResults.length,
                    itemBuilder: (context, index) {
                      var user = _searchResults[index];
                      if (user.isEmpty) {
                        return ListTile(
                          title: Text('User not found'),
                        );
                      }
                      String? userId = user['uid'];
                      if (userId == null) {
                        return ListTile(
                          title: Text('User ID is missing'),
                        );
                      }
                      return ListTile(
                        title: Text(user['username']),
                        subtitle: Text(user['email']),
                        leading: CircleAvatar(child: Text(user['username'][0])),
                        trailing: IconButton(
                          icon: Icon(Icons.person_add),
                          onPressed: () async {
                            await _authService.sendConnectionRequest(userId);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Connection request sent to ${user['username']}')),
                            );
                          },
                        ),
                        onTap: () async {
                          if (this.user == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('User not logged in')),
                            );
                            return;
                          }
                          // Check if a chat already exists with the selected user
                          String? existingChatId = await _chatService.getExistingChatId(this.user!.uid, userId);
                          if (existingChatId != null) {
                            // Navigate to the existing chat
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ChatScreen(chatId: existingChatId),
                              ),
                            );
                          } else {
                            // Create a new chat with the selected user
                            String chatId = (await _chatService.createChat(
                              [this.user!.uid, userId],
                              user['username'],
                            ))!;
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ChatScreen(chatId: chatId),
                              ),
                            );
                          }
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}