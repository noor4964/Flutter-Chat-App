/// **DEPRECATED** — Use [EditProfileScreen] (`edit_profile_screen.dart`) instead.
/// This file is retained for reference only and will be removed in a future release.
///
/// All navigation has been redirected to [EditProfileScreen].
@Deprecated('Use EditProfileScreen from edit_profile_screen.dart instead')
// ignore_for_file: deprecated_member_use_from_same_package

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io' if (dart.library.html) 'dart:html' as html;
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:universal_io/io.dart';
import 'package:path/path.dart' as path;
import 'package:http_parser/http_parser.dart';
import 'dart:typed_data';
import 'dart:async';
import '../../utils/user_friendly_error_handler.dart';
import '../../widgets/common/loading_overlay.dart';
import '../../widgets/common/navigation_helper.dart';
import '../../widgets/common/network_image_with_fallback.dart';

class ProfileScreen extends StatefulWidget {
  @override
  _ProfileScreenState createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final User? user = FirebaseAuth.instance.currentUser;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  dynamic _imageFile; // Can be File or XFile depending on platform
  Uint8List? _webImage; // For web platform
  late TextEditingController _usernameController;
  late TextEditingController _emailController;
  late TextEditingController _bioController;
  late TextEditingController _phoneController;
  late TextEditingController _locationController;
  bool _isLoading = false;
  bool _isSubmitting = false;
  String? _profilePictureUrl;
  final _formKey = GlobalKey<FormState>();
  bool _readOnlyEmail = true;

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController();
    _emailController = TextEditingController();
    _bioController = TextEditingController();
    _phoneController = TextEditingController();
    _locationController = TextEditingController();
    _loadUserProfile();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _bioController.dispose();
    _phoneController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _loadUserProfile() async {
    setState(() {
      _isLoading = true;
    });

    if (user != null) {
      try {
        DocumentSnapshot userDoc =
            await _firestore.collection('users').doc(user!.uid).get();
        var userData = userDoc.data() as Map<String, dynamic>?;
        if (mounted) {
          setState(() {
            _usernameController.text = userData?['username'] ?? '';
            _emailController.text = userData?['email'] ?? user?.email ?? '';
            _bioController.text = userData?['bio'] ?? '';
            _phoneController.text = userData?['phone'] ?? '';
            _locationController.text = userData?['location'] ?? '';
            _profilePictureUrl = userData?['profileImageUrl'] ?? null;
            _isLoading = false;
          });
        }
      } catch (e) {
        print('Error loading profile: $e');
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
          UserFriendlyErrorHandler.showErrorSnackBar(
            context,
            e,
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: () => _loadUserProfile(),
            ),
          );
        }
      }
    }
  }

  Future<void> _updateProfile() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    if (user != null) {
      try {
        // First update Firestore
        await _firestore.collection('users').doc(user!.uid).update({
          'username': _usernameController.text,
          'email': _emailController.text,
          'bio': _bioController.text,
          'phone': _phoneController.text,
          'location': _locationController.text,
          'lastUpdated': FieldValue.serverTimestamp(),
        });

        // Then update Firebase Auth user's display name
        await user!.updateDisplayName(_usernameController.text);

        if (mounted) {
          setState(() {
            _isSubmitting = false;
          });

          UserFriendlyErrorHandler.showSuccessSnackBar(
            context,
            'Profile updated successfully',
          );
        }
      } catch (e) {
        print('Error updating profile: $e');
        if (mounted) {
          setState(() {
            _isSubmitting = false;
          });

          UserFriendlyErrorHandler.showErrorSnackBar(
            context,
            e,
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: () => _updateProfile(),
            ),
          );
        }
      }
    }
  }

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();

    // Show a dialog to choose between camera and gallery
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Wrap(
            children: <Widget>[
              ListTile(
                leading: Icon(Icons.photo_library),
                title: Text('Photo Library'),
                onTap: () async {
                  Navigator.of(context).pop();
                  final XFile? pickedFile =
                      await picker.pickImage(source: ImageSource.gallery);
                  _processPickedImage(pickedFile);
                },
              ),
              ListTile(
                leading: Icon(Icons.photo_camera),
                title: Text('Camera'),
                onTap: () async {
                  Navigator.of(context).pop();
                  final XFile? pickedFile =
                      await picker.pickImage(source: ImageSource.camera);
                  _processPickedImage(pickedFile);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _processPickedImage(XFile? pickedFile) async {
    if (pickedFile != null) {
      if (kIsWeb) {
        // Handle web platform
        var bytes = await pickedFile.readAsBytes();
        setState(() {
          _webImage = bytes;
          _imageFile = pickedFile;
        });
      } else {
        // Handle mobile platforms
        setState(() {
          _imageFile = File(pickedFile.path);
        });
      }
      // Upload the image to Cloudinary and update the user's profile picture URL
      await _uploadProfilePicture();
    }
  }

  // Rest of the image upload functionality remains the same
  Future<void> _uploadProfilePicture() async {
    if (_imageFile != null && user != null) {
      try {
        setState(() {
          _isLoading = true;
        });

        // Show a loading indicator
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Uploading profile picture...')),
        );

        // Upload the image to Cloudinary
        String uploadUrl =
            'https://api.cloudinary.com/v1_1/daekv7k8q/image/upload';
        String apiKey = '354918315997393';
        String apiSecret = 'J9RlhhbDDovsyNpOGz67futNGj0';
        String timestamp = DateTime.now().millisecondsSinceEpoch.toString();

        var request = http.MultipartRequest('POST', Uri.parse(uploadUrl));
        request.fields['api_key'] = apiKey;
        request.fields['timestamp'] = timestamp;
        request.fields['signature'] =
            _generateSignature(apiSecret, timestamp, 'profile_picture');
        request.fields['upload_preset'] = 'profile_picture';

        // Handle file upload differently based on platform
        if (kIsWeb) {
          // For web
          final fileName = path.basename((_imageFile as XFile).name);
          final bytes = _webImage;

          if (bytes != null) {
            request.files.add(http.MultipartFile.fromBytes(
              'file',
              bytes,
              filename: fileName,
              contentType:
                  MediaType('image', 'jpeg'), // Adjust based on your needs
            ));
          }
        } else {
          // For mobile
          request.files.add(await http.MultipartFile.fromPath(
              'file', (_imageFile as File).path));
        }

        var response = await request.send();
        var responseData = await http.Response.fromStream(response);

        if (response.statusCode == 200) {
          var responseDataJson = json.decode(responseData.body);
          String downloadUrl = responseDataJson['secure_url'];

          // Update the user's profile picture URL in Firestore
          await _firestore.collection('users').doc(user!.uid).update({
            'profileImageUrl': downloadUrl,
          });

          if (mounted) {
            setState(() {
              _profilePictureUrl = downloadUrl;
              _isLoading = false;
            });

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Profile picture updated successfully'),
                backgroundColor: Colors.green,
              ),
            );
          }
        } else {
          print('Failed to upload profile picture: ${responseData.body}');
          if (mounted) {
            setState(() {
              _isLoading = false;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Failed to upload profile picture'),
                backgroundColor: Colors.red,
              ),
            );
          }
          throw Exception('Failed to upload profile picture');
        }
      } catch (e) {
        print('Exception: $e');
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to upload profile picture: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  String _generateSignature(
      String apiSecret, String timestamp, String uploadPreset) {
    var bytes = utf8
        .encode('timestamp=$timestamp&upload_preset=$uploadPreset$apiSecret');
    var digest = sha1.convert(bytes);
    return digest.toString();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: SimplifiedAppBar(
        title: 'My Profile',
        actions: [
          IconButton(
            icon: Icon(Icons.help_outline),
            onPressed: () {
              NavigationHelper.showConfirmDialog(
                context,
                title: 'Profile Help',
                content:
                    'This screen allows you to update your profile information.'
                    '\n\n• Tap on your profile picture to change it'
                    '\n• Fill in your details and tap Save to update'
                    '\n• Your email address cannot be changed',
                confirmText: 'Got it',
                onConfirm: () {},
              );
            },
          ),
        ],
      ),
      body: LoadingOverlay(
        isLoading: _isLoading,
        message: 'Loading profile...',
        child: _isLoading
            ? Container() // Empty container when loading
            : SingleChildScrollView(
                child: Column(
                  children: [
                    // Profile Header Section
                    Container(
                      padding: EdgeInsets.only(bottom: 24),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer.withOpacity(0.3),
                        borderRadius: BorderRadius.only(
                          bottomLeft: Radius.circular(30),
                          bottomRight: Radius.circular(30),
                        ),
                      ),
                      child: Column(
                        children: [
                          SizedBox(height: 20),
                          Stack(
                            alignment: Alignment.bottomRight,
                            children: [
                              GestureDetector(
                                onTap: _pickImage,
                                child: Container(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: colorScheme.primary,
                                      width: 4,
                                    ),
                                  ),
                                  child: _buildProfileImage(),
                                ),
                              ),
                              Container(
                                padding: EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: colorScheme.primary,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Theme.of(context)
                                        .scaffoldBackgroundColor,
                                    width: 3,
                                  ),
                                ),
                                child: IconButton(
                                  icon: Icon(Icons.camera_alt,
                                      color: Colors.white, size: 20),
                                  onPressed: _pickImage,
                                  constraints: BoxConstraints(
                                    minWidth: 36,
                                    minHeight: 36,
                                  ),
                                  padding: EdgeInsets.zero,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 16),
                          Text(
                            _usernameController.text.isEmpty
                                ? (user?.displayName ?? 'Update your profile')
                                : _usernameController.text,
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            user?.email ?? '',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Form Section
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Personal Information',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.primary,
                              ),
                            ),
                            SizedBox(height: 16),

                            // Username field
                            TextFormField(
                              controller: _usernameController,
                              decoration: InputDecoration(
                                labelText: 'Username',
                                prefixIcon: Icon(Icons.person),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                filled: true,
                                fillColor: Colors.grey.withOpacity(0.1),
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Please enter a username';
                                }
                                return null;
                              },
                            ),
                            SizedBox(height: 16),

                            // Email field (read-only)
                            TextFormField(
                              controller: _emailController,
                              readOnly: _readOnlyEmail,
                              decoration: InputDecoration(
                                labelText: 'Email',
                                prefixIcon: Icon(Icons.email),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                filled: true,
                                fillColor: Colors.grey.withOpacity(0.1),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _readOnlyEmail
                                        ? Icons.lock
                                        : Icons.lock_open,
                                    color: _readOnlyEmail
                                        ? Colors.grey
                                        : colorScheme.primary,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _readOnlyEmail = !_readOnlyEmail;
                                    });
                                    if (_readOnlyEmail) {
                                      // Reset to original email if locked again
                                      _emailController.text = user?.email ?? '';
                                    }
                                  },
                                ),
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Please enter an email';
                                }
                                // Basic email validation
                                if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$')
                                    .hasMatch(value)) {
                                  return 'Please enter a valid email';
                                }
                                return null;
                              },
                            ),
                            SizedBox(height: 24),

                            Text(
                              'Additional Information',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.primary,
                              ),
                            ),
                            SizedBox(height: 16),

                            // Bio field
                            TextFormField(
                              controller: _bioController,
                              decoration: InputDecoration(
                                labelText: 'Bio',
                                prefixIcon: Icon(Icons.description),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                filled: true,
                                fillColor: Colors.grey.withOpacity(0.1),
                              ),
                              maxLines: 3,
                            ),
                            SizedBox(height: 16),

                            // Phone field
                            TextFormField(
                              controller: _phoneController,
                              decoration: InputDecoration(
                                labelText: 'Phone',
                                prefixIcon: Icon(Icons.phone),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                filled: true,
                                fillColor: Colors.grey.withOpacity(0.1),
                              ),
                              keyboardType: TextInputType.phone,
                            ),
                            SizedBox(height: 16),

                            // Location field
                            TextFormField(
                              controller: _locationController,
                              decoration: InputDecoration(
                                labelText: 'Location',
                                prefixIcon: Icon(Icons.location_on),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                filled: true,
                                fillColor: Colors.grey.withOpacity(0.1),
                              ),
                            ),
                            SizedBox(height: 32),

                            // Save button
                            SizedBox(
                              width: double.infinity,
                              height: 50,
                              child: ElevatedButton(
                                onPressed:
                                    _isSubmitting ? null : _updateProfile,
                                style: ElevatedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  backgroundColor: colorScheme.primary,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                child: _isSubmitting
                                    ? CircularProgressIndicator(
                                        color: Colors.white)
                                    : Text(
                                        'Save Changes',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                              ),
                            ),
                            SizedBox(height: 16),

                            // Sign out button
                            SizedBox(
                              width: double.infinity,
                              height: 50,
                              child: OutlinedButton(
                                onPressed: () async {
                                  // Show confirmation dialog
                                  bool? confirm = await showDialog<bool>(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      title: Text('Sign Out'),
                                      content: Text(
                                          'Are you sure you want to sign out?'),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.of(context).pop(false),
                                          child: Text('Cancel'),
                                        ),
                                        ElevatedButton(
                                          onPressed: () =>
                                              Navigator.of(context).pop(true),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.red,
                                          ),
                                          child: Text('Sign Out'),
                                        ),
                                      ],
                                    ),
                                  );

                                  if (confirm == true) {
                                    await FirebaseAuth.instance.signOut();
                                    Navigator.pushReplacementNamed(
                                        context, '/login');
                                  }
                                },
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(color: Colors.red),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                child: Text(
                                  'Sign Out',
                                  style: TextStyle(
                                    color: Colors.red,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  // Helper method to get the correct image provider based on platform
  ImageProvider? _getProfileImage() {
    if (_imageFile != null) {
      if (kIsWeb && _webImage != null) {
        return MemoryImage(_webImage!);
      } else if (!kIsWeb) {
        return FileImage(_imageFile as File);
      }
    } else if (_profilePictureUrl != null) {
      return NetworkImage(_profilePictureUrl!);
    }
    return null;
  }

  // Helper method to safely build profile image with error handling
  Widget _buildProfileImage() {
    if (_imageFile != null) {
      if (kIsWeb && _webImage != null) {
        return CircleAvatar(
          radius: 64,
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          backgroundImage: MemoryImage(_webImage!),
        );
      } else if (!kIsWeb) {
        return CircleAvatar(
          radius: 64,
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          backgroundImage: FileImage(_imageFile as File),
        );
      }
    } else if (_profilePictureUrl != null) {
      return NetworkImageWithFallback(
        imageUrl: _profilePictureUrl!,
        width: 128,
        height: 128,
        borderRadius: BorderRadius.circular(64),
        fit: BoxFit.cover,
        errorWidget: CircleAvatar(
          radius: 64,
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: Icon(Icons.person,
              size: 64, color: Theme.of(context).colorScheme.primary),
        ),
      );
    }

    return CircleAvatar(
      radius: 64,
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      child: Icon(Icons.person,
          size: 64, color: Theme.of(context).colorScheme.primary),
    );
  }
}
