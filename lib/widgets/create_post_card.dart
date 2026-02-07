import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_chat_app/models/post_model.dart';
import 'package:flutter_chat_app/services/post_service.dart';

class CreatePostCard extends StatefulWidget {
  const CreatePostCard({Key? key}) : super(key: key);

  @override
  _CreatePostCardState createState() => _CreatePostCardState();
}

class _CreatePostCardState extends State<CreatePostCard> {
  final TextEditingController _captionController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final PostService _postService = PostService();

  bool _isExpanded = false;
  bool _isPosting = false;
  File? _selectedImage;
  PostPrivacy _selectedPrivacy = PostPrivacy.public;
  String _userName = '';
  String _userProfileImage = '';

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
  }

  @override
  void dispose() {
    _captionController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _loadUserInfo() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final userDoc =
            await _firestore.collection('users').doc(user.uid).get();
        if (userDoc.exists) {
          final userData = userDoc.data();
          if (userData != null) {
            setState(() {
              _userName = userData['username'] ?? 'User';
              _userProfileImage = userData['profileImageUrl'] ?? '';
            });
          }
        }
      } catch (e) {
        print('Error loading user info: $e');
      }
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      setState(() {
        _selectedImage = File(pickedFile.path);
        _isExpanded = true;
      });
    }
  }

  Future<String?> _uploadImage() async {
    if (_selectedImage == null) return null;

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return null;

      final storageRef = FirebaseStorage.instance
          .ref()
          .child('post_images')
          .child('${user.uid}_${DateTime.now().millisecondsSinceEpoch}.jpg');

      final uploadTask = storageRef.putFile(_selectedImage!);
      final snapshot = await uploadTask;

      return await snapshot.ref.getDownloadURL();
    } catch (e) {
      print('Error uploading image: $e');
      return null;
    }
  }

  Future<void> _createPost() async {
    if (_isPosting) return;

    final caption = _captionController.text.trim();
    final location = _locationController.text.trim();

    if (caption.isEmpty && _selectedImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Add a caption or image to create a post')),
      );
      return;
    }

    setState(() {
      _isPosting = true;
    });

    try {
      String? imageUrl;
      if (_selectedImage != null) {
        imageUrl = await _uploadImage();
      }

      await _postService.createPost(
        caption: caption,
        imageUrl: imageUrl ?? '',
        privacy: _selectedPrivacy,
        location: location,
      );

      // Reset form
      setState(() {
        _captionController.clear();
        _locationController.clear();
        _selectedImage = null;
        _isExpanded = false;
        _selectedPrivacy = PostPrivacy.public;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Post created successfully')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error creating post: ${e.toString()}')),
      );
    } finally {
      setState(() {
        _isPosting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? Colors.black : Colors.white,
          border: Border(
            bottom: BorderSide(
              color: isDark
                  ? Colors.white.withOpacity(0.10)
                  : Colors.black.withOpacity(0.06),
              width: 0.5,
            ),
          ),
        ),
        child: Center(
          child: Text(
            'Sign in to create posts',
            style: theme.textTheme.titleMedium?.copyWith(
              color: isDark ? Colors.white54 : Colors.grey[600],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? Colors.black : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: isDark
                ? Colors.white.withOpacity(0.10)
                : Colors.black.withOpacity(0.06),
            width: 0.5,
          ),
        ),
      ),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 300),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withOpacity(0.1)
                          : Colors.black.withOpacity(0.08),
                      width: 1,
                    ),
                  ),
                  child: CircleAvatar(
                    radius: 18,
                    backgroundImage: _userProfileImage.isNotEmpty
                        ? NetworkImage(_userProfileImage)
                        : null,
                    child: _userProfileImage.isEmpty
                        ? Text(_userName.isNotEmpty ? _userName[0] : 'U')
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _isExpanded = true;
                      });
                    },
                    child: _isExpanded
                        ? const SizedBox.shrink()
                        : Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF121212)
                                  : const Color(0xFFF5F5F7),
                              borderRadius: BorderRadius.circular(28),
                              border: Border.all(
                                color: isDark
                                    ? Colors.white.withOpacity(0.10)
                                    : Colors.black.withOpacity(0.04),
                              ),
                            ),
                            child: Text(
                              "What's on your mind?",
                              style: TextStyle(
                                color:
                                    isDark ? Colors.white54 : Colors.grey[500],
                                fontSize: 15,
                              ),
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(
                    Icons.photo_outlined,
                    color: isDark ? Colors.white70 : Colors.green[600],
                  ),
                  onPressed: _pickImage,
                  splashRadius: 22,
                ),
              ],
            ),
            if (_isExpanded) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _captionController,
                maxLines: 5,
                minLines: 1,
                style: theme.textTheme.bodyMedium,
                decoration: InputDecoration(
                  hintText: "What's on your mind?",
                  hintStyle: TextStyle(
                    color: isDark ? Colors.white38 : Colors.grey[400],
                  ),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              if (_selectedImage != null) ...[
                const SizedBox(height: 12),
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(
                        _selectedImage!,
                        width: double.infinity,
                        height: 200,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedImage = null;
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
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              // Location field — capsule style
              TextField(
                controller: _locationController,
                style: theme.textTheme.bodyMedium,
                decoration: InputDecoration(
                  hintText: "Add location (optional)",
                  hintStyle: TextStyle(
                    color: isDark ? Colors.white38 : Colors.grey[400],
                    fontSize: 14,
                  ),
                  prefixIcon: Icon(Icons.location_on_outlined,
                      color: isDark ? Colors.white38 : Colors.grey[400],
                      size: 20),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(28),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: isDark
                      ? const Color(0xFF121212)
                      : const Color(0xFFF5F5F7),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _buildPrivacySelector(isDark),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _captionController.clear();
                        _locationController.clear();
                        _selectedImage = null;
                        _isExpanded = false;
                        _selectedPrivacy = PostPrivacy.public;
                      });
                    },
                    style: TextButton.styleFrom(
                      foregroundColor:
                          isDark ? Colors.white54 : Colors.grey[600],
                    ),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  // Gradient Post button
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          colorScheme.primary,
                          HSLColor.fromColor(colorScheme.primary)
                              .withHue(
                                  (HSLColor.fromColor(colorScheme.primary)
                                              .hue +
                                          18) %
                                      360)
                              .withLightness(
                                  (HSLColor.fromColor(colorScheme.primary)
                                              .lightness -
                                          0.06)
                                      .clamp(0.0, 1.0))
                              .toColor(),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: colorScheme.primary.withOpacity(0.35),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(24),
                        onTap: _isPosting ? null : _createPost,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 10),
                          child: _isPosting
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  'Post',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPrivacySelector(bool isDark) {
    return PopupMenuButton<PostPrivacy>(
      initialValue: _selectedPrivacy,
      onSelected: (PostPrivacy privacy) {
        setState(() {
          _selectedPrivacy = privacy;
        });
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: PostPrivacy.public,
          child: Row(
            children: [
              Icon(Icons.public, color: Colors.green),
              SizedBox(width: 8),
              Text('Public'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: PostPrivacy.friends,
          child: Row(
            children: [
              Icon(Icons.people, color: Colors.blue),
              SizedBox(width: 8),
              Text('Friends Only'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: PostPrivacy.private,
          child: Row(
            children: [
              Icon(Icons.lock, color: Colors.red),
              SizedBox(width: 8),
              Text('Private'),
            ],
          ),
        ),
      ],
      child: Chip(
        avatar: Icon(
          _selectedPrivacy == PostPrivacy.public
              ? Icons.public
              : _selectedPrivacy == PostPrivacy.friends
                  ? Icons.people
                  : Icons.lock,
          size: 18,
          color: _selectedPrivacy == PostPrivacy.public
              ? Colors.green
              : _selectedPrivacy == PostPrivacy.friends
                  ? Colors.blue
                  : Colors.red,
        ),
        label: Text(
          _selectedPrivacy == PostPrivacy.public
              ? 'Public'
              : _selectedPrivacy == PostPrivacy.friends
                  ? 'Friends'
                  : 'Private',
          style: TextStyle(
            fontSize: 13,
            color: isDark ? Colors.white70 : Colors.black87,
          ),
        ),
        backgroundColor:
            isDark ? const Color(0xFF121212) : const Color(0xFFF0F0F3),
        side: BorderSide(
          color: isDark
              ? Colors.white.withOpacity(0.10)
              : Colors.black.withOpacity(0.06),
        ),
      ),
    );
  }
}
