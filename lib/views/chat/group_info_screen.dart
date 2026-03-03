import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_chat_app/services/group_chat_service.dart';
import 'package:provider/provider.dart';
import 'package:flutter_chat_app/providers/theme_provider.dart';
import 'package:flutter_chat_app/widgets/glass_scaffold.dart';
import 'package:flutter_chat_app/widgets/glass_container.dart';

/// Screen showing group chat details: name, description, member list,
/// and admin actions (add/remove members, promote admins, edit info, leave group).
class GroupInfoScreen extends StatefulWidget {
  final String chatId;

  const GroupInfoScreen({Key? key, required this.chatId}) : super(key: key);

  @override
  State<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends State<GroupInfoScreen> {
  final _groupChatService = GroupChatService();
  final _currentUid = FirebaseAuth.instance.currentUser?.uid;

  Map<String, dynamic>? _groupData;
  List<Map<String, dynamic>> _members = [];
  bool _isLoading = true;
  bool _isAdmin = false;
  bool _isCreator = false;

  @override
  void initState() {
    super.initState();
    _loadGroupInfo();
  }

  Future<void> _loadGroupInfo() async {
    try {
      final chatDoc = await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .get();

      if (!chatDoc.exists || !mounted) return;

      final data = chatDoc.data()!;
      final admins = List<String>.from(data['admins'] ?? []);
      final members = await _groupChatService.getGroupMembers(widget.chatId);

      if (mounted) {
        setState(() {
          _groupData = data;
          _members = members;
          _isAdmin = admins.contains(_currentUid);
          _isCreator = data['createdBy'] == _currentUid;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('❌ Error loading group info: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _editGroupName() async {
    final controller =
        TextEditingController(text: _groupData?['groupName'] ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Group Name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            hintText: 'Enter new group name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      final success = await _groupChatService.updateGroupInfo(
        widget.chatId,
        groupName: result,
      );
      if (success) _loadGroupInfo();
    }
  }

  Future<void> _editGroupDescription() async {
    final controller =
        TextEditingController(text: _groupData?['groupDescription'] ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Description'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Enter group description',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result != null) {
      final success = await _groupChatService.updateGroupInfo(
        widget.chatId,
        groupDescription: result,
      );
      if (success) _loadGroupInfo();
    }
  }

  Future<void> _removeMember(String memberId, String memberName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Member'),
        content: Text('Remove $memberName from the group?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final success =
          await _groupChatService.removeMember(widget.chatId, memberId);
      if (success) {
        _loadGroupInfo();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$memberName removed from group')),
          );
        }
      }
    }
  }

  Future<void> _promoteToAdmin(String memberId, String memberName) async {
    final success =
        await _groupChatService.promoteToAdmin(widget.chatId, memberId);
    if (success) {
      _loadGroupInfo();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$memberName is now an admin')),
        );
      }
    }
  }

  Future<void> _leaveGroup() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave Group'),
        content: const Text(
            'Are you sure you want to leave this group? You won\'t be able to see new messages.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Leave'),
          ),
        ],
      ),
    );

    if (confirm == true && _currentUid != null) {
      final success =
          await _groupChatService.removeMember(widget.chatId, _currentUid!);
      if (success && mounted) {
        // Pop back to chat list
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    }
  }

  Future<void> _addMembers() async {
    // Navigate to a simple add members dialog
    final searchController = TextEditingController();
    List<Map<String, dynamic>> searchResults = [];

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: SizedBox(
                height: MediaQuery.of(ctx).size.height * 0.6,
                child: Column(
                  children: [
                    // Handle bar
                    Container(
                      margin: const EdgeInsets.only(top: 12, bottom: 8),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'Add Members',
                        style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Search
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        controller: searchController,
                        autofocus: true,
                        decoration: InputDecoration(
                          hintText: 'Search by username...',
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 10),
                        ),
                        onChanged: (query) async {
                          if (query.trim().isEmpty) {
                            setSheetState(() => searchResults = []);
                            return;
                          }
                          final results = await FirebaseFirestore.instance
                              .collection('users')
                              .where('username',
                                  isGreaterThanOrEqualTo: query)
                              .where('username',
                                  isLessThanOrEqualTo: '$query\uf8ff')
                              .limit(15)
                              .get();

                          final currentMembers = List<String>.from(
                              _groupData?['userIds'] ?? []);
                          setSheetState(() {
                            searchResults = results.docs
                                .where((d) =>
                                    d.id != _currentUid &&
                                    !currentMembers.contains(d.id))
                                .map((d) {
                              final data = d.data();
                              data['uid'] = d.id;
                              return data;
                            }).toList();
                          });
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Results
                    Expanded(
                      child: searchResults.isEmpty
                          ? Center(
                              child: Text(
                                searchController.text.isEmpty
                                    ? 'Search for users to add'
                                    : 'No results',
                                style: TextStyle(color: Colors.grey[500]),
                              ),
                            )
                          : ListView.builder(
                              itemCount: searchResults.length,
                              itemBuilder: (ctx, i) {
                                final user = searchResults[i];
                                final uid = user['uid'] as String;
                                final name = user['username'] ?? 'Unknown';
                                final img = user['profileImageUrl'] ?? '';

                                return ListTile(
                                  leading: CircleAvatar(
                                    backgroundImage: img.isNotEmpty
                                        ? NetworkImage(img)
                                        : null,
                                    child: img.isEmpty
                                        ? Text(name.isNotEmpty
                                            ? name[0].toUpperCase()
                                            : '?')
                                        : null,
                                  ),
                                  title: Text(name),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.person_add_rounded),
                                    color:
                                        Theme.of(ctx).colorScheme.primary,
                                    onPressed: () async {
                                      final success =
                                          await _groupChatService.addMember(
                                              widget.chatId, uid);
                                      if (success) {
                                        setSheetState(() {
                                          searchResults.removeAt(i);
                                        });
                                        if (mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                                content: Text(
                                                    '$name added to group')),
                                          );
                                        }
                                      }
                                    },
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    // Reload after sheet closes
    _loadGroupInfo();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isGlass = themeProvider.isGlassMode;

    if (_isLoading) {
      return GlassScaffold(
        appBar: isGlass
            ? GlassAppBar(title: const Text('Group Info'))
            : AppBar(title: const Text('Group Info')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_groupData == null) {
      return GlassScaffold(
        appBar: isGlass
            ? GlassAppBar(title: const Text('Group Info'))
            : AppBar(title: const Text('Group Info')),
        body: const Center(child: Text('Group not found')),
      );
    }

    final groupName = _groupData!['groupName'] ?? 'Group Chat';
    final groupDesc = _groupData!['groupDescription'] ?? '';
    final groupImg = _groupData!['groupImageUrl'] ?? '';
    final memberCount = _members.length;

    return GlassScaffold(
      appBar: isGlass
          ? GlassAppBar(
              elevation: 0,
              title: const Text('Group Info'),
            )
          : AppBar(
              elevation: 0,
              title: const Text('Group Info'),
            ),
      body: ListView(
        children: [
          // ── Group header ────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(vertical: 24),
            alignment: Alignment.center,
            child: Column(
              children: [
                CircleAvatar(
                  radius: 48,
                  backgroundColor: colorScheme.primaryContainer,
                  backgroundImage:
                      groupImg.isNotEmpty ? NetworkImage(groupImg) : null,
                  child: groupImg.isEmpty
                      ? Icon(Icons.group_rounded,
                          size: 40, color: colorScheme.onPrimaryContainer)
                      : null,
                ),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: _isAdmin ? _editGroupName : null,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        groupName,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (_isAdmin) ...[
                        const SizedBox(width: 6),
                        Icon(Icons.edit, size: 16, color: colorScheme.primary),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$memberCount member${memberCount != 1 ? 's' : ''}',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[500],
                  ),
                ),
                if (groupDesc.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: _isAdmin ? _editGroupDescription : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Text(
                        groupDesc,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ),
                  ),
                ] else if (_isAdmin) ...[
                  const SizedBox(height: 4),
                  TextButton(
                    onPressed: _editGroupDescription,
                    child: const Text('Add description'),
                  ),
                ],
              ],
            ),
          ),

          const Divider(height: 1),

          // ── Members section ─────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Text(
                  'Members',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
                if (_isAdmin)
                  TextButton.icon(
                    onPressed: _addMembers,
                    icon: const Icon(Icons.person_add_rounded, size: 18),
                    label: const Text('Add'),
                    style: TextButton.styleFrom(
                      foregroundColor: colorScheme.primary,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
              ],
            ),
          ),

          ..._members.map((member) {
            final uid = member['uid'] as String;
            final name = member['username'] ?? 'Unknown';
            final imgUrl = member['profileImageUrl'] ?? '';
            final isOnline = member['isOnline'] == true;
            final role = member['role'] ?? 'member';
            final isMemberAdmin = role == 'admin';
            final isMe = uid == _currentUid;

            return ListTile(
              leading: Stack(
                children: [
                  CircleAvatar(
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
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                ],
              ),
              title: Row(
                children: [
                  Text(
                    isMe ? '$name (You)' : name,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  if (isMemberAdmin) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        'Admin',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              subtitle: Text(
                isOnline ? 'Online' : 'Offline',
                style: TextStyle(
                  fontSize: 12,
                  color: isOnline ? Colors.green : Colors.grey[500],
                ),
              ),
              trailing: (!isMe && _isAdmin)
                  ? PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, size: 20),
                      onSelected: (value) {
                        switch (value) {
                          case 'promote':
                            _promoteToAdmin(uid, name);
                            break;
                          case 'remove':
                            _removeMember(uid, name);
                            break;
                        }
                      },
                      itemBuilder: (_) => [
                        if (!isMemberAdmin)
                          const PopupMenuItem(
                            value: 'promote',
                            child: ListTile(
                              leading: Icon(Icons.admin_panel_settings),
                              title: Text('Make Admin'),
                              dense: true,
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                        const PopupMenuItem(
                          value: 'remove',
                          child: ListTile(
                            leading:
                                Icon(Icons.person_remove, color: Colors.red),
                            title: Text('Remove',
                                style: TextStyle(color: Colors.red)),
                            dense: true,
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ],
                    )
                  : null,
            );
          }),

          const SizedBox(height: 16),
          const Divider(height: 1),

          // ── Leave group button ──────────────────────────────────────
          ListTile(
            leading: const Icon(Icons.exit_to_app_rounded, color: Colors.red),
            title: const Text(
              'Leave Group',
              style: TextStyle(
                color: Colors.red,
                fontWeight: FontWeight.w500,
              ),
            ),
            onTap: _leaveGroup,
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
