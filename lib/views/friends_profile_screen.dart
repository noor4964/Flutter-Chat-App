import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_chat_app/views/chat/chat_screen.dart';
import 'package:flutter_chat_app/services/chat_service.dart';
import 'package:flutter_chat_app/views/user_profile_screen.dart';

class FriendsProfileScreen extends StatefulWidget {
  const FriendsProfileScreen({Key? key}) : super(key: key);

  @override
  _FriendsProfileScreenState createState() => _FriendsProfileScreenState();
}

class _FriendsProfileScreenState extends State<FriendsProfileScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ChatService _chatService = ChatService();

  late Stream<List<Map<String, dynamic>>> _friendsStream;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _initFriendsStream();
  }

  void _initFriendsStream() {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return;

    _friendsStream = _firestore
        .collection('connections')
        .where('status', isEqualTo: 'accepted')
        .where(Filter.or(Filter('senderId', isEqualTo: userId),
            Filter('receiverId', isEqualTo: userId)))
        .snapshots()
        .asyncMap((snapshot) async {
      if (snapshot.docs.isEmpty) return [];

      // Extract the friend IDs from connections
      List<Map<String, String>> connections = [];
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final String friendId =
            data['senderId'] == userId ? data['receiverId'] : data['senderId'];
        connections.add({
          'connectionId': doc.id,
          'friendId': friendId,
        });
      }

      // Get all friend IDs
      List<String> friendIds = connections.map((c) => c['friendId']!).toList();

      // Fetch all friend profiles in one batch
      final userDocs = await _firestore
          .collection('users')
          .where('uid', whereIn: friendIds)
          .get();

      // Create a map for quick lookup
      Map<String, Map<String, dynamic>> friendProfiles = {};
      for (var doc in userDocs.docs) {
        final data = doc.data();
        friendProfiles[data['uid']] = data;
      }

      // Combine connection info with profile data
      return connections.map((connection) {
        final friendId = connection['friendId']!;
        final connectionId = connection['connectionId']!;
        final profile =
            friendProfiles[friendId] ?? {'username': 'Unknown User'};

        return {
          'connectionId': connectionId,
          'friendId': friendId,
          ...profile,
        };
      }).toList();
    });
  }

  void _onSearch(String query) {
    setState(() {
      _searchQuery = query.toLowerCase();
    });
  }

  void _removeFriend(String connectionId, String friendName) async {
    // Show confirmation dialog
    final bool confirm = await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Remove Friend'),
            content: Text(
                'Are you sure you want to remove $friendName from your friends?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child:
                    const Text('Remove', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirm) return;

    try {
      // Delete the connection document
      await _firestore.collection('connections').doc(connectionId).delete();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('$friendName has been removed from your friends')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to remove friend: $e')),
      );
    }
  }

  Future<void> _startChat(String friendId, String friendName) async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return;

    try {
      // Check if chat already exists
      String? existingChatId =
          await _chatService.getExistingChatId(userId, friendId);

      if (existingChatId != null) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatScreen(chatId: existingChatId),
          ),
        );
      } else {
        // Create new chat
        String? chatId = await _chatService.createChat(
          [userId, friendId],
          friendName,
        );

        if (chatId != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ChatScreen(chatId: chatId),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to create chat. Please try again.'),
              backgroundColor: Colors.red,
            ),
          );
        }
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

  void _viewFriendProfile(Map<String, dynamic> friend) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => UserProfileScreen(
          profileImageUrl: friend['profileImageUrl'] ?? '',
          username: friend['username'] ?? 'Unknown',
          isOnline: friend['isOnline'] ?? false,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Friends'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add),
            tooltip: 'Add Friend',
            onPressed: () {
              Navigator.pushNamed(context, '/user_list');
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search friends...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.grey.withOpacity(0.1),
                contentPadding: EdgeInsets.zero,
              ),
              onChanged: _onSearch,
            ),
          ),

          // Friends list
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _friendsStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline,
                            size: 48, color: Colors.orange),
                        const SizedBox(height: 16),
                        Text('Error loading friends: ${snapshot.error}'),
                        const SizedBox(height: 8),
                        ElevatedButton(
                          onPressed: () => setState(() {
                            _initFriendsStream();
                          }),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  );
                }

                final List<Map<String, dynamic>> friends = snapshot.data ?? [];

                if (friends.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.people_outline,
                          size: 64,
                          color: colorScheme.primary.withOpacity(0.5),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'No friends yet',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Add friends to chat with them',
                          style: TextStyle(
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.person_add),
                          label: const Text('Find Friends'),
                          onPressed: () {
                            Navigator.pushNamed(context, '/user_list');
                          },
                        ),
                      ],
                    ),
                  );
                }

                // Filter friends by search query if needed
                final List<Map<String, dynamic>> filteredFriends =
                    _searchQuery.isEmpty
                        ? friends
                        : friends
                            .where((friend) =>
                                (friend['username'] as String?)
                                    ?.toLowerCase()
                                    .contains(_searchQuery) ??
                                false)
                            .toList();

                if (filteredFriends.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.search_off,
                          size: 64,
                          color: Colors.grey.withOpacity(0.5),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No friends match "$_searchQuery"',
                          style: const TextStyle(
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: filteredFriends.length,
                  itemBuilder: (context, index) {
                    final friend = filteredFriends[index];
                    final bool isOnline = friend['isOnline'] ?? false;

                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      child: ListTile(
                        leading: Stack(
                          children: [
                            CircleAvatar(
                              backgroundImage:
                                  friend['profileImageUrl'] != null &&
                                          friend['profileImageUrl'].isNotEmpty
                                      ? NetworkImage(friend['profileImageUrl'])
                                      : null,
                              child: friend['profileImageUrl'] == null ||
                                      friend['profileImageUrl'].isEmpty
                                  ? Text(
                                      (friend['username'] as String?)
                                                  ?.isNotEmpty ==
                                              true
                                          ? (friend['username'] as String)
                                              .substring(0, 1)
                                              .toUpperCase()
                                          : '?',
                                      style: TextStyle(
                                        color: colorScheme.onPrimary,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    )
                                  : null,
                            ),
                            if (isOnline)
                              Positioned(
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: Colors.green,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: theme.cardColor,
                                      width: 2,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        title: Text(
                          friend['username'] ?? 'Unknown User',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: Text(
                          isOnline ? 'Online' : 'Offline',
                          style: TextStyle(
                            color: isOnline ? Colors.green : Colors.grey,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.message),
                              tooltip: 'Send Message',
                              onPressed: () => _startChat(
                                friend['friendId'],
                                friend['username'] ?? 'Unknown User',
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.more_vert),
                              onPressed: () {
                                showModalBottomSheet(
                                  context: context,
                                  builder: (context) => SafeArea(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        ListTile(
                                          leading: const Icon(Icons.person),
                                          title: const Text('View Profile'),
                                          onTap: () {
                                            Navigator.pop(context);
                                            _viewFriendProfile(friend);
                                          },
                                        ),
                                        ListTile(
                                          leading: const Icon(Icons.call),
                                          title: const Text('Voice Call'),
                                          onTap: () {
                                            Navigator.pop(context);
                                            // Implement call functionality
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              const SnackBar(
                                                  content: Text(
                                                      'Call feature coming soon')),
                                            );
                                          },
                                        ),
                                        ListTile(
                                          leading: const Icon(Icons.videocam),
                                          title: const Text('Video Call'),
                                          onTap: () {
                                            Navigator.pop(context);
                                            // Implement video call functionality
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              const SnackBar(
                                                  content: Text(
                                                      'Video call feature coming soon')),
                                            );
                                          },
                                        ),
                                        ListTile(
                                          leading: const Icon(
                                              Icons.person_remove,
                                              color: Colors.red),
                                          title: const Text('Remove Friend',
                                              style:
                                                  TextStyle(color: Colors.red)),
                                          onTap: () {
                                            Navigator.pop(context);
                                            _removeFriend(
                                              friend['connectionId'],
                                              friend['username'] ??
                                                  'this friend',
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                        onTap: () => _viewFriendProfile(friend),
                      ),
                    );
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
