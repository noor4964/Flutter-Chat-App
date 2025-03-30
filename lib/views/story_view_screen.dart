import 'dart:async';
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
    // Determine which half of the screen was tapped
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isLeftSide = details.globalPosition.dx < screenWidth / 2;

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
                            Text(
                              _getTimeAgo(story.timestamp),
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.8),
                                fontSize: 12,
                              ),
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

                // Caption at the bottom
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
                      child: Text(
                        story.caption,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),

                // Story interactions at the bottom
                Positioned(
                  bottom: MediaQuery.of(context).padding.bottom + 70,
                  right: 10,
                  child: Column(
                    children: [
                      // Only show reply option if not the current user's story
                      if (story.userId != _currentUserId)
                        _buildStoryAction(
                          icon: Icons.send_outlined,
                          label: "Reply",
                          onTap: () {
                            // Reply to story functionality
                            _showReplyDialog(story);
                          },
                        ),
                      const SizedBox(height: 16),
                      // More actions (like, share, etc.)
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
      onTap: onTap,
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
                    onPressed: () {
                      final String reply = replyController.text.trim();
                      if (reply.isNotEmpty) {
                        // Here we would implement the reply functionality
                        // For now, just show a snackbar
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Reply sent to ${story.username}',
                              style: const TextStyle(color: Colors.white),
                            ),
                            backgroundColor: Colors.green,
                          ),
                        );
                        Navigator.pop(context);
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
}
