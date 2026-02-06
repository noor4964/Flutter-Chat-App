import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class MessengerRightSidebar extends StatefulWidget {
  final int currentIndex;

  const MessengerRightSidebar({
    Key? key,
    required this.currentIndex,
  }) : super(key: key);

  @override
  _MessengerRightSidebarState createState() => _MessengerRightSidebarState();
}

class _MessengerRightSidebarState extends State<MessengerRightSidebar> {
  List<Map<String, dynamic>> _recentChats = [];
  List<Map<String, dynamic>> _onlineFriends = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRightSidebarData();
  }

  Future<void> _loadRightSidebarData() async {
    await Future.wait([
      _loadRecentChats(),
      _loadOnlineFriends(),
    ]);
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadRecentChats() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        QuerySnapshot chatsSnapshot = await FirebaseFirestore.instance
            .collection('chats')
            .where('participants', arrayContains: user.uid)
            .orderBy('lastMessageTime', descending: true)
            .limit(5)
            .get();

        List<Map<String, dynamic>> chats = [];
        for (var doc in chatsSnapshot.docs) {
          var chatData = doc.data() as Map<String, dynamic>;
          List<String> participants = List<String>.from(chatData['participants']);
          String otherUserId = participants.firstWhere((id) => id != user.uid);

          // Get other user's data
          DocumentSnapshot otherUserDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(otherUserId)
              .get();

          if (otherUserDoc.exists) {
            var otherUserData = otherUserDoc.data() as Map<String, dynamic>;
            chats.add({
              'chatId': doc.id,
              'otherUserId': otherUserId,
              'otherUserName': otherUserData['username'] ?? 'Unknown',
              'otherUserImage': otherUserData['profileImageUrl'],
              'lastMessage': chatData['lastMessage'] ?? '',
              'lastMessageTime': chatData['lastMessageTime'],
            });
          }
        }

        if (mounted) {
          setState(() {
            _recentChats = chats;
          });
        }
      } catch (e) {
        print('Error loading recent chats: $e');
      }
    }
  }

  Future<void> _loadOnlineFriends() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        // Get friends list
        QuerySnapshot friendsSnapshot = await FirebaseFirestore.instance
            .collection('connections')
            .where('senderId', isEqualTo: user.uid)
            .where('status', isEqualTo: 'accepted')
            .limit(8)
            .get();

        List<Map<String, dynamic>> friends = [];
        for (var doc in friendsSnapshot.docs) {
          var connectionData = doc.data() as Map<String, dynamic>;
          String friendId = connectionData['receiverId'];

          // Get friend's data
          DocumentSnapshot friendDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(friendId)
              .get();

          if (friendDoc.exists) {
            var friendData = friendDoc.data() as Map<String, dynamic>;
            friends.add({
              'userId': friendId,
              'username': friendData['username'] ?? 'Unknown',
              'profileImageUrl': friendData['profileImageUrl'],
              'isOnline': friendData['isOnline'] ?? false,
              'lastSeen': friendData['lastSeen'],
            });
          }
        }

        if (mounted) {
          setState(() {
            _onlineFriends = friends;
          });
        }
      } catch (e) {
        print('Error loading online friends: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        color: Theme.of(context).cardColor,
        child: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Container(
      color: Theme.of(context).cardColor,
      child: Column(
        children: [
          // Quick Actions Section
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context).dividerColor,
                  width: 1,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Quick Actions',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildQuickActionButton(
                        context,
                        icon: Icons.add,
                        label: 'New Post',
                        onTap: () => Navigator.pushNamed(context, '/create-post'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildQuickActionButton(
                        context,
                        icon: Icons.video_call,
                        label: 'Start Call',
                        onTap: () => Navigator.pushNamed(context, '/start-call'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Recent Chats Section
          if (_recentChats.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Recent Chats',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          // Switch to chats tab
                          if (widget.currentIndex != 1) {
                            // This would need to be passed up to parent
                          }
                        },
                        child: Text('View All'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...(_recentChats.take(3).map((chat) => _buildRecentChatItem(context, chat))),
                ],
              ),
            ),
          ],

          // Online Friends Section
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Friends (${_onlineFriends.where((f) => f['isOnline'] == true).length} online)',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _onlineFriends.length,
                      itemBuilder: (context, index) {
                        return _buildFriendItem(context, _onlineFriends[index]);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).primaryColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Theme.of(context).primaryColor.withOpacity(0.2),
            width: 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: Theme.of(context).primaryColor,
              size: 20,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).primaryColor,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentChatItem(BuildContext context, Map<String, dynamic> chat) {
    return InkWell(
      onTap: () {
        Navigator.pushNamed(
          context,
          '/chat',
          arguments: {
            'chatId': chat['chatId'],
            'otherUserId': chat['otherUserId'],
            'otherUserName': chat['otherUserName'],
          },
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundImage: chat['otherUserImage'] != null
                  ? NetworkImage(chat['otherUserImage'])
                  : null,
              child: chat['otherUserImage'] == null
                  ? Icon(Icons.person, size: 16)
                  : null,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    chat['otherUserName'],
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (chat['lastMessage'].isNotEmpty)
                    Text(
                      chat['lastMessage'],
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.7),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFriendItem(BuildContext context, Map<String, dynamic> friend) {
    bool isOnline = friend['isOnline'] ?? false;
    
    return InkWell(
      onTap: () {
        // Start chat with friend
        Navigator.pushNamed(
          context,
          '/chat-with-user',
          arguments: {
            'userId': friend['userId'],
            'username': friend['username'],
          },
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundImage: friend['profileImageUrl'] != null
                      ? NetworkImage(friend['profileImageUrl'])
                      : null,
                  child: friend['profileImageUrl'] == null
                      ? Icon(Icons.person, size: 14)
                      : null,
                ),
                if (isOnline)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Theme.of(context).cardColor,
                          width: 1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                friend['username'],
                style: Theme.of(context).textTheme.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}