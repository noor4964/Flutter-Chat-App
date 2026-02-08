import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:universal_io/io.dart';
import 'package:provider/provider.dart';

import 'package:flutter_chat_app/models/user_model.dart';
import 'package:flutter_chat_app/providers/auth_provider.dart' as app;
import 'package:flutter_chat_app/services/cloudinary_service.dart';
import 'package:flutter_chat_app/services/platform_helper.dart';
import 'package:flutter_chat_app/utils/user_friendly_error_handler.dart';
import 'package:flutter_chat_app/widgets/common/consistent_ui_components.dart';
import 'package:flutter_chat_app/widgets/common/loading_overlay.dart';
import 'package:flutter_chat_app/widgets/common/navigation_helper.dart';
import 'package:flutter_chat_app/widgets/common/network_image_with_fallback.dart';

/// A modern, section-based Edit Profile screen.
///
/// Features:
/// - Cover photo + profile avatar with image cropping
/// - Section-based form (Personal / Contact)
/// - Real-time validation with debounced username uniqueness check
/// - Unsaved changes guard
/// - Delegates to [AuthProvider] / [AuthService] for persistence
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen>
    with SingleTickerProviderStateMixin {
  // ─── Controllers ────────────────────────────────────────────────────
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _bioController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _locationController = TextEditingController();

  // ─── State ──────────────────────────────────────────────────────────
  UserModel? _originalProfile;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isUploadingAvatar = false;
  bool _isUploadingCover = false;
  bool _hasChanges = false;
  bool _readOnlyEmail = true;
  String? _profileImageUrl;
  String? _coverImageUrl;
  String? _gender;

  // Username uniqueness
  Timer? _usernameDebounce;
  bool _isCheckingUsername = false;
  bool? _isUsernameAvailable;

  // Image picker
  final ImagePicker _imagePicker = ImagePicker();

  // Animation
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );

    // Listen for changes on all controllers
    for (final c in _allControllers) {
      c.addListener(_onFieldChanged);
    }

    _loadProfile();
  }

  List<TextEditingController> get _allControllers => [
        _usernameController,
        _bioController,
        _emailController,
        _phoneController,
        _locationController,
      ];

  @override
  void dispose() {
    _usernameDebounce?.cancel();
    _fadeController.dispose();
    for (final c in _allControllers) {
      c.removeListener(_onFieldChanged);
      c.dispose();
    }
    super.dispose();
  }

  // ─── Data Loading ───────────────────────────────────────────────────

  Future<void> _loadProfile() async {
    try {
      final authProvider =
          Provider.of<app.AuthProvider>(context, listen: false);
      final profile = await authProvider.getUserProfile();

      if (profile != null && mounted) {
        _originalProfile = profile;
        _usernameController.text = profile.username;
        _bioController.text = profile.bio ?? '';
        _emailController.text = profile.email;
        _phoneController.text = profile.phone ?? '';
        _locationController.text = profile.location ?? '';
        _profileImageUrl = profile.profileImageUrl;
        _coverImageUrl = profile.coverImageUrl;
        _gender = profile.gender;

        setState(() {
          _isLoading = false;
          _hasChanges = false;
        });
        _fadeController.forward();
      } else if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        UserFriendlyErrorHandler.showErrorSnackBar(context, e);
      }
    }
  }

  // ─── Change Tracking ────────────────────────────────────────────────

  void _onFieldChanged() {
    if (_originalProfile == null) return;
    final changed = _usernameController.text != _originalProfile!.username ||
        _bioController.text != (_originalProfile!.bio ?? '') ||
        _emailController.text != _originalProfile!.email ||
        _phoneController.text != (_originalProfile!.phone ?? '') ||
        _locationController.text != (_originalProfile!.location ?? '') ||
        _profileImageUrl != _originalProfile!.profileImageUrl ||
        _coverImageUrl != _originalProfile!.coverImageUrl;

    if (changed != _hasChanges) {
      setState(() => _hasChanges = changed);
    }
  }

  // ─── Username Uniqueness ────────────────────────────────────────────

  void _checkUsernameAvailability(String value) {
    _usernameDebounce?.cancel();
    if (value.trim().length < 3) {
      setState(() {
        _isCheckingUsername = false;
        _isUsernameAvailable = null;
      });
      return;
    }
    // Same as original — no need to check
    if (value.trim() == _originalProfile?.username) {
      setState(() {
        _isCheckingUsername = false;
        _isUsernameAvailable = true;
      });
      return;
    }

    setState(() => _isCheckingUsername = true);
    _usernameDebounce = Timer(const Duration(milliseconds: 600), () async {
      final authProvider =
          Provider.of<app.AuthProvider>(context, listen: false);
      final available = await authProvider.isUsernameAvailable(value.trim());
      if (mounted) {
        setState(() {
          _isCheckingUsername = false;
          _isUsernameAvailable = available;
        });
      }
    });
  }

  // ─── Image Picking & Cropping ───────────────────────────────────────

  Future<void> _pickAvatar() async {
    final source = await _showImageSourceSheet();
    if (source == null) return;

    try {
      final picked = await _imagePicker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );
      if (picked == null) return;

      // Crop to square (for avatar)
      final cropped = await _cropImage(
        picked.path,
        aspectRatioPreset: CropAspectRatioPreset.square,
        maxSize: 512,
        isAvatar: true,
      );

      if (cropped != null) {
        setState(() => _isUploadingAvatar = true);
        await _uploadAndSetImage(
          cropped: cropped,
          isAvatar: true,
        );
      }
    } catch (e) {
      if (mounted) {
        UserFriendlyErrorHandler.showErrorSnackBar(context, e);
      }
    } finally {
      if (mounted) setState(() => _isUploadingAvatar = false);
    }
  }

  Future<void> _pickCover() async {
    final source = await _showImageSourceSheet();
    if (source == null) return;

    try {
      final picked = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 900,
        imageQuality: 85,
      );
      if (picked == null) return;

      // Crop to 16:9 (for cover)
      final cropped = await _cropImage(
        picked.path,
        aspectRatioPreset: CropAspectRatioPreset.ratio16x9,
        maxSize: 1200,
        isAvatar: false,
      );

      if (cropped != null) {
        setState(() => _isUploadingCover = true);
        await _uploadAndSetImage(
          cropped: cropped,
          isAvatar: false,
        );
      }
    } catch (e) {
      if (mounted) {
        UserFriendlyErrorHandler.showErrorSnackBar(context, e);
      }
    } finally {
      if (mounted) setState(() => _isUploadingCover = false);
    }
  }

  Future<CroppedFile?> _cropImage(
    String sourcePath, {
    required CropAspectRatioPreset aspectRatioPreset,
    required int maxSize,
    required bool isAvatar,
  }) async {
    final colorScheme = Theme.of(context).colorScheme;

    // image_cropper is not fully supported on web — skip cropping there
    if (PlatformHelper.isWeb) return null;

    return ImageCropper().cropImage(
      sourcePath: sourcePath,
      maxWidth: maxSize,
      maxHeight: maxSize,
      compressFormat: ImageCompressFormat.jpg,
      compressQuality: 85,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle:
              isAvatar ? 'Crop Profile Photo' : 'Crop Cover Photo',
          toolbarColor: colorScheme.surface,
          toolbarWidgetColor: colorScheme.onSurface,
          activeControlsWidgetColor: colorScheme.primary,
          backgroundColor: colorScheme.surface,
          cropGridColor: colorScheme.outline,
          cropFrameColor: colorScheme.primary,
          initAspectRatio: aspectRatioPreset,
          lockAspectRatio: true,
          aspectRatioPresets: [aspectRatioPreset],
        ),
        IOSUiSettings(
          title: isAvatar ? 'Crop Profile Photo' : 'Crop Cover Photo',
          aspectRatioLockEnabled: true,
          resetAspectRatioEnabled: false,
          aspectRatioPresets: [aspectRatioPreset],
        ),
      ],
    );
  }

  Future<void> _uploadAndSetImage({
    required CroppedFile cropped,
    required bool isAvatar,
  }) async {
    try {
      final bytes = await File(cropped.path).readAsBytes();
      final url = await CloudinaryService.uploadImageBytes(
        imageBytes: bytes,
        preset: CloudinaryService.profilePicturePreset,
        filename: isAvatar ? 'profile_avatar.jpg' : 'profile_cover.jpg',
      );

      // Persist to Firestore immediately
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final field = isAvatar ? 'profileImageUrl' : 'coverImageUrl';
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .update({
          field: url,
          'lastUpdated': FieldValue.serverTimestamp(),
        });
      }

      if (mounted) {
        setState(() {
          if (isAvatar) {
            _profileImageUrl = url;
          } else {
            _coverImageUrl = url;
          }
        });
        _onFieldChanged();
        UserFriendlyErrorHandler.showSuccessSnackBar(
          context,
          isAvatar ? 'Profile photo updated' : 'Cover photo updated',
        );
      }
    } catch (e) {
      if (mounted) UserFriendlyErrorHandler.showErrorSnackBar(context, e);
    }
  }

  /// On web, skip camera. On mobile offer both.
  Future<ImageSource?> _showImageSourceSheet() async {
    if (PlatformHelper.isWeb || PlatformHelper.isDesktop) {
      // No camera on web/desktop — go straight to gallery
      return ImageSource.gallery;
    }

    return showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final colorScheme = Theme.of(ctx).colorScheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colorScheme.onSurface.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Choose Photo',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 16),
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: colorScheme.primaryContainer,
                    child: Icon(Icons.photo_library_outlined,
                        color: colorScheme.onPrimaryContainer),
                  ),
                  title: const Text('Gallery'),
                  subtitle: const Text('Choose from your photos'),
                  onTap: () => Navigator.pop(ctx, ImageSource.gallery),
                ),
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: colorScheme.secondaryContainer,
                    child: Icon(Icons.camera_alt_outlined,
                        color: colorScheme.onSecondaryContainer),
                  ),
                  title: const Text('Camera'),
                  subtitle: const Text('Take a new photo'),
                  onTap: () => Navigator.pop(ctx, ImageSource.camera),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ─── Save ───────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    // Block save if username is taken
    if (_isUsernameAvailable == false) {
      UserFriendlyErrorHandler.showWarningSnackBar(
        context,
        'That username is already taken',
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final current = UserModel(
        uid: _originalProfile!.uid,
        username: _usernameController.text.trim(),
        email: _emailController.text.trim(),
        bio: _bioController.text.trim(),
        phone: _phoneController.text.trim(),
        location: _locationController.text.trim(),
        profileImageUrl: _profileImageUrl,
        coverImageUrl: _coverImageUrl,
      );

      final changes = current.changedFields(_originalProfile!);

      if (changes.isEmpty) {
        if (mounted) Navigator.pop(context);
        return;
      }

      final authProvider =
          Provider.of<app.AuthProvider>(context, listen: false);
      final success = await authProvider.updateProfile(changes);

      if (mounted) {
        if (success) {
          UserFriendlyErrorHandler.showSuccessSnackBar(
            context,
            'Profile updated successfully',
          );
          Navigator.pop(context);
        } else {
          UserFriendlyErrorHandler.showErrorSnackBar(
            context,
            authProvider.errorMessage ?? 'Failed to update profile',
          );
        }
      }
    } catch (e) {
      if (mounted) UserFriendlyErrorHandler.showErrorSnackBar(context, e);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ─── Unsaved Changes Guard ──────────────────────────────────────────

  Future<bool> _onWillPop() async {
    if (!_hasChanges) return true;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final colorScheme = Theme.of(ctx).colorScheme;
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded,
                  color: colorScheme.error, size: 24),
              const SizedBox(width: 8),
              const Text('Discard Changes?'),
            ],
          ),
          content: const Text(
            'You have unsaved changes. Are you sure you want to leave without saving?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Keep Editing',
                  style: TextStyle(color: colorScheme.primary)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child:
                  Text('Discard', style: TextStyle(color: colorScheme.error)),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return PopScope(
      canPop: !_hasChanges,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (shouldPop && mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: SimplifiedAppBar(
          title: 'Edit Profile',
          actions: [
            // Save button in app bar
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: _isSaving
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : TextButton(
                        onPressed: _hasChanges ? _save : null,
                        child: Text(
                          'Save',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: _hasChanges
                                ? colorScheme.primary
                                : colorScheme.onSurface.withOpacity(0.35),
                          ),
                        ),
                      ),
              ),
            ),
          ],
        ),
        body: LoadingOverlay(
          isLoading: _isSaving,
          message: 'Updating profile…',
          child: _isLoading ? _buildShimmer(colorScheme) : _buildBody(theme),
        ),
      ),
    );
  }

  // ─── Loading Shimmer ────────────────────────────────────────────────

  Widget _buildShimmer(ColorScheme colorScheme) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: Column(
        children: [
          // Cover shimmer
          Container(
            height: 180,
            color: colorScheme.surfaceContainerHighest,
          ),
          const SizedBox(height: 60),
          // Fields shimmer
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: List.generate(
                5,
                (_) => Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Container(
                    height: 56,
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Main Body ──────────────────────────────────────────────────────

  Widget _buildBody(ThemeData theme) {
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return FadeTransition(
      opacity: _fadeAnimation,
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Cover + Avatar Header ──────────────────────────
              _buildHeaderSection(colorScheme, isDark),

              const SizedBox(height: 24),

              // ── Personal Info Section ──────────────────────────
              _buildSectionCard(
                colorScheme: colorScheme,
                isDark: isDark,
                icon: Icons.person_outline,
                title: 'Personal Information',
                children: [
                  // Username
                  ConsistentTextField(
                    label: 'Username',
                    hint: 'Enter your username',
                    controller: _usernameController,
                    prefixIcon: Icons.alternate_email,
                    suffixIcon: _buildUsernameSuffix(colorScheme),
                    onChanged: (val) => _checkUsernameAvailability(val),
                    validator: _validateUsername,
                  ),
                  const SizedBox(height: 20),

                  // Bio
                  ConsistentTextField(
                    label: 'Bio',
                    hint: 'Tell people about yourself…',
                    controller: _bioController,
                    prefixIcon: Icons.info_outline,
                    maxLines: 3,
                    validator: (val) {
                      if (val != null && val.length > 150) {
                        return 'Bio must be 150 characters or less';
                      }
                      return null;
                    },
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 6, right: 4),
                      child: ValueListenableBuilder<TextEditingValue>(
                        valueListenable: _bioController,
                        builder: (_, value, __) {
                          final len = value.text.length;
                          final over = len > 150;
                          return Text(
                            '$len / 150',
                            style: TextStyle(
                              fontSize: 12,
                              color: over
                                  ? colorScheme.error
                                  : colorScheme.onSurface.withOpacity(0.45),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Gender (read-only chip)
                  if (_gender != null && _gender!.isNotEmpty) ...[
                    Text(
                      'Gender',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Chip(
                      avatar: Icon(
                        _gender == 'Male'
                            ? Icons.male
                            : _gender == 'Female'
                                ? Icons.female
                                : Icons.transgender,
                        size: 18,
                        color: colorScheme.primary,
                      ),
                      label: Text(_gender!),
                      backgroundColor:
                          colorScheme.primaryContainer.withOpacity(0.3),
                      side: BorderSide.none,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ],
                ],
              ),

              const SizedBox(height: 12),

              // ── Contact Info Section ───────────────────────────
              _buildSectionCard(
                colorScheme: colorScheme,
                isDark: isDark,
                icon: Icons.contact_mail_outlined,
                title: 'Contact Information',
                children: [
                  // Email
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: ConsistentTextField(
                          label: 'Email',
                          hint: 'your@email.com',
                          controller: _emailController,
                          prefixIcon: Icons.email_outlined,
                          keyboardType: TextInputType.emailAddress,
                          enabled: !_readOnlyEmail,
                          validator: _validateEmail,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Padding(
                        padding: const EdgeInsets.only(top: 26),
                        child: IconButton(
                          onPressed: () {
                            setState(
                                () => _readOnlyEmail = !_readOnlyEmail);
                          },
                          icon: Icon(
                            _readOnlyEmail
                                ? Icons.lock_outline
                                : Icons.lock_open,
                            size: 20,
                            color: colorScheme.primary,
                          ),
                          tooltip: _readOnlyEmail
                              ? 'Unlock email editing'
                              : 'Lock email',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Phone
                  ConsistentTextField(
                    label: 'Phone',
                    hint: '+1 234 567 8900',
                    controller: _phoneController,
                    prefixIcon: Icons.phone_outlined,
                    keyboardType: TextInputType.phone,
                    validator: _validatePhone,
                  ),
                  const SizedBox(height: 20),

                  // Location
                  ConsistentTextField(
                    label: 'Location',
                    hint: 'City, Country',
                    controller: _locationController,
                    prefixIcon: Icons.location_on_outlined,
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // ── Save Button (bottom) ──────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: ConsistentButton(
                  text: 'Save Changes',
                  icon: Icons.check_circle_outline,
                  isLoading: _isSaving,
                  onPressed: _hasChanges ? _save : null,
                  variant: ButtonVariant.primary,
                ),
              ),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Header: Cover Photo + Avatar ──────────────────────────────────

  Widget _buildHeaderSection(ColorScheme colorScheme, bool isDark) {
    return SizedBox(
      height: 250,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Cover photo
          GestureDetector(
            onTap: _isUploadingCover ? null : _pickCover,
            child: Stack(
              children: [
                SizedBox(
                  width: double.infinity,
                  height: 180,
                  child: _coverImageUrl != null && _coverImageUrl!.isNotEmpty
                      ? NetworkImageWithFallback(
                          imageUrl: _coverImageUrl,
                          width: double.infinity,
                          height: 180,
                          fit: BoxFit.cover,
                        )
                      : Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                colorScheme.primary.withOpacity(0.6),
                                colorScheme.secondary.withOpacity(0.4),
                                colorScheme.tertiary.withOpacity(0.3),
                              ],
                            ),
                          ),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.add_photo_alternate_outlined,
                                  size: 36,
                                  color: Colors.white.withOpacity(0.7),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Add Cover Photo',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.8),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                ),

                // Dark gradient overlay at bottom of cover
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  height: 60,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          (isDark ? Colors.black : Colors.white)
                              .withOpacity(0.5),
                        ],
                      ),
                    ),
                  ),
                ),

                // Cover edit button
                Positioned(
                  top: 12,
                  right: 12,
                  child: _buildCoverEditBadge(colorScheme),
                ),

                // Cover upload indicator
                if (_isUploadingCover)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black45,
                      child: const Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Avatar (overlapping the cover)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: _isUploadingAvatar ? null : _pickAvatar,
                child: Stack(
                  children: [
                    // Avatar circle
                    Hero(
                      tag: 'profile-avatar',
                      child: Container(
                        width: 110,
                        height: 110,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: colorScheme.surface,
                            width: 4,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.15),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ClipOval(
                          child: _profileImageUrl != null &&
                                  _profileImageUrl!.isNotEmpty
                              ? NetworkImageWithFallback(
                                  imageUrl: _profileImageUrl,
                                  width: 110,
                                  height: 110,
                                  fit: BoxFit.cover,
                                )
                              : Container(
                                  color: colorScheme.primaryContainer,
                                  child: Icon(
                                    Icons.person,
                                    size: 50,
                                    color: colorScheme.onPrimaryContainer,
                                  ),
                                ),
                        ),
                      ),
                    ),

                    // Camera overlay
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: colorScheme.primary,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: colorScheme.surface,
                            width: 2.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.15),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: _isUploadingAvatar
                            ? const Padding(
                                padding: EdgeInsets.all(8),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(
                                Icons.camera_alt,
                                color: Colors.white,
                                size: 18,
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCoverEditBadge(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.5),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.edit, size: 14, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            _isUploadingCover ? 'Uploading…' : 'Edit',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Section Card ──────────────────────────────────────────────────

  Widget _buildSectionCard({
    required ColorScheme colorScheme,
    required bool isDark,
    required IconData icon,
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: isDark
            ? colorScheme.surfaceContainerHighest.withOpacity(0.4)
            : colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outlineVariant.withOpacity(0.3),
        ),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 12,
              offset: const Offset(0, 2),
            ),
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: true,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8)
                  .copyWith(top: 0, bottom: 20),
          leading: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withOpacity(0.4),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: colorScheme.primary),
          ),
          title: Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
          children: children,
        ),
      ),
    );
  }

  // ─── Username Suffix Widget ─────────────────────────────────────────

  Widget? _buildUsernameSuffix(ColorScheme colorScheme) {
    if (_isCheckingUsername) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: Padding(
          padding: EdgeInsets.all(2),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_isUsernameAvailable == null) return null;
    if (_isUsernameAvailable!) {
      return Icon(Icons.check_circle, color: Colors.green.shade600, size: 22);
    }
    return Icon(Icons.cancel, color: colorScheme.error, size: 22);
  }

  // ─── Validators ─────────────────────────────────────────────────────

  String? _validateUsername(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Username is required';
    }
    if (value.trim().length < 3) {
      return 'Username must be at least 3 characters';
    }
    if (value.trim().length > 30) {
      return 'Username must be 30 characters or less';
    }
    if (!RegExp(r'^[a-zA-Z0-9._]+$').hasMatch(value.trim())) {
      return 'Only letters, numbers, dots, and underscores';
    }
    if (_isUsernameAvailable == false) {
      return 'This username is already taken';
    }
    return null;
  }

  String? _validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Email is required';
    }
    final emailRegex = RegExp(r'^[\w\-.+]+@([\w-]+\.)+[\w-]{2,}$');
    if (!emailRegex.hasMatch(value.trim())) {
      return 'Enter a valid email address';
    }
    return null;
  }

  String? _validatePhone(String? value) {
    if (value == null || value.trim().isEmpty) return null; // optional
    final phoneRegex = RegExp(r'^\+?[\d\s\-().]{7,20}$');
    if (!phoneRegex.hasMatch(value.trim())) {
      return 'Enter a valid phone number';
    }
    return null;
  }
}
