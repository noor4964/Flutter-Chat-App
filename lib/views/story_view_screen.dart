import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chat_app/models/story_model.dart';
import 'package:flutter_chat_app/services/story_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';

class StoryViewScreen extends StatefulWidget {
  final List<Story> stories;
  final int initialIndex;
  final String userId;

  const StoryViewScreen({
    Key? key,
    required this.stories,
    required this.userId,
    this.initialIndex = 0,
  }) : super(key: key);

  @override
  _StoryViewScreenState createState() => _StoryViewScreenState();
}

class _StoryViewScreenState extends State<StoryViewScreen>
    with SingleTickerProviderStateMixin {
  late PageController _pageController;
  late AnimationController _animationController;
  late int _currentIndex;
  late List<Story> _stories;
  bool _isLoading = false;
  bool _isProcessingReaction = false; // Add rate limiting flag
  final StoryService _storyService = StoryService();
  String? _currentUserId;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _currentUserId = FirebaseAuth.instance.currentUser?.uid;
    _stories = widget.stories;
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: _currentIndex);
    _animationController = AnimationController(vsync: this);

    // Add status listener for animation controller
    _animationController.addStatusListener(_animationStatusListener);

    // Mark current story as viewed when screen loads
    _markAsViewed(_stories[_currentIndex]);

    // Start watching the story
    _loadStory(_currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _animationController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  void _animationStatusListener(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _animationController.stop();
      _animationController.reset();

      // Move to next story
      if (_currentIndex + 1 < _stories.length) {
        setState(() {
          _currentIndex += 1;
        });
        _pageController.animateToPage(
          _currentIndex,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      } else {
        // Exit on last story
        Navigator.of(context).pop();
      }
    }
  }

  void _loadStory(int index) {
    // Reset controller
    _animationController.stop();
    _animationController.reset();

    // Mark the story as viewed
    _markAsViewed(_stories[index]);

    // Define duration based on media type
    Duration duration;

    // Handle different media types
    if (_stories[index].mediaType == 'image') {
      duration = const Duration(seconds: 5); // 5 seconds for images
    } else if (_stories[index].mediaType == 'video') {
      duration = const Duration(seconds: 15); // 15 seconds max for videos
    } else {
      duration = const Duration(seconds: 6); // 6 seconds for text
    }

    _animationController.duration = duration;
    _animationController.forward();
  }

  void _markAsViewed(Story story) {
    if (_currentUserId != null) {
      _storyService.markStoryAsViewed(story.id, context: context);
    }
  }

  void _onTapDown(TapDownDetails details) {
    // Get screen dimensions
    final double screenWidth = MediaQuery.of(context).size.width;
    final double screenHeight = MediaQuery.of(context).size.height;
    
    // Define the button area (bottom right corner where story actions are)
    final double buttonAreaWidth = 100; // Width of button area
    final double buttonAreaHeight = 200; // Height of button area from bottom
    final double buttonAreaRight = screenWidth - 10; // 10px from right edge
    final double buttonAreaBottom = screenHeight - MediaQuery.of(context).padding.bottom - 70;
    
    // Check if tap is in the button area
    final bool isInButtonArea = details.globalPosition.dx > (buttonAreaRight - buttonAreaWidth) &&
                               details.globalPosition.dy > (buttonAreaBottom - buttonAreaHeight);
    
    // If tap is in button area, don't process story navigation
    if (isInButtonArea) {
      print('🚫 Tap in button area - ignoring story navigation');
      return;
    }
    
    // Determine which half of the screen was tapped (excluding button area)
    final bool isLeftSide = details.globalPosition.dx < screenWidth / 2;

    print('🎯 Story tap detected - Left: $isLeftSide, Position: ${details.globalPosition}');

    // Stop the animation temporarily
    _animationController.stop();

    if (isLeftSide) {
      // Go to previous story or user
      if (_currentIndex > 0) {
        setState(() {
          _currentIndex -= 1;
        });
        _pageController.animateToPage(
          _currentIndex,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      } else {
        // If we're at the first story, pop back
        Navigator.of(context).pop();
      }
    } else {
      // Go to next story or user
      if (_currentIndex + 1 < _stories.length) {
        setState(() {
          _currentIndex += 1;
        });
        _pageController.animateToPage(
          _currentIndex,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      } else {
        // If we're at the last story, pop back
        Navigator.of(context).pop();
      }
    }
  }

  void _onHold() {
    _animationController.stop();
  }

  void _onHoldRelease() {
    _animationController.forward();
  }

  Color _parseColor(String colorString) {
    if (colorString.startsWith('#')) {
      return Color(int.parse('FF${colorString.substring(1)}', radix: 16));
    }
    return Colors.purple; // Default color
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTapDown: _onTapDown,
        onLongPressStart: (_) => _onHold(),
        onLongPressEnd: (_) => _onHoldRelease(),
        child: PageView.builder(
          controller: _pageController,
          itemCount: _stories.length,
          onPageChanged: (index) {
            setState(() {
              _currentIndex = index;
            });
            _loadStory(index);
          },
          itemBuilder: (context, index) {
            final Story story = _stories[index];
            return Stack(
              children: [
                // Story content based on media type
                _buildStoryContent(story),

                // Progress indicator at the top
                Positioned(
                  top: MediaQuery.of(context).padding.top + 8,
                  left: 10,
                  right: 10,
                  child: Row(
                    children: List.generate(
                      _stories.length,
                      (i) => Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: LinearProgressIndicator(
                            value: i < _currentIndex
                                ? 1.0
                                : i == _currentIndex
                                    ? _animationController.value
                                    : 0.0,
                            backgroundColor: Colors.white.withOpacity(0.4),
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // User info at the top
                Positioned(
                  top: MediaQuery.of(context).padding.top + 20,
                  left: 10,
                  right: 10,
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: Colors.grey[300],
                        backgroundImage: story.userProfileImage.isNotEmpty
                            ? NetworkImage(story.userProfileImage)
                            : null,
                        child: story.userProfileImage.isEmpty
                            ? Text(
                                story.username.isNotEmpty
                                    ? story.username[0].toUpperCase()
                                    : '?',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              )
                            : null,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              story.username,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Row(
                              children: [
                                Text(
                                  _getTimeAgo(story.timestamp),
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.8),
                                    fontSize: 12,
                                  ),
                                ),
                                // Show location if available
                                if (story.location != null &&
                                    story.location!.isNotEmpty)
                                  Row(
                                    children: [
                                      Text(
                                        ' • ',
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.8),
                                          fontSize: 12,
                                        ),
                                      ),
                                      Icon(
                                        Icons.location_on,
                                        size: 12,
                                        color: Colors.white.withOpacity(0.8),
                                      ),
                                      const SizedBox(width: 2),
                                      Text(
                                        story.location!,
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.8),
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                // Show privacy indicator
                                Row(
                                  children: [
                                    Text(
                                      ' • ',
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.8),
                                        fontSize: 12,
                                      ),
                                    ),
                                    Icon(
                                      _getPrivacyIcon(story.privacy),
                                      size: 12,
                                      color: Colors.white.withOpacity(0.8),
                                    ),
                                    const SizedBox(width: 2),
                                    Text(
                                      _getPrivacyText(story.privacy),
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.8),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      // Close button
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),

                // Caption at the bottom with mentions highlighted
                if (story.caption.isNotEmpty)
                  Positioned(
                    bottom: MediaQuery.of(context).padding.bottom + 20,
                    left: 10,
                    right: 10,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.4),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            story.caption,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                            ),
                          ),

                          // Display mentions if available
                          if (story.mentions.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.people,
                                    size: 14,
                                    color: Colors.white.withOpacity(0.8),
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      'With ${_formatMentions(story.mentions)}',
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.8),
                                        fontSize: 12,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                          // Display music info if available
                          if (story.musicInfo != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.music_note,
                                    size: 14,
                                    color: Colors.white.withOpacity(0.8),
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      '${story.musicInfo!['artist'] ?? 'Unknown'} - ${story.musicInfo!['title'] ?? 'Unknown'}',
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.8),
                                        fontSize: 12,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),

                // Story interactions at the bottom
                Positioned(
                  bottom: MediaQuery.of(context).padding.bottom + 70,
                  right: 10,
                  child: Column(
                    children: [
                      // Debug info
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Text(
                          'DEBUG: Story User: ${story.userId}\nCurrent User: $_currentUserId\nShould show React: ${story.userId != _currentUserId}',
                          style: TextStyle(color: Colors.white, fontSize: 10),
                        ),
                      ),
                      
                      // Show reaction button for ALL stories (temporarily for testing)
                      _buildStoryAction(
                        icon: Icons.favorite_border,
                        label: "React",
                        onTap: () {
                          print('💗 React button tapped!');
                          print('📱 Story ID: ${story.id}');
                          print('👤 Current User: $_currentUserId');
                          print('📊 Story Object: ${story.toString()}');
                          try {
                            _showReactionPicker(story);
                          } catch (e) {
                            print('❌ Error showing reaction picker: $e');
                            // Show a simple snackbar if the picker fails
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Failed to open reaction picker: $e'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      
                      // Only show reply option if not the current user's story
                      if (story.userId != _currentUserId) ...[
                        // Reply button
                        _buildStoryAction(
                          icon: Icons.send_outlined,
                          label: "Reply",
                          onTap: () {
                            _showReplyDialog(story);
                          },
                        ),
                        const SizedBox(height: 16),
                      ],

                      // More options (accessible by all)
                      _buildStoryAction(
                        icon: Icons.more_horiz,
                        label: "More",
                        onTap: () {
                          _showStoryOptions(story);
                        },
                      ),
                    ],
                  ),
                ),

                // Display number of views for owner
                if (story.userId == _currentUserId)
                  Positioned(
                    bottom: MediaQuery.of(context).padding.bottom + 20,
                    left: 10,
                    child: GestureDetector(
                      onTap: () => _showViewersList(story),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.remove_red_eye,
                              color: Colors.white,
                              size: 16,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${story.viewers.length}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                // Display reactions on a story
                if (story.reactions.isNotEmpty)
                  Positioned(
                    bottom: MediaQuery.of(context).padding.bottom + 100,
                    left: 10,
                    child: _buildReactionsDisplay(story),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildStoryAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTapDown: (details) {
        print('🎯 Story action TAP DOWN: $label');
        // Execute immediately on tap down to beat parent gesture detector
        onTap();
      },
      onTap: () {
        print('🎯 Story action TAP: $label (backup)');
        // Backup in case onTapDown doesn't work
      },
      // Prevent parent GestureDetector from receiving this tap
      behavior: HitTestBehavior.opaque,
      child: Container(
        // Add container to ensure proper hit testing
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.all(4),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: Colors.white,
                size: 24,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStoryContent(Story story) {
    // Handle different media types
    if (story.mediaType == 'text') {
      // Text-only story with background color
      return Container(
        decoration: BoxDecoration(
          color: story.background.isNotEmpty
              ? _parseColor(story.background)
              : Colors.purple,
        ),
        child: Center(
          child: Text(
            story.caption,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
    } else if (story.mediaType == 'image') {
      // Image story
      return Container(
        decoration: BoxDecoration(
          color: Colors.black,
        ),
        child: Center(
          child: _isLoading
              ? const CircularProgressIndicator(color: Colors.white)
              : CachedNetworkImage(
                  imageUrl: story.mediaUrl,
                  fit: BoxFit.contain,
                  placeholder: (context, url) => const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                  errorWidget: (context, url, error) => Container(
                    color: Colors.grey[900],
                    child: const Center(
                      child: Icon(
                        Icons.error_outline,
                        color: Colors.white,
                        size: 48,
                      ),
                    ),
                  ),
                ),
        ),
      );
    } else if (story.mediaType == 'video') {
      // For future video implementation
      return Container(
        color: Colors.black,
        child: const Center(
          child: Text(
            "Video support coming soon",
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    } else {
      // Fallback
      return Container(
        color: Colors.black,
        child: const Center(
          child: Text(
            "Unsupported media type",
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    }
  }

  void _showReplyDialog(Story story) {
    final TextEditingController replyController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "Reply to ${story.username}'s Story",
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: replyController,
                autofocus: true,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Type your reply...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () async {
                      final String reply = replyController.text.trim();
                      if (reply.isNotEmpty) {
                        Navigator.pop(context);

                        // Show loading indicator with a key to dismiss it later
                        final ScaffoldFeatureController loadingSnackBar =
                            ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Sending reply...'),
                            duration: Duration(
                                seconds:
                                    30), // Longer duration that will be dismissed manually
                          ),
                        );

                        try {
                          // Actually send the reply using the StoryService
                          await _storyService.replyToStory(
                            story.id,
                            reply,
                            context: context,
                          );

                          // Hide the loading snackbar
                          loadingSnackBar.close();

                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Reply sent to ${story.username}',
                                  style: const TextStyle(color: Colors.white),
                                ),
                                backgroundColor: Colors.green,
                              ),
                            );
                          }
                        } catch (e) {
                          // Hide the loading snackbar
                          loadingSnackBar.close();

                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Failed to send reply: $e'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Send'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showStoryOptions(Story story) {
    final bool isOwnStory = story.userId == _currentUserId;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle for the bottom sheet
              Container(
                height: 4,
                width: 40,
                margin: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              ListTile(
                leading: const Icon(Icons.share_outlined),
                title: const Text('Share story'),
                onTap: () {
                  Navigator.pop(context);
                  // Share story functionality
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Share functionality coming soon')),
                  );
                },
              ),

              if (isOwnStory) ...[
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: const Text('Delete story'),
                  onTap: () async {
                    // Show confirmation dialog
                    final bool confirm = await showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Delete Story'),
                            content: const Text(
                                'Are you sure you want to delete this story?'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text(
                                  'Delete',
                                  style: TextStyle(color: Colors.red),
                                ),
                              ),
                            ],
                          ),
                        ) ??
                        false;

                    if (confirm) {
                      Navigator.pop(context); // Close the bottom sheet

                      try {
                        await _storyService.deleteStory(story.id,
                            context: mounted ? context : null);

                        if (mounted) {
                          Navigator.pop(context); // Close the story viewer

                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Story deleted'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Failed to delete story: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.star_outline),
                  title: Text(story.isHighlighted
                      ? 'Remove from highlights'
                      : 'Add to highlights'),
                  onTap: () async {
                    Navigator.pop(context); // Close the bottom sheet

                    try {
                      await _storyService.highlightStory(
                        story.id,
                        !story.isHighlighted,
                        context: mounted ? context : null,
                      );

                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(story.isHighlighted
                                ? 'Removed from highlights'
                                : 'Added to highlights'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Failed to update highlights: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  },
                ),
              ] else ...[
                ListTile(
                  leading: const Icon(Icons.report_outlined),
                  title: const Text('Report story'),
                  onTap: () {
                    Navigator.pop(context);
                    // Report story functionality
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Report functionality coming soon')),
                    );
                  },
                ),
              ],

              // Add some padding at the bottom
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  String _getTimeAgo(DateTime dateTime) {
    final Duration difference = DateTime.now().difference(dateTime);

    if (difference.inSeconds < 60) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }

  // Enhanced method to show emoji reactions
  void _showReactionPicker(Story story) {
    print('_showReactionPicker called for story: ${story.id}');
    print('Current user ID: $_currentUserId');
    print('Story reactions: ${story.reactions}');
    
    // Simple test version first
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: 300,
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Handle for the bottom sheet
              Container(
                height: 4,
                width: 40,
                margin: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  "React to Story",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),

              // Simple emoji grid
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    childAspectRatio: 1,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                  ),
                  itemCount: 8,
                  itemBuilder: (context, index) {
                    final emojis = ['❤️', '😂', '😮', '😢', '😡', '👍', '🔥', '🎉'];
                    final emoji = emojis[index];
                    
                    return InkWell(
                      onTap: () async {
                        print('Emoji tapped: $emoji');
                        Navigator.pop(context);
                        await _handleReaction(story, emoji);
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey[300]!, width: 1),
                        ),
                        child: Center(
                          child: Text(
                            emoji,
                            style: const TextStyle(fontSize: 24),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Helper method to handle reaction with rate limiting
  Future<void> _handleReaction(Story story, String emoji) async {
    // Check if we're hitting rate limits
    if (_isProcessingReaction) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please wait a moment before adding another reaction'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    _isProcessingReaction = true;

    final ScaffoldFeatureController loadingSnackBar =
        ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Sending reaction...'),
        duration: Duration(seconds: 30),
      ),
    );

    try {
      await _storyService.reactToStory(
        story.id,
        emoji,
        context: context,
      );

      loadingSnackBar.close();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Reaction sent: $emoji'),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      loadingSnackBar.close();

      if (mounted) {
        String errorMessage = 'Failed to send reaction';
        if (e.toString().contains('resource-exhausted')) {
          errorMessage = 'Too many requests. Please wait a moment and try again.';
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      // Add delay before allowing next reaction
      await Future.delayed(const Duration(milliseconds: 500));
      _isProcessingReaction = false;
    }
  }

  // Helper method to remove specific reaction
  Future<void> _removeSpecificReaction(Story story, String emoji) async {
    final ScaffoldFeatureController loadingSnackBar =
        ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Removing reaction...'),
        duration: Duration(seconds: 30),
      ),
    );

    try {
      await _storyService.removeReaction(
        story.id,
        emoji,
        context: context,
      );

      loadingSnackBar.close();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Reaction removed: $emoji'),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      loadingSnackBar.close();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to remove reaction: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Helper method to remove all user reactions
  Future<void> _removeAllReactions(Story story) async {
    final ScaffoldFeatureController loadingSnackBar =
        ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Removing all reactions...'),
        duration: Duration(seconds: 30),
      ),
    );

    try {
      await _storyService.removeAllUserReactions(
        story.id,
        context: context,
      );

      loadingSnackBar.close();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All reactions removed'),
            duration: Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      loadingSnackBar.close();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to remove reactions: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _formatMentions(List<String> mentions) {
    if (mentions.isEmpty) return '';

    if (mentions.length <= 2) {
      return mentions.map((mention) => '@$mention').join(', ');
    } else {
      return '${mentions.take(2).map((mention) => '@$mention').join(', ')} and ${mentions.length - 2} others';
    }
  }

  // Enhanced display reactions on a story with reaction details
  Widget _buildReactionsDisplay(Story story) {
    // If no reactions, return empty container
    if (story.reactions.isEmpty) {
      return const SizedBox.shrink();
    }

    // Group reactions by emoji manually
    Map<String, int> reactionCounts = {};
    for (var reaction in story.reactions) {
      String emoji = reaction['emoji'] as String;
      reactionCounts[emoji] = (reactionCounts[emoji] ?? 0) + 1;
    }

    return GestureDetector(
      onTap: () => _showReactionDetails(story),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.6),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.white.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ...reactionCounts.entries.take(3).map(
              (entry) => Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      entry.key,
                      style: const TextStyle(fontSize: 16),
                    ),
                    if (entry.value > 1)
                      Text(
                        entry.value.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (reactionCounts.length > 3)
              Text(
                "+${reactionCounts.length - 3}",
                style: TextStyle(
                  color: Colors.white.withOpacity(0.8),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            const SizedBox(width: 4),
            Text(
              story.reactions.length.toString(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Show detailed reaction information
  void _showReactionDetails(Story story) {
    // Group reactions by emoji manually
    Map<String, List<String>> reactionsByEmoji = {};
    for (var reaction in story.reactions) {
      String emoji = reaction['emoji'] as String;
      String username = reaction['username'] ?? 'Unknown';
      if (!reactionsByEmoji.containsKey(emoji)) {
        reactionsByEmoji[emoji] = [];
      }
      reactionsByEmoji[emoji]!.add(username);
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Handle for the bottom sheet
              Container(
                height: 4,
                width: 40,
                margin: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  "Story Reactions",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),

              Expanded(
                child: ListView.builder(
                  itemCount: reactionsByEmoji.length,
                  itemBuilder: (context, index) {
                    final emoji = reactionsByEmoji.keys.elementAt(index);
                    final users = reactionsByEmoji[emoji]!;
                    final count = users.length;

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
                        child: Text(
                          emoji,
                          style: const TextStyle(fontSize: 20),
                        ),
                      ),
                      title: Text(
                        '$count ${count == 1 ? 'reaction' : 'reactions'}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        users.take(3).join(', ') + 
                        (users.length > 3 ? ' and ${users.length - 3} others' : ''),
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 14,
                        ),
                      ),
                      onTap: () {
                        // Show all users for this reaction
                        _showUsersForReaction(emoji, users);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Show all users who reacted with a specific emoji
  void _showUsersForReaction(String emoji, List<String> users) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 8),
            Text('Reactions', style: const TextStyle(fontSize: 18)),
          ],
        ),
        content: Container(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: users.length,
            itemBuilder: (context, index) {
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: Theme.of(context).primaryColor,
                  child: Text(
                    users[index][0].toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                title: Text(users[index]),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showViewersList(Story story) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.6,
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          children: [
            // Handle for the bottom sheet
            Container(
              height: 4,
              width: 40,
              margin: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                children: [
                  Text(
                    "Viewers (${story.viewers.length})",
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(),
            // List of viewers
            Expanded(
              child: story.viewers.isEmpty
                  ? const Center(
                      child: Text("No viewers yet"),
                    )
                  : FutureBuilder<List<Map<String, dynamic>>>(
                      future: _fetchViewersData(story.viewers),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }

                        if (snapshot.hasError) {
                          return Center(
                            child: Text(
                                "Error loading viewers: ${snapshot.error}"),
                          );
                        }

                        final viewersData = snapshot.data ?? [];

                        if (viewersData.isEmpty) {
                          return const Center(
                            child: Text("No viewer information available"),
                          );
                        }

                        return ListView.builder(
                          itemCount: viewersData.length,
                          itemBuilder: (context, index) {
                            final userData = viewersData[index];
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundImage: userData['profileImageUrl'] !=
                                            null &&
                                        userData['profileImageUrl'].isNotEmpty
                                    ? NetworkImage(userData['profileImageUrl'])
                                    : null,
                                child: userData['profileImageUrl'] == null ||
                                        userData['profileImageUrl'].isEmpty
                                    ? Text(
                                        userData['username'] != null &&
                                                userData['username'].isNotEmpty
                                            ? userData['username'][0]
                                                .toUpperCase()
                                            : '?',
                                      )
                                    : null,
                              ),
                              title:
                                  Text(userData['username'] ?? 'Unknown User'),
                              subtitle: Text(
                                  'Viewed ${_getTimeAgo(userData['viewedAt'] ?? DateTime.now())}'),
                            );
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // Method to fetch viewer data from Firebase
  Future<List<Map<String, dynamic>>> _fetchViewersData(
      List<String> viewerIds) async {
    List<Map<String, dynamic>> viewersData = [];

    try {
      // Get Firestore instance
      final firestore = FirebaseFirestore.instance;

      // Fetch data for each viewer
      for (String viewerId in viewerIds) {
        try {
          // Get the user document
          final userDoc =
              await firestore.collection('users').doc(viewerId).get();

          if (userDoc.exists) {
            final userData = userDoc.data() as Map<String, dynamic>;
            // Add the user data to our list with the time they viewed the story
            viewersData.add({
              'userId': viewerId,
              'username': userData['username'] ?? 'Unknown',
              'profileImageUrl': userData['profileImageUrl'] ?? '',
              'viewedAt': DateTime
                  .now(), // Ideally, this would be stored in the viewers array
            });
          } else {
            // User not found, add placeholder
            viewersData.add({
              'userId': viewerId,
              'username': 'Unknown User',
              'profileImageUrl': '',
              'viewedAt': DateTime.now(),
            });
          }
        } catch (e) {
          print('❌ Error fetching data for viewer $viewerId: $e');
          // Add error placeholder
          viewersData.add({
            'userId': viewerId,
            'username': 'User',
            'profileImageUrl': '',
            'viewedAt': DateTime.now(),
          });
        }
      }

      // Sort by most recent viewers first (ideally would use actual view timestamps)
      viewersData.sort((a, b) =>
          (b['viewedAt'] as DateTime).compareTo(a['viewedAt'] as DateTime));

      return viewersData;
    } catch (e) {
      print('❌ Error fetching viewers data: $e');
      return [];
    }
  }

  // Get privacy icon based on story privacy
  IconData _getPrivacyIcon(StoryPrivacy privacy) {
    switch (privacy) {
      case StoryPrivacy.public:
        return Icons.public;
      case StoryPrivacy.friends:
        return Icons.group;
      case StoryPrivacy.private:
        return Icons.lock;
      default:
        return Icons.group;
    }
  }

  // Get privacy text based on story privacy
  String _getPrivacyText(StoryPrivacy privacy) {
    switch (privacy) {
      case StoryPrivacy.public:
        return 'Public';
      case StoryPrivacy.friends:
        return 'Friends';
      case StoryPrivacy.private:
        return 'Private';
      default:
        return 'Friends';
    }
  }
}
