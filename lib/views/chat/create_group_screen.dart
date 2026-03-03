import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_chat_app/services/group_chat_service.dart';
import 'package:flutter_chat_app/views/chat/chat_screen.dart';
import 'package:provider/provider.dart';
import 'package:flutter_chat_app/providers/theme_provider.dart';
import 'package:flutter_chat_app/widgets/glass_scaffold.dart';
import 'package:flutter_chat_app/widgets/glass_container.dart';

/// Screen for creating a new group chat.
/// Users can set a group name, description, and select members to add.
class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({Key? key}) : super(key: key);

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _groupNameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _searchController = TextEditingController();
  final _groupChatService = GroupChatService();

  final Set<String> _selectedMembers = {};
  final Map<String, Map<String, dynamic>> _userCache = {};
  List<Map<String, dynamic>> _searchResults = [];
  bool _isCreating = false;
  bool _isSearching = false;

  // Connections (friends) to show by default
  List<Map<String, dynamic>> _connections = [];
  bool _connectionsLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadConnections();
  }

  @override
  void dispose() {
    _groupNameController.dispose();
    _descriptionController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// Load the current user's accepted connections (friends) to show by default.
  Future<void> _loadConnections() async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid == null) return;

    try {
      // Query connections where the current user is sender or receiver (two queries
      // to satisfy Firestore security rules that require user to be a participant)
      final sentSnap = await FirebaseFirestore.instance
          .collection('connections')
          .where('senderId', isEqualTo: currentUid)
          .where('status', isEqualTo: 'accepted')
          .get();
      final receivedSnap = await FirebaseFirestore.instance
          .collection('connections')
          .where('receiverId', isEqualTo: currentUid)
          .where('status', isEqualTo: 'accepted')
          .get();

      final friendIds = <String>{};
      for (final doc in sentSnap.docs) {
        final receiverId = doc.data()['receiverId'] as String?;
        if (receiverId != null) friendIds.add(receiverId);
      }
      for (final doc in receivedSnap.docs) {
        final senderId = doc.data()['senderId'] as String?;
        if (senderId != null) friendIds.add(senderId);
      }

      if (friendIds.isEmpty) {
        setState(() => _connectionsLoaded = true);
        return;
      }

      // Batch fetch friend profiles
      final friends = <Map<String, dynamic>>[];
      final idsList = friendIds.toList();
      for (var i = 0; i < idsList.length; i += 10) {
        final chunk =
            idsList.sublist(i, (i + 10).clamp(0, idsList.length));
        final usersSnap = await FirebaseFirestore.instance
            .collection('users')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        for (final doc in usersSnap.docs) {
          final data = doc.data();
          data['uid'] = doc.id;
          friends.add(data);
          _userCache[doc.id] = data;
        }
      }

      if (mounted) {
        setState(() {
          _connections = friends;
          _connectionsLoaded = true;
        });
      }
    } catch (e) {
      print('❌ Error loading connections: $e');
      if (mounted) setState(() => _connectionsLoaded = true);
    }
  }

  Future<void> _searchUsers(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    setState(() => _isSearching = true);

    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    try {
      final results = await FirebaseFirestore.instance
          .collection('users')
          .where('username', isGreaterThanOrEqualTo: query)
          .where('username', isLessThanOrEqualTo: '$query\uf8ff')
          .limit(20)
          .get();

      if (mounted) {
        setState(() {
          _searchResults = results.docs
              .where((doc) => doc.id != currentUid)
              .map((doc) {
            final data = doc.data();
            data['uid'] = doc.id;
            _userCache[doc.id] = data;
            return data;
          }).toList();
          _isSearching = false;
        });
      }
    } catch (e) {
      print('❌ Error searching users: $e');
      if (mounted) setState(() => _isSearching = false);
    }
  }

  Future<void> _createGroup() async {
    final groupName = _groupNameController.text.trim();
    if (groupName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a group name')),
      );
      return;
    }

    if (_selectedMembers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please add at least one member')),
      );
      return;
    }

    setState(() => _isCreating = true);

    try {
      final chatId = await _groupChatService.createGroupChat(
        groupName: groupName,
        memberIds: _selectedMembers.toList(),
        groupDescription: _descriptionController.text.trim(),
      );

      if (chatId != null && mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => ChatScreen(
              chatId: chatId,
              chatPersonName: groupName,
            ),
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to create group. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isGlass = themeProvider.isGlassMode;

    // List to display: search results when searching, otherwise connections
    final displayList = _searchController.text.trim().isNotEmpty
        ? _searchResults
        : _connections;

    return GlassScaffold(
      appBar: isGlass
          ? GlassAppBar(
              elevation: 0,
              title: const Text('New Group'),
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: TextButton.icon(
                    onPressed: _isCreating ? null : _createGroup,
                    icon: _isCreating
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check_rounded),
                    label: const Text('Create'),
                    style: TextButton.styleFrom(
                      foregroundColor: colorScheme.primary,
                    ),
                  ),
                ),
              ],
            )
          : AppBar(
              elevation: 0,
              title: const Text('New Group'),
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: TextButton.icon(
                    onPressed: _isCreating ? null : _createGroup,
                    icon: _isCreating
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check_rounded),
                    label: const Text('Create'),
                    style: TextButton.styleFrom(
                      foregroundColor: colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
      body: Column(
        children: [
          // ── Group info header ───────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
              border: Border(
                bottom: BorderSide(
                  color: colorScheme.outlineVariant.withOpacity(0.3),
                ),
              ),
            ),
            child: Row(
              children: [
                // Group avatar placeholder
                CircleAvatar(
                  radius: 32,
                  backgroundColor: colorScheme.primaryContainer,
                  child: Icon(
                    Icons.group_rounded,
                    size: 30,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 16),
                // Group name + description fields
                Expanded(
                  child: Column(
                    children: [
                      TextField(
                        controller: _groupNameController,
                        decoration: const InputDecoration(
                          hintText: 'Group name (required)',
                          border: InputBorder.none,
                          isDense: true,
                        ),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                        textCapitalization: TextCapitalization.words,
                      ),
                      TextField(
                        controller: _descriptionController,
                        decoration: const InputDecoration(
                          hintText: 'Description (optional)',
                          border: InputBorder.none,
                          isDense: true,
                        ),
                        style: const TextStyle(fontSize: 14),
                        maxLines: 1,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Selected members chips ──────────────────────────────────
          if (_selectedMembers.isNotEmpty)
            Container(
              height: 90,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: _selectedMembers.map((uid) {
                  final user = _userCache[uid];
                  final name = user?['username'] ?? 'Unknown';
                  final imgUrl = user?['profileImageUrl'] ?? '';

                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Stack(
                          children: [
                            CircleAvatar(
                              radius: 22,
                              backgroundColor: colorScheme.primaryContainer,
                              backgroundImage:
                                  imgUrl.isNotEmpty ? NetworkImage(imgUrl) : null,
                              child: imgUrl.isEmpty
                                  ? Text(
                                      name.isNotEmpty
                                          ? name[0].toUpperCase()
                                          : '?',
                                      style: TextStyle(
                                        color: colorScheme.onPrimaryContainer,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    )
                                  : null,
                            ),
                            Positioned(
                              right: -2,
                              top: -2,
                              child: GestureDetector(
                                onTap: () {
                                  HapticFeedback.lightImpact();
                                  setState(
                                      () => _selectedMembers.remove(uid));
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(2),
                                  decoration: const BoxDecoration(
                                    color: Colors.red,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.close,
                                      size: 12, color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        SizedBox(
                          width: 56,
                          child: Text(
                            name,
                            style: const TextStyle(fontSize: 11),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),

          // ── Search bar ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search contacts...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 20),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchResults = [];
                            _isSearching = false;
                          });
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: colorScheme.outlineVariant),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: colorScheme.outlineVariant),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest.withOpacity(0.3),
              ),
              onChanged: _searchUsers,
            ),
          ),

          // ── Members count ───────────────────────────────────────────
          if (_selectedMembers.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${_selectedMembers.length} member${_selectedMembers.length > 1 ? 's' : ''} selected',
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),

          const Divider(height: 1),

          // ── Contact list ────────────────────────────────────────────
          Expanded(
            child: _buildContactList(displayList, colorScheme),
          ),
        ],
      ),
    );
  }

  Widget _buildContactList(
      List<Map<String, dynamic>> displayList, ColorScheme colorScheme) {
    if (_isSearching) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!_connectionsLoaded && _searchController.text.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (displayList.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _searchController.text.isNotEmpty
                  ? Icons.search_off_rounded
                  : Icons.people_outline_rounded,
              size: 56,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 12),
            Text(
              _searchController.text.isNotEmpty
                  ? 'No users found'
                  : 'No connections yet.\nSearch for users to add.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[500], fontSize: 14),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: displayList.length,
      padding: const EdgeInsets.only(bottom: 16),
      itemBuilder: (context, index) {
        final user = displayList[index];
        final uid = user['uid'] as String;
        final name = user['username'] ?? 'Unknown';
        final imgUrl = user['profileImageUrl'] ?? '';
        final isSelected = _selectedMembers.contains(uid);

        return ListTile(
          leading: CircleAvatar(
            radius: 22,
            backgroundColor: colorScheme.primaryContainer,
            backgroundImage:
                imgUrl.isNotEmpty ? NetworkImage(imgUrl) : null,
            child: imgUrl.isEmpty
                ? Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: TextStyle(
                      color: colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                : null,
          ),
          title: Text(
            name,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          subtitle: user['bio'] != null && (user['bio'] as String).isNotEmpty
              ? Text(
                  user['bio'],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[500],
                  ),
                )
              : null,
          trailing: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isSelected
                  ? colorScheme.primary
                  : Colors.transparent,
              border: Border.all(
                color: isSelected
                    ? colorScheme.primary
                    : colorScheme.outlineVariant,
                width: 2,
              ),
            ),
            child: isSelected
                ? const Icon(Icons.check, size: 16, color: Colors.white)
                : null,
          ),
          onTap: () {
            HapticFeedback.lightImpact();
            setState(() {
              if (isSelected) {
                _selectedMembers.remove(uid);
              } else {
                _selectedMembers.add(uid);
              }
            });
          },
        );
      },
    );
  }
}
