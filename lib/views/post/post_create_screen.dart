import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_chat_app/services/feed_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class PostCreateScreen extends StatefulWidget {
  final XFile? initialImage;

  const PostCreateScreen({Key? key, this.initialImage}) : super(key: key);

  @override
  _PostCreateScreenState createState() => _PostCreateScreenState();
}

class _PostCreateScreenState extends State<PostCreateScreen> {
  final FeedService _feedService = FeedService();
  final TextEditingController _captionController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();

  XFile? _selectedImage;
  Uint8List? _webImageBytes;
  bool _isLoading = false;
  String? _currentUserProfileImageUrl;
  String? _currentUsername;

  @override
  void initState() {
    super.initState();
    _initializePost();
    _loadUserProfileData();
  }

  // Load user profile data from Firestore
  Future<void> _loadUserProfileData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
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
      }
    } catch (e) {
      print('❌ Error loading user profile data: $e');
    }
  }

  Future<void> _initializePost() async {
    if (widget.initialImage != null) {
      _selectedImage = widget.initialImage;

      if (kIsWeb) {
        _webImageBytes = await widget.initialImage!.readAsBytes();
      }

      setState(() {});
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    setState(() => _isLoading = true);

    try {
      final XFile? pickedFile =
          await _feedService.pickImageFromSource(source, context: context);

      if (pickedFile != null) {
        _selectedImage = pickedFile;

        if (kIsWeb) {
          _webImageBytes = await pickedFile.readAsBytes();
        }

        setState(() {});
      }
    } catch (e) {
      _showErrorSnackBar('Failed to pick image: ${e.toString()}');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _createPost() async {
    // Validate inputs
    final String caption = _captionController.text.trim();
    final String location = _locationController.text.trim();

    if (caption.isEmpty) {
      _showErrorSnackBar('Please add a caption for your post');
      return;
    }

    if (_selectedImage == null) {
      _showErrorSnackBar('Please select an image for your post');
      return;
    }

    setState(() => _isLoading = true);

    try {
      bool success = await _feedService.createPostWithImage(
        pickedImage: _selectedImage,
        caption: caption,
        location: location,
        context: context,
      );

      if (success && mounted) {
        // Give haptic feedback
        HapticFeedback.mediumImpact();

        // Navigate back with success result
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      _showErrorSnackBar('Failed to create post: ${e.toString()}');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    bool isDarkMode = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDarkMode ? colorScheme.background : Colors.grey[100],
      appBar: AppBar(
        title: const Text('Create Post'),
        elevation: 0,
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _createPost,
            child: Text(
              'Share',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : _buildCreatePostContent(isDarkMode, colorScheme),
    );
  }

  Widget _buildCreatePostContent(bool isDarkMode, ColorScheme colorScheme) {
    return Column(
      children: [
        // User info row
        Container(
          color: isDarkMode ? colorScheme.surface : Colors.white,
          padding: const EdgeInsets.all(16),
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

        // Image preview or placeholder
        Expanded(
          child: _selectedImage != null
              ? Container(
                  width: double.infinity,
                  color: Colors.black,
                  child: kIsWeb
                      ? _webImageBytes != null
                          ? Image.memory(
                              _webImageBytes!,
                              fit: BoxFit.contain,
                            )
                          : Center(child: CircularProgressIndicator())
                      : Image.file(
                          File(_selectedImage!.path),
                          fit: BoxFit.contain,
                        ),
                )
              : Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.add_photo_alternate,
                        size: 80,
                        color: colorScheme.primary.withOpacity(0.7),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Add a photo to your post',
                        style: TextStyle(
                          fontSize: 18,
                          color: colorScheme.onBackground.withOpacity(0.7),
                        ),
                      ),
                    ],
                  ),
                ),
        ),

        // Input fields and buttons
        Container(
          color: isDarkMode ? colorScheme.surface : Colors.white,
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Caption input
              TextField(
                controller: _captionController,
                maxLines: 3,
                minLines: 1,
                decoration: InputDecoration(
                  hintText: 'Write a caption...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding: EdgeInsets.all(12),
                ),
              ),

              const SizedBox(height: 16),

              // Location input
              TextField(
                controller: _locationController,
                decoration: InputDecoration(
                  hintText: 'Add location (optional)',
                  prefixIcon: Icon(Icons.location_on_outlined),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Media picker buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildOptionButton(
                    icon: Icons.camera_alt,
                    label: 'Camera',
                    onTap: () => _pickImage(ImageSource.camera),
                    color: Colors.blue,
                  ),
                  _buildOptionButton(
                    icon: Icons.photo_library,
                    label: 'Gallery',
                    onTap: () => _pickImage(ImageSource.gallery),
                    color: Colors.purple,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOptionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required Color color,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _captionController.dispose();
    _locationController.dispose();
    super.dispose();
  }
}
