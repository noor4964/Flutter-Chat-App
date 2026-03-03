import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:flutter_chat_app/models/post_model.dart';
import 'package:flutter_chat_app/services/post_service.dart';
import 'package:flutter_chat_app/services/cloudinary_service.dart';
import 'package:flutter_chat_app/providers/theme_provider.dart';
import 'package:flutter_chat_app/views/post/image_editor_screen.dart';
import 'package:flutter_chat_app/widgets/glass_scaffold.dart';
import 'package:flutter_chat_app/widgets/glass_container.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class PostCreateScreen extends StatefulWidget {
  final XFile? initialImage;

  const PostCreateScreen({Key? key, this.initialImage}) : super(key: key);

  @override
  State<PostCreateScreen> createState() => _PostCreateScreenState();
}

class _PostCreateScreenState extends State<PostCreateScreen> {
  final PostService _postService = PostService();
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _captionController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  final PageController _pageController = PageController();

  final List<Uint8List> _selectedImageBytes = [];
  int _currentPreviewIndex = 0;
  bool _isLoading = false;
  String? _currentUserProfileImageUrl;
  String? _currentUsername;

  // Privacy
  PostPrivacy _selectedPrivacy = PostPrivacy.public;

  // Upload progress
  bool _isUploading = false;
  double _uploadProgress = 0.0;
  int _uploadedCount = 0;

  // Validation
  bool _captionError = false;

  static const int _maxImages = 10;

  @override
  void initState() {
    super.initState();
    _initializePost();
    _loadUserProfileData();
  }

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
      print('Error loading user profile data: $e');
    }
  }

  Future<void> _initializePost() async {
    if (widget.initialImage != null) {
      final bytes = await widget.initialImage!.readAsBytes();
      if (mounted) {
        final edited = await Navigator.of(context).push<Uint8List>(
          MaterialPageRoute(
            builder: (_) => ImageEditorScreen(imageBytes: bytes),
          ),
        );
        if (edited != null && mounted) {
          setState(() => _selectedImageBytes.add(edited));
        } else if (mounted) {
          setState(() => _selectedImageBytes.add(bytes));
        }
      }
    }
  }

  // ── Image picking ─────────────────────────────────────────────────────

  Future<void> _pickFromGallery() async {
    if (_selectedImageBytes.length >= _maxImages) {
      _showErrorSnackBar('Maximum $_maxImages images allowed');
      return;
    }

    try {
      final List<XFile> pickedFiles = await _picker.pickMultiImage(
        imageQuality: 85,
        maxWidth: 1920,
        maxHeight: 1920,
      );

      if (pickedFiles.isEmpty) return;

      final remaining = _maxImages - _selectedImageBytes.length;
      final filesToProcess = pickedFiles.take(remaining).toList();

      if (pickedFiles.length > remaining) {
        _showErrorSnackBar(
            'Only $remaining more image${remaining == 1 ? '' : 's'} can be added');
      }

      setState(() => _isLoading = true);

      for (final file in filesToProcess) {
        final bytes = await file.readAsBytes();
        if (!mounted) return;

        final edited = await Navigator.of(context).push<Uint8List>(
          MaterialPageRoute(
            builder: (_) => ImageEditorScreen(imageBytes: bytes),
          ),
        );

        if (edited != null && mounted) {
          HapticFeedback.lightImpact();
          setState(() => _selectedImageBytes.add(edited));
        }
      }

      // Jump to last added image
      if (_selectedImageBytes.isNotEmpty && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_pageController.hasClients) {
            _pageController.animateToPage(
              _selectedImageBytes.length - 1,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
            );
          }
        });
      }
    } catch (e) {
      _showErrorSnackBar('Failed to pick images: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickFromCamera() async {
    if (_selectedImageBytes.length >= _maxImages) {
      _showErrorSnackBar('Maximum $_maxImages images allowed');
      return;
    }

    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        maxWidth: 1920,
        maxHeight: 1920,
      );

      if (pickedFile == null) return;

      setState(() => _isLoading = true);

      final bytes = await pickedFile.readAsBytes();
      if (!mounted) return;

      final edited = await Navigator.of(context).push<Uint8List>(
        MaterialPageRoute(
          builder: (_) => ImageEditorScreen(imageBytes: bytes),
        ),
      );

      if (edited != null && mounted) {
        HapticFeedback.lightImpact();
        setState(() => _selectedImageBytes.add(edited));
      }
    } catch (e) {
      _showErrorSnackBar('Failed to capture photo: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _editImageAt(int index) async {
    if (index >= _selectedImageBytes.length) return;

    final edited = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(
        builder: (_) =>
            ImageEditorScreen(imageBytes: _selectedImageBytes[index]),
      ),
    );

    if (edited != null && mounted) {
      setState(() => _selectedImageBytes[index] = edited);
    }
  }

  void _removeImageAt(int index) {
    HapticFeedback.lightImpact();
    setState(() {
      _selectedImageBytes.removeAt(index);
      if (_currentPreviewIndex >= _selectedImageBytes.length &&
          _selectedImageBytes.isNotEmpty) {
        _currentPreviewIndex = _selectedImageBytes.length - 1;
      }
      if (_selectedImageBytes.isEmpty) {
        _currentPreviewIndex = 0;
      }
    });
  }

  // ── Post creation ─────────────────────────────────────────────────────

  Future<void> _createPost() async {
    final String caption = _captionController.text.trim();
    final String location = _locationController.text.trim();

    if (caption.isEmpty) {
      setState(() => _captionError = true);
      _showErrorSnackBar('Please add a caption for your post');
      return;
    }

    if (_selectedImageBytes.isEmpty) {
      _showErrorSnackBar('Please select at least one image for your post');
      return;
    }

    setState(() {
      _isUploading = true;
      _uploadProgress = 0.0;
      _uploadedCount = 0;
    });

    try {
      HapticFeedback.lightImpact();

      // Upload images sequentially for progress tracking
      List<String> imageUrls = [];
      for (int i = 0; i < _selectedImageBytes.length; i++) {
        final url = await CloudinaryService.uploadImageBytes(
          imageBytes: _selectedImageBytes[i],
          preset: CloudinaryService.feedPostPreset,
          filename: 'post_image_$i.jpg',
        );
        imageUrls.add(url);

        if (mounted) {
          setState(() {
            _uploadedCount = i + 1;
            _uploadProgress = (i + 1) / _selectedImageBytes.length;
          });
        }
      }

      // Create post via PostService (supports privacy)
      final postId = await _postService.createPost(
        caption: caption,
        imageUrl: imageUrls.first,
        imageUrls: imageUrls,
        privacy: _selectedPrivacy,
        location: location,
      );

      if (postId != null && mounted) {
        HapticFeedback.mediumImpact();
        Navigator.of(context).pop(true);
      } else if (mounted) {
        _showErrorSnackBar('Failed to create post. Please try again.');
      }
    } catch (e) {
      String errorMessage = 'Failed to create post.';
      if (e.toString().contains('network')) {
        errorMessage = 'Network error. Check your connection.';
      } else if (e.toString().contains('timed out')) {
        errorMessage = 'Upload timed out. Try fewer or smaller images.';
      }
      _showErrorSnackBar(errorMessage);
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _uploadProgress = 0.0;
          _uploadedCount = 0;
        });
      }
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isGlass = themeProvider.isGlassMode;

    return GlassScaffold(
      backgroundColor: isGlass ? null : (isDark ? Colors.black : Colors.white),
      appBar: isGlass
          ? GlassAppBar(
              title: const Text('New Post'),
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 12, top: 8, bottom: 8),
                  child: _buildGradientShareButton(colorScheme),
                ),
              ],
            )
          : _buildAppBar(isDark, colorScheme, theme),
      body: Stack(
        children: [
          _isLoading && _selectedImageBytes.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    // User info bar
                    _buildUserInfoBar(isDark, colorScheme, theme),

                    // Image preview (takes remaining space)
                    Expanded(
                      child: _selectedImageBytes.isNotEmpty
                          ? _buildImagePreview(isDark, colorScheme)
                          : _buildEmptyPlaceholder(isDark, colorScheme),
                    ),

                    // Thumbnail strip
                    if (_selectedImageBytes.isNotEmpty)
                      _buildThumbnailStrip(isDark, colorScheme),

                    // Bottom inputs section
                    _buildBottomSection(isDark, colorScheme, theme),
                  ],
                ),

          // Upload progress overlay
          if (_isUploading) _buildUploadOverlay(colorScheme),
        ],
      ),
    );
  }

  // ── App Bar ───────────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar(
      bool isDark, ColorScheme colorScheme, ThemeData theme) {
    return AppBar(
      backgroundColor: isDark ? Colors.black : Colors.white,
      foregroundColor: isDark ? Colors.white : Colors.black87,
      elevation: 0,
      centerTitle: true,
      title: Text(
        'New Post',
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 12, top: 8, bottom: 8),
          child: _buildGradientShareButton(colorScheme),
        ),
      ],
    );
  }

  Widget _buildGradientShareButton(ColorScheme colorScheme) {
    final bool canShare =
        !_isLoading && !_isUploading && _selectedImageBytes.isNotEmpty;

    final primaryHSL = HSLColor.fromColor(colorScheme.primary);
    final gradientEnd = primaryHSL
        .withHue((primaryHSL.hue + 18) % 360)
        .withLightness((primaryHSL.lightness - 0.06).clamp(0.0, 1.0))
        .toColor();

    return AnimatedOpacity(
      opacity: canShare ? 1.0 : 0.5,
      duration: const Duration(milliseconds: 200),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [colorScheme.primary, gradientEnd],
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: canShare
              ? [
                  BoxShadow(
                    color: colorScheme.primary.withOpacity(0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ]
              : [],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: canShare ? _createPost : null,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: _isUploading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Share',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  // ── User Info Bar ─────────────────────────────────────────────────────

  Widget _buildUserInfoBar(
      bool isDark, ColorScheme colorScheme, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
      child: Row(
        children: [
          // Avatar with border
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: isDark
                    ? Colors.white.withOpacity(0.12)
                    : Colors.black.withOpacity(0.08),
                width: 1,
              ),
            ),
            child: CircleAvatar(
              radius: 18,
              backgroundImage: _currentUserProfileImageUrl != null
                  ? NetworkImage(_currentUserProfileImageUrl!)
                  : null,
              child: _currentUserProfileImageUrl == null
                  ? Text(
                      _currentUsername != null && _currentUsername!.isNotEmpty
                          ? _currentUsername![0]
                          : 'U',
                      style: const TextStyle(fontSize: 14),
                    )
                  : null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _currentUsername ?? 'Your Name',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                _buildPrivacySelector(isDark),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Privacy Selector ──────────────────────────────────────────────────

  Widget _buildPrivacySelector(bool isDark) {
    return PopupMenuButton<PostPrivacy>(
      initialValue: _selectedPrivacy,
      onSelected: (PostPrivacy privacy) {
        HapticFeedback.selectionClick();
        setState(() => _selectedPrivacy = privacy);
      },
      padding: EdgeInsets.zero,
      position: PopupMenuPosition.under,
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: PostPrivacy.public,
          child: Row(
            children: [
              Icon(Icons.public, color: Colors.green, size: 20),
              SizedBox(width: 8),
              Text('Public'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: PostPrivacy.friends,
          child: Row(
            children: [
              Icon(Icons.people, color: Colors.blue, size: 20),
              SizedBox(width: 8),
              Text('Friends Only'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: PostPrivacy.private,
          child: Row(
            children: [
              Icon(Icons.lock, color: Colors.red, size: 20),
              SizedBox(width: 8),
              Text('Private'),
            ],
          ),
        ),
      ],
      child: Chip(
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        avatar: Icon(
          _selectedPrivacy == PostPrivacy.public
              ? Icons.public
              : _selectedPrivacy == PostPrivacy.friends
                  ? Icons.people
                  : Icons.lock,
          size: 16,
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
            fontSize: 12,
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

  // ── Image Preview ─────────────────────────────────────────────────────

  Widget _buildImagePreview(bool isDark, ColorScheme colorScheme) {
    return Stack(
      children: [
        Container(
          width: double.infinity,
          color: isDark ? const Color(0xFF121212) : const Color(0xFFF5F5F7),
          child: PageView.builder(
            controller: _pageController,
            itemCount: _selectedImageBytes.length,
            onPageChanged: (index) {
              setState(() => _currentPreviewIndex = index);
            },
            itemBuilder: (context, index) {
              return GestureDetector(
                onTap: () => _editImageAt(index),
                child: Image.memory(
                  _selectedImageBytes[index],
                  fit: BoxFit.contain,
                ),
              );
            },
          ),
        ),

        // Counter badge (top-right)
        if (_selectedImageBytes.length > 1)
          Positioned(
            top: 12,
            right: 12,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${_currentPreviewIndex + 1}/${_selectedImageBytes.length}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),

        // Edit hint (top-left)
        Positioned(
          top: 12,
          left: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.6),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.edit, color: Colors.white, size: 14),
                SizedBox(width: 4),
                Text(
                  'Tap to edit',
                  style: TextStyle(color: Colors.white, fontSize: 11),
                ),
              ],
            ),
          ),
        ),

        // Dot indicators (bottom center)
        if (_selectedImageBytes.length > 1)
          Positioned(
            bottom: 12,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _selectedImageBytes.length,
                (index) => AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: _currentPreviewIndex == index ? 7 : 5,
                  height: _currentPreviewIndex == index ? 7 : 5,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _currentPreviewIndex == index
                        ? colorScheme.primary
                        : (isDark
                            ? Colors.white.withOpacity(0.3)
                            : Colors.grey[350]),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ── Thumbnail Strip ───────────────────────────────────────────────────

  Widget _buildThumbnailStrip(bool isDark, ColorScheme colorScheme) {
    return Container(
      color: isDark ? Colors.black : Colors.white,
      height: 96,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: isDark
                ? Colors.white.withOpacity(0.10)
                : Colors.black.withOpacity(0.06),
            width: 0.5,
          ),
        ),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: _selectedImageBytes.length +
            (_selectedImageBytes.length < _maxImages ? 1 : 0),
        itemBuilder: (context, index) {
          // "Add more" button at the end
          if (index == _selectedImageBytes.length) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: GestureDetector(
                onTap: _pickFromGallery,
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: colorScheme.primary.withOpacity(0.4),
                      width: 1.5,
                    ),
                    color: colorScheme.primary.withOpacity(0.05),
                  ),
                  child: Icon(
                    Icons.add_photo_alternate_outlined,
                    color: colorScheme.primary,
                    size: 28,
                  ),
                ),
              ),
            );
          }

          final isSelected = index == _currentPreviewIndex;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                _pageController.animateToPage(
                  index,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                );
              },
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected
                            ? colorScheme.primary
                            : (isDark
                                ? Colors.white.withOpacity(0.10)
                                : Colors.black.withOpacity(0.08)),
                        width: isSelected ? 2.5 : 1,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(
                        _selectedImageBytes[index],
                        fit: BoxFit.cover,
                        width: 72,
                        height: 72,
                      ),
                    ),
                  ),
                  // Remove button
                  Positioned(
                    top: 4,
                    right: 4,
                    child: GestureDetector(
                      onTap: () => _removeImageAt(index),
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close,
                            color: Colors.white, size: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Empty Placeholder ─────────────────────────────────────────────────

  Widget _buildEmptyPlaceholder(bool isDark, ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.add_photo_alternate_outlined,
            size: 72,
            color: isDark ? Colors.white24 : Colors.grey[350],
          ),
          const SizedBox(height: 16),
          Text(
            'Add photos to your post',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white54 : Colors.grey[600],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'You can select up to $_maxImages photos',
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.white38 : Colors.grey[400],
            ),
          ),
        ],
      ),
    );
  }

  // ── Bottom Section ────────────────────────────────────────────────────

  Widget _buildBottomSection(
      bool isDark, ColorScheme colorScheme, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? Colors.black : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark
                ? Colors.white.withOpacity(0.10)
                : Colors.black.withOpacity(0.06),
            width: 0.5,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Caption input (borderless)
            TextField(
              controller: _captionController,
              maxLines: 3,
              minLines: 1,
              style: theme.textTheme.bodyMedium,
              onChanged: (_) {
                if (_captionError) setState(() => _captionError = false);
              },
              decoration: InputDecoration(
                hintText: 'Write a caption...',
                hintStyle: TextStyle(
                  color: isDark ? Colors.white38 : Colors.grey[400],
                ),
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                errorText: _captionError ? 'Caption is required' : null,
                errorStyle: TextStyle(fontSize: 12),
              ),
            ),

            const SizedBox(height: 12),

            // Location input (pill-shaped)
            TextField(
              controller: _locationController,
              style: theme.textTheme.bodyMedium,
              decoration: InputDecoration(
                hintText: 'Add location (optional)',
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
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
            ),

            const SizedBox(height: 14),

            // Media picker buttons
            Row(
              children: [
                Expanded(
                  child: _buildMediaButton(
                    icon: Icons.camera_alt,
                    label: 'Camera',
                    onTap: _pickFromCamera,
                    colorScheme: colorScheme,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildMediaButton(
                    icon: Icons.photo_library,
                    label: 'Gallery',
                    onTap: _pickFromGallery,
                    colorScheme: colorScheme,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMediaButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required ColorScheme colorScheme,
  }) {
    final bool disabled = _isLoading || _isUploading;

    final primaryHSL = HSLColor.fromColor(colorScheme.primary);
    final gradientEnd = primaryHSL
        .withHue((primaryHSL.hue + 18) % 360)
        .withLightness((primaryHSL.lightness - 0.06).clamp(0.0, 1.0))
        .toColor();

    return AnimatedOpacity(
      opacity: disabled ? 0.5 : 1.0,
      duration: const Duration(milliseconds: 200),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [colorScheme.primary, gradientEnd],
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: disabled
              ? []
              : [
                  BoxShadow(
                    color: colorScheme.primary.withOpacity(0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: disabled ? null : onTap,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Upload Progress Overlay ───────────────────────────────────────────

  Widget _buildUploadOverlay(ColorScheme colorScheme) {
    return Container(
      color: Colors.black.withOpacity(0.6),
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 40),
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFF1E1E1E)
                : Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 56,
                height: 56,
                child: CircularProgressIndicator(
                  value: _uploadProgress > 0 ? _uploadProgress : null,
                  strokeWidth: 4,
                  color: colorScheme.primary,
                  backgroundColor: colorScheme.primary.withOpacity(0.15),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                _uploadedCount < _selectedImageBytes.length
                    ? 'Uploading image ${_uploadedCount + 1} of ${_selectedImageBytes.length}...'
                    : 'Creating post...',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white
                      : Colors.black87,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                '${(_uploadProgress * 100).toInt()}%',
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white54
                      : Colors.grey[500],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Dispose ───────────────────────────────────────────────────────────

  @override
  void dispose() {
    _captionController.dispose();
    _locationController.dispose();
    _pageController.dispose();
    super.dispose();
  }
}
