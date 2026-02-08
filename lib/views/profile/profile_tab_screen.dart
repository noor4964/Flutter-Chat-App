import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:flutter_chat_app/models/post_model.dart';
import 'package:flutter_chat_app/models/story_model.dart';
import 'package:flutter_chat_app/services/post_service.dart';
import 'package:flutter_chat_app/services/story_service.dart';
import 'package:flutter_chat_app/services/presence_service.dart';
import 'package:flutter_chat_app/views/friends_profile_screen.dart';
import 'package:flutter_chat_app/views/pending_requests_screen.dart';
import 'package:flutter_chat_app/views/profile/edit_profile_screen.dart';
import 'package:flutter_chat_app/views/settings/settings_screen.dart';
import 'package:flutter_chat_app/views/create_story_screen.dart';
import 'package:flutter_chat_app/views/story_view_screen.dart';
import 'package:flutter_chat_app/views/post/post_create_screen.dart';
import 'package:flutter_chat_app/widgets/post_card.dart';

/// Instagram-style profile tab with story highlights, tabbed post views,
/// engagement stats, online indicator, and comprehensive settings.
class ProfileTabScreen extends StatefulWidget {
  final VoidCallback? onProfileUpdated;

  const ProfileTabScreen({Key? key, this.onProfileUpdated}) : super(key: key);

  @override
  State<ProfileTabScreen> createState() => _ProfileTabScreenState();
}

class _ProfileTabScreenState extends State<ProfileTabScreen>
    with TickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final PostService _postService = PostService();
  final StoryService _storyService = StoryService();
  final PresenceService _presenceService = PresenceService();

  late TabController _tabController;

  // Profile data
  String _username = '';
  String _bio = '';
  String _location = '';
  String _profileImageUrl = '';
  DateTime? _memberSince;

  // Stats
  int _postsCount = 0;
  int _friendsCount = 0;
  int _friendRequestCount = 0;
  int _totalLikesReceived = 0;
  int _totalCommentsReceived = 0;

  // Posts
  List<Post> _posts = [];
  bool _isLoading = true;

  // Story highlights
  List<Story> _highlights = [];
  bool _highlightsLoading = true;

  // Active stories (for gradient ring on avatar)
  bool _hasActiveStory = false;

  // Online status
  bool _isOnline = false;
  StreamSubscription<bool>? _onlineStatusSub;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadAll();
    _setupOnlineStatus();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _onlineStatusSub?.cancel();
    super.dispose();
  }

  // ── Data loading ──────────────────────────────────────────────────

  Future<void> _loadAll() async {
    await Future.wait([
      _loadProfile(),
      _loadPosts(),
      _loadFriendsCount(),
      _loadFriendRequestCount(),
      _loadHighlights(),
      _loadActiveStories(),
    ]);
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _refresh() async {
    setState(() => _isLoading = true);
    await _loadAll();
  }

  Future<void> _loadProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      final data = doc.data();
      if (data != null && mounted) {
        setState(() {
          _username = data['username'] ?? '';
          _bio = data['bio'] ?? '';
          _location = data['location'] ?? '';
          _profileImageUrl = data['profileImageUrl'] ?? '';
          // Extract member-since date
          if (data['createdAt'] != null && data['createdAt'] is Timestamp) {
            _memberSince = (data['createdAt'] as Timestamp).toDate();
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading profile: $e');
    }
  }

  Future<void> _loadPosts() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final posts = await _postService
          .getUserPosts(user.uid, includePrivate: true)
          .first;
      if (mounted) {
        setState(() {
          _posts = posts;
          _postsCount = posts.length;
          _totalLikesReceived =
              posts.fold(0, (total, p) => total + p.likes.length);
          _totalCommentsReceived =
              posts.fold(0, (total, p) => total + p.commentsCount);
        });
      }
    } catch (e) {
      debugPrint('Error loading posts: $e');
    }
  }

  Future<void> _loadFriendsCount() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final snapshot = await _firestore
          .collection('connections')
          .where('status', isEqualTo: 'accepted')
          .where(Filter.or(
            Filter('senderId', isEqualTo: user.uid),
            Filter('receiverId', isEqualTo: user.uid),
          ))
          .get();
      if (mounted) setState(() => _friendsCount = snapshot.docs.length);
    } catch (e) {
      debugPrint('Error loading friends count: $e');
    }
  }

  Future<void> _loadFriendRequestCount() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final snapshot = await _firestore
          .collection('connections')
          .where('receiverId', isEqualTo: user.uid)
          .where('status', isEqualTo: 'pending')
          .get();
      if (mounted) setState(() => _friendRequestCount = snapshot.docs.length);
    } catch (e) {
      debugPrint('Error loading friend requests: $e');
    }
  }

  Future<void> _loadHighlights() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final highlights =
          await _storyService.getUserHighlights(user.uid).first;
      if (mounted) {
        setState(() {
          _highlights = highlights;
          _highlightsLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading highlights: $e');
      if (mounted) setState(() => _highlightsLoading = false);
    }
  }

  Future<void> _loadActiveStories() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final stories =
          await _storyService.getUserStories(user.uid).first;
      if (mounted) {
        setState(() => _hasActiveStory = stories.isNotEmpty);
      }
    } catch (e) {
      debugPrint('Error loading active stories: $e');
    }
  }

  void _setupOnlineStatus() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    _onlineStatusSub =
        _presenceService.getUserOnlineStatusStream(user.uid).listen(
      (isOnline) {
        if (mounted) setState(() => _isOnline = isOnline);
      },
      onError: (e) => debugPrint('Error listening to online status: $e'),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: isDark ? Colors.black : Colors.white,
        body: _buildSkeleton(isDark),
      );
    }

    return Scaffold(
      backgroundColor: isDark ? Colors.black : Colors.white,
      body: RefreshIndicator(
        onRefresh: _refresh,
        color: colorScheme.primary,
        child: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) {
            return [
              // ── App bar ────────────────────────────────────
              SliverAppBar(
                floating: true,
                snap: true,
                elevation: 0,
                scrolledUnderElevation: 0,
                backgroundColor: isDark ? Colors.black : Colors.white,
                title: Text(
                  _username.isNotEmpty ? _username : 'Profile',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                centerTitle: false,
                actions: [
                  IconButton(
                    icon: Icon(
                      Icons.add_box_outlined,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                    onPressed: () {
                      Navigator.of(context).push(
                        PageRouteBuilder(
                          opaque: false,
                          pageBuilder: (context, _, __) => PostCreateScreen(),
                        ),
                      ).then((_) => _loadPosts());
                    },
                    splashRadius: 22,
                    tooltip: 'Create post',
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.menu,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                    onPressed: () => _showSettingsSheet(context),
                    splashRadius: 22,
                    tooltip: 'Settings',
                  ),
                ],
              ),

              // ── Profile header ──────────────────────────────
              SliverToBoxAdapter(
                child: _buildProfileHeader(theme, colorScheme, isDark),
              ),

              // ── Story highlights ────────────────────────────
              SliverToBoxAdapter(
                child: _buildHighlightsRow(theme, colorScheme, isDark),
              ),

              // ── Divider ─────────────────────────────────────
              SliverToBoxAdapter(
                child: Divider(
                  height: 1,
                  thickness: 0.5,
                  color: isDark
                      ? Colors.white.withOpacity(0.10)
                      : Colors.black.withOpacity(0.06),
                ),
              ),

              // ── Pinned tab bar ──────────────────────────────
              SliverPersistentHeader(
                pinned: true,
                delegate: _SliverTabBarDelegate(
                  TabBar(
                    controller: _tabController,
                    indicatorColor: isDark ? Colors.white : Colors.black87,
                    indicatorWeight: 1.5,
                    labelColor: isDark ? Colors.white : Colors.black87,
                    unselectedLabelColor:
                        isDark ? Colors.white38 : Colors.grey[400],
                    tabs: const [
                      Tab(icon: Icon(Icons.grid_on, size: 22)),
                      Tab(icon: Icon(Icons.view_list_rounded, size: 22)),
                      Tab(icon: Icon(Icons.lock_outline, size: 22)),
                    ],
                  ),
                  isDark: isDark,
                ),
              ),
            ];
          },
          body: TabBarView(
            controller: _tabController,
            children: [
              _buildAllPostsGrid(theme, colorScheme, isDark),
              _buildPostsListView(theme, colorScheme, isDark),
              _buildPrivatePostsGrid(theme, colorScheme, isDark),
            ],
          ),
        ),
      ),
    );
  }

  // ── Profile header ──────────────────────────────────────────────────

  Widget _buildProfileHeader(
    ThemeData theme,
    ColorScheme colorScheme,
    bool isDark,
  ) {
    final bgColor = isDark ? Colors.black : Colors.white;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar + stats row
          Row(
            children: [
              // Avatar with gradient ring + online dot
              _buildAvatarWithRing(isDark, bgColor, colorScheme),
              const SizedBox(width: 20),
              // Stats
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildTappableStatColumn(
                      _postsCount.toString(),
                      'Posts',
                      theme,
                      isDark,
                      onTap: () {
                        // Scroll to tab 0
                        _tabController.animateTo(0);
                      },
                    ),
                    _buildTappableStatColumn(
                      _friendsCount.toString(),
                      'Friends',
                      theme,
                      isDark,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const FriendsProfileScreen(),
                          ),
                        );
                      },
                    ),
                    _buildTappableStatColumn(
                      _totalLikesReceived.toString(),
                      'Likes',
                      theme,
                      isDark,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Username
          Text(
            _username,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),

          // Bio
          if (_bio.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              _bio,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: isDark ? Colors.white70 : Colors.black87,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],

          // Location + Member since row
          if (_location.isNotEmpty || _memberSince != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                if (_location.isNotEmpty) ...[
                  Icon(
                    Icons.location_on_outlined,
                    size: 14,
                    color: isDark ? Colors.white38 : Colors.grey[500],
                  ),
                  const SizedBox(width: 2),
                  Text(
                    _location,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isDark ? Colors.white38 : Colors.grey[500],
                    ),
                  ),
                ],
                if (_location.isNotEmpty && _memberSince != null) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      '·',
                      style: TextStyle(
                        color: isDark ? Colors.white38 : Colors.grey[500],
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
                if (_memberSince != null) ...[
                  Icon(
                    Icons.calendar_today_outlined,
                    size: 13,
                    color: isDark ? Colors.white38 : Colors.grey[500],
                  ),
                  const SizedBox(width: 3),
                  Text(
                    'Joined ${DateFormat('MMM yyyy').format(_memberSince!)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isDark ? Colors.white38 : Colors.grey[500],
                    ),
                  ),
                ],
              ],
            ),
          ],

          const SizedBox(height: 14),

          // Action buttons row: Edit Profile + Share Profile
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const EditProfileScreen()),
                    ).then((_) {
                      _loadProfile();
                      _loadPosts();
                      widget.onProfileUpdated?.call();
                    });
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: isDark ? Colors.white : Colors.black87,
                    side: BorderSide(
                      color: isDark
                          ? Colors.white.withOpacity(0.15)
                          : Colors.black.withOpacity(0.12),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  child: Text(
                    'Edit Profile',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    // Share profile action
                    final user = FirebaseAuth.instance.currentUser;
                    if (user != null) {
                      Clipboard.setData(
                        ClipboardData(text: 'Check out $_username\'s profile!'),
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Profile link copied to clipboard'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: isDark ? Colors.white : Colors.black87,
                    side: BorderSide(
                      color: isDark
                          ? Colors.white.withOpacity(0.15)
                          : Colors.black.withOpacity(0.12),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  child: Text(
                    'Share Profile',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Avatar with gradient ring + online dot ──────────────────────────

  Widget _buildAvatarWithRing(
      bool isDark, Color bgColor, ColorScheme colorScheme) {
    return GestureDetector(
      onTap: _hasActiveStory
          ? () {
              final user = FirebaseAuth.instance.currentUser;
              if (user != null) {
                _storyService.getUserStories(user.uid).first.then((stories) {
                  if (stories.isNotEmpty && mounted) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => StoryViewScreen(
                          stories: stories,
                          userId: user.uid,
                          initialIndex: 0,
                        ),
                      ),
                    );
                  }
                });
              }
            }
          : null,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: _hasActiveStory
              ? const LinearGradient(
                  colors: [Color(0xFFDE0046), Color(0xFFF7A34B)],
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                )
              : null,
          border: !_hasActiveStory
              ? Border.all(
                  color: isDark
                      ? Colors.white.withOpacity(0.12)
                      : Colors.black.withOpacity(0.08),
                  width: 1,
                )
              : null,
        ),
        child: Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: bgColor,
          ),
          child: Stack(
            children: [
              CircleAvatar(
                radius: 42,
                backgroundColor: isDark
                    ? const Color(0xFF121212)
                    : const Color(0xFFF0F0F3),
                backgroundImage: _profileImageUrl.isNotEmpty
                    ? CachedNetworkImageProvider(_profileImageUrl)
                    : null,
                child: _profileImageUrl.isEmpty
                    ? Icon(
                        Icons.person,
                        size: 42,
                        color: isDark ? Colors.white38 : Colors.grey[400],
                      )
                    : null,
              ),
              // Online green dot
              if (_isOnline)
                Positioned(
                  bottom: 2,
                  right: 2,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: const Color(0xFF4CAF50),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: bgColor,
                        width: 2.5,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Tappable stat column ──────────────────────────────────────────

  Widget _buildTappableStatColumn(
    String count,
    String label,
    ThemeData theme,
    bool isDark, {
    VoidCallback? onTap,
  }) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          count,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: isDark ? Colors.white54 : Colors.grey[600],
          ),
        ),
      ],
    );

    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: content,
      );
    }
    return content;
  }

  // ── Story highlights row ──────────────────────────────────────────

  Widget _buildHighlightsRow(
      ThemeData theme, ColorScheme colorScheme, bool isDark) {
    return SizedBox(
      height: 100,
      child: _highlightsLoading
          ? _buildHighlightsShimmer(isDark)
          : ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: _highlights.length + 1, // +1 for "New" button
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _buildNewHighlightButton(isDark, colorScheme);
                }
                final highlight = _highlights[index - 1];
                return _buildHighlightCircle(highlight, isDark, colorScheme);
              },
            ),
    );
  }

  Widget _buildNewHighlightButton(bool isDark, ColorScheme colorScheme) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CreateStoryScreen()),
        ).then((result) {
          if (result == true) {
            _loadHighlights();
            _loadActiveStories();
          }
        });
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isDark
                      ? Colors.white.withOpacity(0.15)
                      : Colors.black.withOpacity(0.10),
                  width: 1,
                ),
              ),
              child: Icon(
                Icons.add,
                size: 28,
                color: isDark ? Colors.white54 : Colors.grey[600],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'New',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.white54 : Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHighlightCircle(
      Story highlight, bool isDark, ColorScheme colorScheme) {
    final hasImage =
        highlight.mediaUrl.isNotEmpty && highlight.mediaType != 'text';

    return GestureDetector(
      onTap: () {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => StoryViewScreen(
                stories: [highlight],
                userId: highlight.userId,
                initialIndex: 0,
              ),
            ),
          );
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isDark
                      ? Colors.white.withOpacity(0.20)
                      : Colors.grey[300]!,
                  width: 1.5,
                ),
              ),
              child: CircleAvatar(
                radius: 29,
                backgroundColor: isDark
                    ? const Color(0xFF121212)
                    : const Color(0xFFF0F0F3),
                backgroundImage: hasImage
                    ? CachedNetworkImageProvider(highlight.mediaUrl)
                    : null,
                child: !hasImage
                    ? Icon(
                        Icons.text_fields,
                        size: 22,
                        color: isDark ? Colors.white38 : Colors.grey[400],
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: 64,
              child: Text(
                highlight.caption.isNotEmpty
                    ? highlight.caption
                    : 'Highlight',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.white54 : Colors.grey[600],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHighlightsShimmer(bool isDark) {
    final shimmer = isDark ? const Color(0xFF121212) : const Color(0xFFE8E8EA);
    return ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: 5,
      itemBuilder: (_, __) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(radius: 30, backgroundColor: shimmer),
            const SizedBox(height: 4),
            Container(
              width: 40,
              height: 10,
              decoration: BoxDecoration(
                color: shimmer,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Tab 0: All Posts Grid ─────────────────────────────────────────

  Widget _buildAllPostsGrid(
      ThemeData theme, ColorScheme colorScheme, bool isDark) {
    if (_posts.isEmpty) {
      return _buildEmptyPostsState(
        theme,
        isDark,
        icon: Icons.camera_alt_outlined,
        title: 'No posts yet',
        subtitle: 'Your posts will appear here.',
        showCreateButton: true,
      );
    }

    return GridView.builder(
      padding: EdgeInsets.zero,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
      ),
      itemCount: _posts.length,
      itemBuilder: (context, index) {
        final post = _posts[index];
        return _buildEnhancedGridTile(post, isDark, colorScheme);
      },
    );
  }

  Widget _buildEnhancedGridTile(
      Post post, bool isDark, ColorScheme colorScheme) {
    return GestureDetector(
      onTap: () => _showPostDetail(post),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Post content
          if (post.imageUrl.isNotEmpty)
            CachedNetworkImage(
              imageUrl: post.imageUrl,
              fit: BoxFit.cover,
              memCacheWidth: 300,
              placeholder: (_, __) => Container(
                color: isDark
                    ? const Color(0xFF121212)
                    : const Color(0xFFF0F0F3),
              ),
              errorWidget: (_, __, ___) => Container(
                color: isDark
                    ? const Color(0xFF121212)
                    : const Color(0xFFF0F0F3),
                child: Icon(
                  Icons.broken_image_outlined,
                  color: isDark ? Colors.white38 : Colors.grey[400],
                ),
              ),
            )
          else
            Container(
              color: isDark
                  ? const Color(0xFF121212)
                  : const Color(0xFFF0F0F3),
              padding: const EdgeInsets.all(8),
              alignment: Alignment.center,
              child: Text(
                post.caption,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
            ),

          // Like count overlay (bottom-left) for image posts
          if (post.imageUrl.isNotEmpty && post.likes.isNotEmpty)
            Positioned(
              bottom: 4,
              left: 4,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.55),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.favorite, color: Colors.white, size: 12),
                    const SizedBox(width: 3),
                    Text(
                      post.likes.length.toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Privacy badge (top-right) for non-public posts
          if (post.privacy != PostPrivacy.public)
            Positioned(
              top: 4,
              right: 4,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.55),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  post.privacy == PostPrivacy.private
                      ? Icons.lock
                      : Icons.people,
                  color: Colors.white,
                  size: 12,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Tab 1: Posts List View ────────────────────────────────────────

  Widget _buildPostsListView(
      ThemeData theme, ColorScheme colorScheme, bool isDark) {
    if (_posts.isEmpty) {
      return _buildEmptyPostsState(
        theme,
        isDark,
        icon: Icons.camera_alt_outlined,
        title: 'No posts yet',
        subtitle: 'Your posts will appear here.',
        showCreateButton: true,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(top: 4),
      itemCount: _posts.length,
      itemBuilder: (context, index) {
        return PostCard(
          post: _posts[index],
          onPrivacyChanged: () => _loadPosts(),
        );
      },
    );
  }

  // ── Tab 2: Private Posts Grid ─────────────────────────────────────

  Widget _buildPrivatePostsGrid(
      ThemeData theme, ColorScheme colorScheme, bool isDark) {
    final privatePosts = _posts
        .where((p) => p.privacy == PostPrivacy.private)
        .toList();

    return Column(
      children: [
        // Private banner
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF5F5F5),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.lock_outline,
                size: 14,
                color: isDark ? Colors.white38 : Colors.grey[500],
              ),
              const SizedBox(width: 6),
              Text(
                'Only visible to you',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white38 : Colors.grey[500],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),

        // Grid or empty state
        Expanded(
          child: privatePosts.isEmpty
              ? _buildEmptyPostsState(
                  theme,
                  isDark,
                  icon: Icons.lock_outline,
                  title: 'No private posts',
                  subtitle: 'Posts set to private will appear here.',
                  showCreateButton: false,
                )
              : GridView.builder(
                  padding: const EdgeInsets.only(top: 2),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 2,
                    crossAxisSpacing: 2,
                  ),
                  itemCount: privatePosts.length,
                  itemBuilder: (context, index) {
                    return _buildEnhancedGridTile(
                        privatePosts[index], isDark, colorScheme);
                  },
                ),
        ),
      ],
    );
  }

  // ── Empty posts state ─────────────────────────────────────────────

  Widget _buildEmptyPostsState(
    ThemeData theme,
    bool isDark, {
    required IconData icon,
    required String title,
    required String subtitle,
    bool showCreateButton = false,
  }) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 64,
            color: isDark ? Colors.white24 : Colors.grey[300],
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: isDark ? Colors.white54 : Colors.grey[500],
            ),
          ),
          if (showCreateButton) ...[
            const SizedBox(height: 20),
            TextButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  PageRouteBuilder(
                    opaque: false,
                    pageBuilder: (context, _, __) => PostCreateScreen(),
                  ),
                ).then((_) => _loadPosts());
              },
              icon: const Icon(Icons.add_circle_outline, size: 18),
              label: const Text('Create your first post'),
            ),
          ],
        ],
      ),
    );
  }

  // ── Post detail modal ─────────────────────────────────────────────

  void _showPostDetail(Post post) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.92,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) {
          return Container(
            decoration: BoxDecoration(
              color: isDark ? Colors.black : Colors.white,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                // Drag handle
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[400],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // Post card
                Expanded(
                  child: SingleChildScrollView(
                    controller: scrollController,
                    child: PostCard(
                      post: post,
                      onPrivacyChanged: () => _loadPosts(),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── Skeleton ────────────────────────────────────────────────────────

  Widget _buildSkeleton(bool isDark) {
    final shimmer =
        isDark ? const Color(0xFF121212) : const Color(0xFFE8E8EA);

    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title skeleton
              Container(
                width: 120,
                height: 20,
                decoration: BoxDecoration(
                  color: shimmer,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 24),

              // Avatar + 3 stats
              Row(
                children: [
                  CircleAvatar(radius: 42, backgroundColor: shimmer),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: List.generate(
                        3,
                        (_) => Column(
                          children: [
                            Container(
                              width: 32,
                              height: 18,
                              decoration: BoxDecoration(
                                color: shimmer,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              width: 42,
                              height: 12,
                              decoration: BoxDecoration(
                                color: shimmer,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Username + bio skeletons
              Container(
                width: 100,
                height: 14,
                decoration: BoxDecoration(
                  color: shimmer,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                height: 12,
                decoration: BoxDecoration(
                  color: shimmer,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 6),
              Container(
                width: 160,
                height: 12,
                decoration: BoxDecoration(
                  color: shimmer,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 14),

              // Two button skeletons
              Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 36,
                      decoration: BoxDecoration(
                        color: shimmer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      height: 36,
                      decoration: BoxDecoration(
                        color: shimmer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Highlights row shimmer
              SizedBox(
                height: 80,
                child: Row(
                  children: List.generate(
                    5,
                    (_) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Column(
                        children: [
                          CircleAvatar(
                              radius: 30, backgroundColor: shimmer),
                          const SizedBox(height: 4),
                          Container(
                            width: 40,
                            height: 10,
                            decoration: BoxDecoration(
                              color: shimmer,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Tab bar shimmer
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(
                  3,
                  (_) => Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: shimmer,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Grid skeleton
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 2,
                  crossAxisSpacing: 2,
                ),
                itemCount: 9,
                itemBuilder: (_, __) => Container(color: shimmer),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Settings bottom sheet ──────────────────────────────────────────

  void _showSettingsSheet(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF121212) : Colors.white,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[400],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),

                // Edit Profile
                _buildSheetItem(
                  ctx,
                  icon: Icons.person_outline,
                  label: 'Edit Profile',
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const EditProfileScreen()),
                    ).then((_) {
                      _loadProfile();
                      widget.onProfileUpdated?.call();
                    });
                  },
                ),

                // Friend Requests
                _buildSheetItem(
                  ctx,
                  icon: Icons.people_outline,
                  label: 'Friend Requests',
                  badge: _friendRequestCount > 0
                      ? _friendRequestCount.toString()
                      : null,
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => PendingRequestsScreen()),
                    ).then((_) => _loadFriendRequestCount());
                  },
                ),

                // Friends
                _buildSheetItem(
                  ctx,
                  icon: Icons.people,
                  label: 'Friends',
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const FriendsProfileScreen()),
                    );
                  },
                ),

                // Your Activity
                _buildSheetItem(
                  ctx,
                  icon: Icons.insights_outlined,
                  label: 'Your Activity',
                  onTap: () {
                    Navigator.pop(ctx);
                    _showActivitySummary();
                  },
                ),

                // Settings
                _buildSheetItem(
                  ctx,
                  icon: Icons.settings_outlined,
                  label: 'Settings',
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => SettingsScreen()),
                    );
                  },
                ),

                Divider(
                  height: 1,
                  color: isDark
                      ? Colors.white.withOpacity(0.10)
                      : Colors.black.withOpacity(0.08),
                ),

                // Archive
                _buildSheetItem(
                  ctx,
                  icon: Icons.archive_outlined,
                  label: 'Archive',
                  onTap: () {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Archive coming soon'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                ),

                // Share Profile
                _buildSheetItem(
                  ctx,
                  icon: Icons.share_outlined,
                  label: 'Share Profile',
                  onTap: () {
                    Navigator.pop(ctx);
                    Clipboard.setData(
                      ClipboardData(
                          text: 'Check out $_username\'s profile!'),
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Profile link copied to clipboard'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                ),

                Divider(
                  height: 1,
                  color: isDark
                      ? Colors.white.withOpacity(0.10)
                      : Colors.black.withOpacity(0.08),
                ),

                // Log Out
                _buildSheetItem(
                  ctx,
                  icon: Icons.logout,
                  label: 'Log Out',
                  isDestructive: true,
                  onTap: () {
                    Navigator.pop(ctx);
                    _confirmLogout(context);
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSheetItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    String? badge,
    bool isDestructive = false,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final color = isDestructive ? Colors.red : null;

    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w500,
        ),
      ),
      trailing: badge != null
          ? Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                badge,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          : null,
      onTap: onTap,
    );
  }

  // ── Activity summary dialog ────────────────────────────────────────

  void _showActivitySummary() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF121212) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.insights, color: colorScheme.primary, size: 24),
            const SizedBox(width: 10),
            const Text('Your Activity'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Stats grid
            _buildActivityRow(
              Icons.grid_on,
              'Total Posts',
              _postsCount.toString(),
              isDark,
              colorScheme,
            ),
            const SizedBox(height: 12),
            _buildActivityRow(
              Icons.favorite_outline,
              'Likes Received',
              _totalLikesReceived.toString(),
              isDark,
              colorScheme,
            ),
            const SizedBox(height: 12),
            _buildActivityRow(
              Icons.chat_bubble_outline,
              'Comments Received',
              _totalCommentsReceived.toString(),
              isDark,
              colorScheme,
            ),
            const SizedBox(height: 12),
            _buildActivityRow(
              Icons.people_outline,
              'Friends',
              _friendsCount.toString(),
              isDark,
              colorScheme,
            ),
            if (_memberSince != null) ...[
              const SizedBox(height: 12),
              _buildActivityRow(
                Icons.calendar_today_outlined,
                'Member Since',
                DateFormat('MMMM d, yyyy').format(_memberSince!),
                isDark,
                colorScheme,
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildActivityRow(
    IconData icon,
    String label,
    String value,
    bool isDark,
    ColorScheme colorScheme,
  ) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: colorScheme.primary.withOpacity(0.10),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: colorScheme.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.white70 : Colors.black87,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
      ],
    );
  }

  // ── Logout confirmation ────────────────────────────────────────────

  void _confirmLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log Out'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await FirebaseAuth.instance.signOut();
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to log out: $e')),
                  );
                }
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Log Out'),
          ),
        ],
      ),
    );
  }
}

// ── Pinned tab bar delegate ───────────────────────────────────────────

class _SliverTabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  final bool isDark;

  _SliverTabBarDelegate(this.tabBar, {required this.isDark});

  @override
  double get minExtent => tabBar.preferredSize.height;

  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: isDark ? Colors.black : Colors.white,
      child: tabBar,
    );
  }

  @override
  bool shouldRebuild(covariant _SliverTabBarDelegate oldDelegate) {
    return isDark != oldDelegate.isDark;
  }
}
