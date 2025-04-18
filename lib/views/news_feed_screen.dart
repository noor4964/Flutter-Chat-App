import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io';
import 'package:flutter_chat_app/models/post_model.dart';
import 'package:flutter_chat_app/models/story_model.dart';
import 'package:flutter_chat_app/services/feed_service.dart';
import 'package:flutter_chat_app/services/story_service.dart';
import 'package:flutter_chat_app/views/create_story_screen.dart';
import 'package:flutter_chat_app/views/story_view_screen.dart';
import 'package:flutter_chat_app/widgets/post_card.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_chat_app/services/firebase_error_handler.dart';
import 'package:image_picker/image_picker.dart';

class NewsFeedScreen extends StatefulWidget {
  const NewsFeedScreen({Key? key}) : super(key: key);

  @override
  _NewsFeedScreenState createState() => _NewsFeedScreenState();
}

class _NewsFeedScreenState extends State<NewsFeedScreen>
    with AutomaticKeepAliveClientMixin {
  final FeedService _feedService = FeedService();
  final StoryService _storyService = StoryService();
  final FirebaseErrorHandler _errorHandler = FirebaseErrorHandler();
  final ScrollController _scrollController = ScrollController();
  bool _showFab = true;
  String? _currentUserProfileImageUrl;
  String? _currentUsername;
  String? _errorMessage;
  bool _isRecovering = false;

  // Story specific variables
  bool _hasActiveStory = false;
  Stream<List<Story>>? _highlightsStream;
  Map<String, List<Story>> _cachedStoryGroups = {};
  DateTime? _lastStoryRefresh;
  bool _storyLoadingError = false;

  // Create a stream controller to help with error recovery
  Stream<List<Post>>? _postsStream;
  Stream<List<Story>>? _storiesStream;

  // Controller for story view animation
  final PageController _storyPageController = PageController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();

    // Wrap Firebase operations in try-catch to prevent startup crashes
    try {
      // Delay Firebase operations slightly to prevent immediate crashes on tab change
      Future.microtask(() {
        if (mounted) {
          _loadCurrentUserInfo();
          _setupErrorListener();
          _initializePostsStream();
          _initializeStoriesStream();
          _initializeHighlightsStream();
          _checkForActiveUserStory();
        }
      });
    } catch (e) {
      print('❌ Error during NewsFeedScreen initialization: $e');
      // Don't show an error here, let the error boundary handle it
    }

    // Add scroll listener to hide/show FAB
    _scrollController.addListener(() {
      if (_scrollController.position.userScrollDirection ==
          ScrollDirection.reverse) {
        if (_showFab) {
          setState(() {
            _showFab = false;
          });
        }
      }

      if (_scrollController.position.userScrollDirection ==
          ScrollDirection.forward) {
        if (!_showFab) {
          setState(() {
            _showFab = true;
          });
        }
      }
    });
  }

  // New method to initialize highlights stream
  void _initializeHighlightsStream() {
    try {
      // Get current user ID
      final String? currentUserId = FirebaseAuth.instance.currentUser?.uid;
      if (currentUserId != null) {
        _highlightsStream = _storyService.getUserHighlights(
          currentUserId,
          context: context,
        );
      }
    } catch (e) {
      print('❌ Error initializing highlights stream: $e');
    }
  }

  // New method to check if current user has active stories
  Future<void> _checkForActiveUserStory() async {
    try {
      final String? currentUserId = FirebaseAuth.instance.currentUser?.uid;
      if (currentUserId != null) {
        final userStories = await _storyService.getUserStoriesFuture(
          currentUserId,
          context: context,
        );

        if (mounted) {
          setState(() {
            _hasActiveStory = userStories.isNotEmpty;
          });
        }
      }
    } catch (e) {
      print('❌ Error checking for active user story: $e');
    }
  }

  void _initializePostsStream() {
    try {
      _postsStream = _feedService.getPosts(context: context);
    } catch (e) {
      print('❌ Error initializing posts stream: $e');
      _errorMessage = 'Could not load feed. Please try again.';
    }
  }

  void _initializeStoriesStream() {
    try {
      _storiesStream = _storyService.getActiveStories(context: context);

      // Cache story groups for smoother UI
      _storiesStream?.listen((stories) {
        if (mounted) {
          setState(() {
            _cachedStoryGroups = _storyService.groupStoriesByUser(stories);
            _lastStoryRefresh = DateTime.now();
            _storyLoadingError = false;
          });
        }
      }, onError: (e) {
        print('❌ Error in stories stream: $e');
        if (mounted) {
          setState(() {
            _storyLoadingError = true;
          });
        }
      });
    } catch (e) {
      print('❌ Error initializing stories stream: $e');
      setState(() {
        _storyLoadingError = true;
      });
    }
  }

  void _setupErrorListener() {
    try {
      // Listen for error messages from the feed service
      _feedService.onError.listen((message) {
        if (mounted) {
          setState(() {
            _errorMessage = message;
          });

          // Auto-dismiss error after a few seconds
          Future.delayed(const Duration(seconds: 5), () {
            if (mounted) {
              setState(() {
                _errorMessage = null;
              });
            }
          });
        }
      });
    } catch (e) {
      print('❌ Error setting up error listener: $e');
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _feedService.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentUserInfo() async {
    if (!mounted) return;

    final User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        DocumentSnapshot userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        if (userDoc.exists && mounted) {
          Map<String, dynamic> userData =
              userDoc.data() as Map<String, dynamic>;
          setState(() {
            _currentUserProfileImageUrl = userData['profileImageUrl'];
            _currentUsername = userData['username'];
          });
        }
      } catch (e) {
        print('Error loading user info: $e');
        // Try to handle Firebase errors, but don't show dialogs that could block UI
        await _errorHandler.handleFirebaseException(e, context,
            showDialog: false);
      }
    }
  }

  Future<void> _refresh() async {
    if (!mounted) return;

    setState(() {
      _errorMessage = null;
    });

    // Add haptic feedback for better UX
    HapticFeedback.mediumImpact();

    try {
      // Attempt to recover from any potential Firestore issues
      if (_isRecovering) {
        return;
      }

      setState(() {
        _isRecovering = true;
      });

      // Reinitialize the posts and stories streams
      _initializePostsStream();
      _initializeStoriesStream();
      _initializeHighlightsStream();

      // Wait a moment for the recovery to take effect
      await Future.delayed(const Duration(milliseconds: 500));
    } catch (e) {
      print('Error during refresh: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isRecovering = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    bool isDarkMode = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDarkMode ? colorScheme.surface : Colors.grey[100],
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDarkMode
                  ? [colorScheme.surface, colorScheme.surfaceVariant]
                  : [Colors.white, Colors.white.withOpacity(0.85)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                offset: const Offset(0, 2),
                blurRadius: 4,
              ),
            ],
          ),
        ),
        title: ShaderMask(
          shaderCallback: (bounds) => LinearGradient(
            colors: isDarkMode
                ? [colorScheme.primary, colorScheme.primaryContainer]
                : [Colors.deepPurple.shade700, Colors.blue.shade600],
          ).createShader(bounds),
          child: const Text(
            'FlutterGram',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.5,
            ),
          ),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 4.0),
            decoration: BoxDecoration(
              color: isDarkMode
                  ? colorScheme.surfaceVariant.withOpacity(0.5)
                  : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: const Icon(Icons.search),
              tooltip: 'Search content',
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Search coming soon!'),
                  ),
                );
              },
            ),
          ),
          Container(
            margin: const EdgeInsets.only(right: 8.0, left: 4.0),
            decoration: BoxDecoration(
              color: isDarkMode
                  ? colorScheme.surfaceVariant.withOpacity(0.5)
                  : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: const Icon(Icons.send),
              tooltip: 'Direct messages',
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Direct messages coming soon!'),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: _refresh,
            child: CustomScrollView(
              controller: _scrollController,
              slivers: [
                // Stories
                SliverToBoxAdapter(
                  child: _buildStories(),
                ),

                // Divider
                SliverToBoxAdapter(
                  child: Divider(
                    height: 1,
                    thickness: 0.5,
                    color: Colors.grey[300],
                  ),
                ),

                // Posts - Wrap in try-catch to prevent crashes
                _buildPostsStreamBuilder(),
              ],
            ),
          ),
          if (_errorMessage != null)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Material(
                // Make sure it's a material widget for tap handling
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    // Dismiss error on tap
                    setState(() {
                      _errorMessage = null;
                    });
                  },
                  child: Container(
                    color: Colors.red.withOpacity(0.8),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.only(right: 8.0),
                          child: Icon(Icons.close, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: AnimatedSlide(
        duration: const Duration(milliseconds: 300),
        offset: _showFab ? Offset.zero : const Offset(0, 2),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 300),
          opacity: _showFab ? 1.0 : 0.0,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              boxShadow: [
                BoxShadow(
                  color: colorScheme.primary.withOpacity(0.4),
                  blurRadius: 8,
                  spreadRadius: 0,
                  offset: const Offset(0, 2),
                ),
              ],
              gradient: LinearGradient(
                colors: [
                  colorScheme.primary,
                  colorScheme.primary
                      .withBlue((colorScheme.primary.blue + 30).clamp(0, 255)),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: FloatingActionButton(
              onPressed: _showCreatePostDialog,
              elevation: 0,
              backgroundColor: Colors.transparent,
              child: const Icon(Icons.add_photo_alternate, color: Colors.white),
              tooltip: 'Create Post',
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPostsStreamBuilder() {
    // Check if stream is available or not
    if (_postsStream == null) {
      return SliverFillRemaining(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              const Text('Loading feed...'),
              TextButton(
                onPressed: () {
                  _initializePostsStream();
                  setState(() {});
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    // Wrap the stream builder in a try-catch to prevent crashes
    try {
      return StreamBuilder<List<Post>>(
        stream: _postsStream,
        builder: (context, snapshot) {
          // Handle loading state
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData &&
              !snapshot.hasError) {
            return const SliverFillRemaining(
              child: Center(
                child: CircularProgressIndicator(),
              ),
            );
          }

          // Handle error state
          if (snapshot.hasError) {
            print('❌ Error in posts stream: ${snapshot.error}');
            return SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 48,
                      color: Colors.red,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Something went wrong',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32.0),
                      child: Text(
                        'We encountered a database error. Please try refreshing or restart the app.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.grey[600],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton(
                          onPressed: _refresh,
                          child: const Text('Refresh'),
                        ),
                        const SizedBox(width: 16),
                        OutlinedButton(
                          onPressed: () {
                            // Just refresh the stream without complex recovery
                            _initializePostsStream();
                            setState(() {});
                          },
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }

          // Handle empty data
          List<Post> posts = snapshot.data ?? [];
          if (posts.isEmpty) {
            return SliverFillRemaining(
              child: Center(
                child: Container(
                  margin: const EdgeInsets.all(24),
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Theme.of(context).colorScheme.surfaceVariant
                        : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        spreadRadius: 0,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .primaryContainer
                              .withOpacity(0.3),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.photo_library_outlined,
                          size: 64,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'No posts yet',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.white
                              : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Be the first to share something amazing with your friends!',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.grey[400]
                              : Colors.grey[600],
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: _showCreatePostDialog,
                        icon: const Icon(Icons.add_photo_alternate),
                        label: const Text('Create Post'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          // Normal display of posts
          return SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                if (index >= posts.length) {
                  return null;
                }

                return Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: PostCard(post: posts[index]),
                );
              },
              childCount: posts.length,
            ),
          );
        },
      );
    } catch (e) {
      print('❌ Error building posts stream widget: $e');
      return SliverFillRemaining(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.orange),
              const SizedBox(height: 16),
              const Text('An unexpected error occurred'),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: _refresh,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
  }

  Widget _buildStories() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    bool isDarkMode = theme.brightness == Brightness.dark;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: isDarkMode ? colorScheme.surfaceVariant : Colors.white,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 8, bottom: 8),
              child: Row(
                children: [
                  Text(
                    'Stories',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () {
                      // View all stories
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('View all stories coming soon!')),
                      );
                    },
                    icon: Icon(Icons.arrow_forward, size: 16),
                    label: Text('View All'),
                    style: TextButton.styleFrom(
                      foregroundColor: colorScheme.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 90,
              child: _buildStoriesStreamBuilder(colorScheme, isDarkMode),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStoriesStreamBuilder(ColorScheme colorScheme, bool isDarkMode) {
    if (_storiesStream == null) {
      // If stream is not initialized, show loading
      return ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: 3, // Show fewer items in loading state
        itemBuilder: (context, index) {
          if (index == 0) {
            // Your story item (always shown)
            return GestureDetector(
              onTap: _navigateToCreateStory,
              child: _buildYourStoryItem(colorScheme, isDarkMode),
            );
          } else {
            // Loading placeholders
            return Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: Colors.grey[300],
                    child: SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          colorScheme.primary.withOpacity(0.7),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    height: 12,
                    width: 40,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ],
              ),
            );
          }
        },
      );
    }

    return StreamBuilder<List<Story>>(
      stream: _storiesStream,
      builder: (context, snapshot) {
        // Get current user ID to find own stories
        final String? currentUserId = FirebaseAuth.instance.currentUser?.uid;
        List<Story> stories = snapshot.data ?? [];

        // Group stories by user
        Map<String, List<Story>> groupedStories =
            _storyService.groupStoriesByUser(stories);

        // Extract unique users who have stories
        List<String> userIds = groupedStories.keys.toList();

        // Total count is your story + all other users with stories
        int totalCount = userIds.length + 1;

        return ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          itemCount: totalCount,
          itemBuilder: (context, index) {
            if (index == 0) {
              // Your story is always first
              return GestureDetector(
                onTap: _navigateToCreateStory,
                child: _buildYourStoryItem(colorScheme, isDarkMode),
              );
            } else {
              // Other users' stories
              final int userIndex = index - 1;
              if (userIndex < userIds.length) {
                final String userId = userIds[userIndex];
                final List<Story> userStories = groupedStories[userId] ?? [];

                if (userStories.isEmpty) {
                  return const SizedBox.shrink();
                }

                // Get first story to display user info
                final Story firstStory = userStories.first;
                final bool hasUnseenStory = currentUserId != null &&
                    !userStories.any((story) => story.isViewed(currentUserId));

                return GestureDetector(
                  onTap: () {
                    // Navigate to story view using the new helper method
                    _navigateToStoryView(userStories, userId, 0);
                  },
                  child: Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Column(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            gradient: hasUnseenStory
                                ? LinearGradient(
                                    colors: const [
                                      Colors.purple,
                                      Colors.orange,
                                      Colors.pink,
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  )
                                : null,
                            borderRadius: BorderRadius.circular(30),
                          ),
                          padding: hasUnseenStory
                              ? const EdgeInsets.all(2)
                              : EdgeInsets.zero,
                          child: Container(
                            decoration: BoxDecoration(
                              border: hasUnseenStory
                                  ? Border.all(
                                      color: isDarkMode
                                          ? colorScheme.surface
                                          : Colors.white,
                                      width: 2,
                                    )
                                  : Border.all(
                                      color: Colors.grey[300]!,
                                      width: 1,
                                    ),
                              borderRadius: BorderRadius.circular(30),
                            ),
                            child: CircleAvatar(
                              radius: 28,
                              backgroundColor: colorScheme.primaryContainer,
                              backgroundImage: firstStory
                                      .userProfileImage.isNotEmpty
                                  ? NetworkImage(firstStory.userProfileImage)
                                  : null,
                              child: firstStory.userProfileImage.isEmpty
                                  ? Text(
                                      firstStory.username.isNotEmpty
                                          ? firstStory.username[0].toUpperCase()
                                          : '?',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: colorScheme.primary,
                                      ),
                                    )
                                  : null,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _truncateUsername(firstStory.username),
                          style: const TextStyle(
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              } else {
                return const SizedBox.shrink();
              }
            }
          },
        );
      },
    );
  }

  Widget _buildYourStoryItem(ColorScheme colorScheme, bool isDarkMode) {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Column(
        children: [
          Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Colors.grey[300]!,
                    width: 1,
                  ),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: CircleAvatar(
                  radius: 30,
                  backgroundColor: colorScheme.primaryContainer,
                  backgroundImage: _currentUserProfileImageUrl != null
                      ? NetworkImage(_currentUserProfileImageUrl!)
                      : null,
                  child: _currentUserProfileImageUrl == null
                      ? Icon(
                          Icons.person,
                          color: colorScheme.primary,
                        )
                      : null,
                ),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isDarkMode ? colorScheme.surface : Colors.white,
                      width: 2,
                    ),
                  ),
                  child: const Icon(
                    Icons.add,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Your Story',
            style: TextStyle(
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  // Helper to truncate long usernames
  String _truncateUsername(String username) {
    return username.length > 9 ? '${username.substring(0, 8)}...' : username;
  }

  void _navigateToStoryView(
      List<Story> stories, String userId, int initialIndex) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => StoryViewScreen(
          stories: stories,
          userId: userId,
          initialIndex: initialIndex,
        ),
      ),
    ).then((_) {
      // Refresh the stories list when returning
      if (mounted) {
        setState(() {
          _initializeStoriesStream();
        });
      }
    });
  }

  void _showCreatePostDialog() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    bool isDarkMode = theme.brightness == Brightness.dark;

    // Variables to store post data
    String caption = '';
    String location = '';
    XFile? pickedImage;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDarkMode ? colorScheme.surface : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
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

                  // Header with gradient text
                  ShaderMask(
                    shaderCallback: (bounds) => LinearGradient(
                      colors: [
                        colorScheme.primary,
                        colorScheme.primary.withBlue(
                            (colorScheme.primary.blue + 40).clamp(0, 255)),
                      ],
                    ).createShader(bounds),
                    child: const Text(
                      'Create New Post',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // User info row
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: colorScheme.primaryContainer,
                          backgroundImage: _currentUserProfileImageUrl != null
                              ? NetworkImage(_currentUserProfileImageUrl!)
                              : null,
                          child: _currentUserProfileImageUrl == null
                              ? Icon(Icons.person, color: colorScheme.primary)
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          _currentUsername ?? 'Your Name',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Image preview if an image is picked
                  if (pickedImage != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Stack(
                        children: [
                          Container(
                            height: 200,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              color: Colors.grey[200],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: kIsWeb
                                  ? FutureBuilder<Uint8List>(
                                      future: pickedImage?.readAsBytes(),
                                      builder: (context, snapshot) {
                                        if (snapshot.connectionState ==
                                                ConnectionState.done &&
                                            snapshot.hasData) {
                                          return Image.memory(
                                            snapshot.data!,
                                            fit: BoxFit.cover,
                                          );
                                        }
                                        return const Center(
                                          child: CircularProgressIndicator(),
                                        );
                                      },
                                    )
                                  : Image.file(
                                      File(pickedImage!.path),
                                      fit: BoxFit.cover,
                                    ),
                            ),
                          ),
                          Positioned(
                            top: 8,
                            right: 8,
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  pickedImage = null;
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.6),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.close,
                                  color: Colors.white,
                                  size: 16,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 16),

                  // Caption input field
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: 'Write a caption...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: Colors.grey[300]!,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: colorScheme.primary,
                            width: 2,
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      maxLines: 3,
                      onChanged: (value) {
                        caption = value;
                      },
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Location input field
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: 'Add location (optional)',
                        prefixIcon: Icon(Icons.location_on_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: Colors.grey[300]!,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: colorScheme.primary,
                            width: 2,
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      onChanged: (value) {
                        location = value;
                      },
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Media picker options - only show if no image is picked yet
                  if (pickedImage == null)
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: isDarkMode
                            ? colorScheme.surfaceVariant
                            : Colors.grey[100],
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          _buildPickerOption(
                            icon: Icons.photo_library,
                            title: 'Photo Gallery',
                            subtitle: 'Share photos from your gallery',
                            onTap: () async {
                              // Pick image from gallery
                              XFile? image = await _feedService
                                  .pickImageFromSource(ImageSource.gallery,
                                      context: context);
                              if (image != null) {
                                setState(() {
                                  pickedImage = image;
                                });
                              }
                            },
                            iconColor: Colors.purple,
                          ),
                          Divider(
                              height: 1, thickness: 1, color: Colors.grey[200]),
                          _buildPickerOption(
                            icon: Icons.camera_alt,
                            title: 'Camera',
                            subtitle: 'Take a new photo',
                            onTap: () async {
                              // Open camera
                              XFile? image = await _feedService
                                  .pickImageFromSource(ImageSource.camera,
                                      context: context);
                              if (image != null) {
                                setState(() {
                                  pickedImage = image;
                                });
                              }
                            },
                            iconColor: Colors.red,
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 24),

                  // Post button
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: pickedImage == null || caption.trim().isEmpty
                            ? null // Disable button if no image or caption
                            : () async {
                                // Close the bottom sheet
                                Navigator.pop(context);

                                // Show loading indicator
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Creating your post...'),
                                    duration: Duration(seconds: 5),
                                  ),
                                );

                                // Create post with the image and caption
                                bool success =
                                    await _feedService.createPostWithImage(
                                  pickedImage: pickedImage,
                                  caption: caption,
                                  location: location,
                                  context: context,
                                );

                                if (success && mounted) {
                                  // Success message is already shown by the feed service
                                  // Refresh feed to show the new post
                                  _refresh();
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                          backgroundColor: colorScheme.primary,
                          disabledBackgroundColor: Colors.grey[400],
                        ),
                        child: const Text(
                          'Post',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPickerOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required Color iconColor,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }

  void _navigateToCreateStory() async {
    // Provide haptic feedback for better user experience
    HapticFeedback.mediumImpact();

    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const CreateStoryScreen(),
      ),
    );

    // If a story was created, refresh the stories list
    if (result == true && mounted) {
      setState(() {
        _initializeStoriesStream();
      });
    }
  }
}
