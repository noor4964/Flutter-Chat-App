import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/chat_service.dart';
import '../services/auth_service.dart';
import 'package:flutter_chat_app/views/chat/chat_screen.dart';
import 'dart:async';

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
  Timer? _debounce;

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _searchUsers(String query) {
    if (_debounce?.isActive ?? false) _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      if (query.isEmpty) {
        setState(() => _searchResults = []);
        return;
      }

      QuerySnapshot userSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .orderBy('username')
          .startAt([query]).endAt([query + '\uf8ff']).get();

      setState(() {
        _searchResults = userSnapshot.docs.map((doc) {
          var data = doc.data() as Map<String, dynamic>;
          data['uid'] = doc.id; // Ensure UID is included
          return data;
        }).toList();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('User List')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by username',
                suffixIcon: Icon(Icons.search),
              ),
              onChanged: _searchUsers, // Debounced live search
            ),
          ),
          Expanded(
            child: _searchResults.isEmpty
                ? const Center(child: Text('No users found'))
                : ListView.builder(
                    itemCount: _searchResults.length,
                    itemBuilder: (context, index) {
                      var searchedUser = _searchResults[index];
                      String? userId = searchedUser['uid'];

                      if (userId == null) {
                        return const ListTile(
                            title: Text('User ID is missing'));
                      }

                      return ListTile(
                        title: Text(searchedUser['username']),
                        subtitle: Text(searchedUser['email']),
                        leading: CircleAvatar(
                            child: Text(searchedUser['username'][0])),
                        trailing: IconButton(
                          icon: const Icon(Icons.person_add),
                          onPressed: () async {
                            await _authService.sendConnectionRequest(userId);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text(
                                      'Request sent to ${searchedUser['username']}')),
                            );
                          },
                        ),
                        onTap: () async {
                          if (user == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('User not logged in')),
                            );
                            return;
                          }

                          // Check if chat already exists
                          String? existingChatId = await _chatService
                              .getExistingChatId(user!.uid, userId);

                          if (existingChatId != null) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    ChatScreen(chatId: existingChatId),
                              ),
                            );
                          } else {
                            try {
                              // Create new chat
                              String? chatId = await _chatService.createChat(
                                [user!.uid, userId],
                                searchedUser['username'],
                              );

                              if (chatId != null) {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        ChatScreen(chatId: chatId),
                                  ),
                                );
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        'Failed to create chat. Please try again.'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            } catch (e) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Error creating chat: $e'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
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
