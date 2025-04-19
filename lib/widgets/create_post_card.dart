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
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return Card(
        margin: const EdgeInsets.all(12),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Center(
            child: Text(
              'Sign in to create posts',
              style: theme.textTheme.titleMedium,
            ),
          ),
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.all(12),
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 300),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundImage: _userProfileImage.isNotEmpty
                        ? NetworkImage(_userProfileImage)
                        : null,
                    child: _userProfileImage.isEmpty
                        ? Text(_userName.isNotEmpty ? _userName[0] : 'U')
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _isExpanded = true;
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Text(
                          _isExpanded ? '' : "What's on your mind?",
                          style: TextStyle(color: Colors.grey[700]),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.photo),
                    color: Colors.green,
                    onPressed: _pickImage,
                  ),
                ],
              ),
              if (_isExpanded) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _captionController,
                  maxLines: 5,
                  minLines: 1,
                  decoration: const InputDecoration(
                    hintText: "What's on your mind?",
                    border: InputBorder.none,
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
                TextField(
                  controller: _locationController,
                  decoration: const InputDecoration(
                    hintText: "Add location (optional)",
                    prefixIcon: Icon(Icons.location_on),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _buildPrivacySelector(),
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
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _isPosting ? null : _createPost,
                      child: _isPosting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Text('Post'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPrivacySelector() {
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
        ),
        backgroundColor: Colors.grey[200],
      ),
    );
  }
}
