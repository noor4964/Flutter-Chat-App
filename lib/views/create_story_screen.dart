import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_chat_app/services/story_service.dart';
import 'package:flutter_chat_app/models/story_model.dart';

class CreateStoryScreen extends StatefulWidget {
  final XFile? initialImage;

  const CreateStoryScreen({Key? key, this.initialImage}) : super(key: key);

  @override
  _CreateStoryScreenState createState() => _CreateStoryScreenState();
}

class _CreateStoryScreenState extends State<CreateStoryScreen> {
  final StoryService _storyService = StoryService();
  final TextEditingController _captionController = TextEditingController();

  XFile? _selectedImage;
  Uint8List? _webImageBytes;
  bool _isLoading = false;
  String _mediaType = 'image'; // Default is image
  String _backgroundColor = '';
  StoryPrivacy _selectedPrivacy = StoryPrivacy.friends; // Default to friends
  List<Color> _backgroundColors = [
    Colors.black,
    Colors.deepPurple,
    Colors.indigo,
    Colors.blue,
    Colors.teal,
    Colors.green,
    Colors.amber,
    Colors.orange,
    Colors.deepOrange,
    Colors.red,
    Colors.pink,
    Colors.purple,
  ];

  @override
  void initState() {
    super.initState();
    _initializeStory();
  }

  Future<void> _initializeStory() async {
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
      final XFile? pickedFile = await _storyService.pickStoryMedia(source);

      if (pickedFile != null) {
        _selectedImage = pickedFile;

        if (kIsWeb) {
          _webImageBytes = await pickedFile.readAsBytes();
        }

        setState(() {
          _mediaType = 'image';
        });
      }
    } catch (e) {
      _showErrorSnackBar('Failed to pick image: ${e.toString()}');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _setTextStoryMode() {
    setState(() {
      _selectedImage = null;
      _webImageBytes = null;
      _mediaType = 'text';
      if (_backgroundColor.isEmpty) {
        _backgroundColor = 'purple'; // Default background color
      }
    });
  }

  void _setBackgroundColor(Color color) {
    // Convert color to string representation
    String colorString = color.toString().split('(0x')[1].split(')')[0];
    colorString = '#${colorString.substring(2)}';

    setState(() {
      _backgroundColor = colorString;
    });
  }

  Future<void> _createStory() async {
    // Validate inputs
    if (_mediaType == 'text' && _captionController.text.trim().isEmpty) {
      _showErrorSnackBar('Text stories require a caption');
      return;
    }

    if (_mediaType == 'image' && _selectedImage == null) {
      _showErrorSnackBar('Please select an image for your story');
      return;
    }

    setState(() => _isLoading = true);

    try {
      bool success = await _storyService.createStoryWithMedia(
        pickedMedia: _selectedImage,
        caption: _captionController.text.trim(),
        background: _backgroundColor,
        mediaType: _mediaType,
        privacy: _selectedPrivacy,
        context: context,
      );

      if (success && mounted) {
        // Give haptic feedback
        HapticFeedback.mediumImpact();

        // Navigate back
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      _showErrorSnackBar('Failed to create story: ${e.toString()}');
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
        title: const Text('Create Story'),
        elevation: 0,
        centerTitle: true,
        actions: [
          if (_mediaType == 'text')
            IconButton(
              icon: Icon(Icons.palette),
              tooltip: 'Change background color',
              onPressed: () => _showColorPicker(),
            ),
          IconButton(
            icon: Icon(_getPrivacyIcon()),
            tooltip: 'Story privacy',
            onPressed: () => _showPrivacyPicker(),
          ),
          TextButton(
            onPressed: _isLoading ? null : _createStory,
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
          : _buildMainContent(isDarkMode, colorScheme),
    );
  }

  Widget _buildMainContent(bool isDarkMode, ColorScheme colorScheme) {
    if (_mediaType == 'text') {
      return _buildTextStory(isDarkMode, colorScheme);
    } else {
      return _buildImageStory(isDarkMode, colorScheme);
    }
  }

  Widget _buildTextStory(bool isDarkMode, ColorScheme colorScheme) {
    // Parse the background color
    Color backgroundColor = _backgroundColor.isNotEmpty
        ? _parseColor(_backgroundColor)
        : Colors.deepPurple;

    // Get contrasting text color
    Color textColor = _getContrastingColor(backgroundColor);

    return Container(
      color: backgroundColor,
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: TextField(
                controller: _captionController,
                maxLines: null,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: textColor,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText: 'Type your story...',
                  hintStyle: TextStyle(
                    color: textColor.withOpacity(0.7),
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
          SizedBox(height: 20),
          Text(
            'Tap on palette icon to change background color',
            style: TextStyle(
              color: textColor.withOpacity(0.7),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageStory(bool isDarkMode, ColorScheme colorScheme) {
    return Column(
      children: [
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
                        'Select an image for your story',
                        style: TextStyle(
                          fontSize: 18,
                          color: colorScheme.onBackground.withOpacity(0.7),
                        ),
                      ),
                    ],
                  ),
                ),
        ),

        // Caption input
        Container(
          color: isDarkMode ? colorScheme.surface : Colors.white,
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              TextField(
                controller: _captionController,
                maxLines: 3,
                minLines: 1,
                decoration: InputDecoration(
                  hintText: 'Add a caption to your story...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding: EdgeInsets.all(12),
                ),
              ),

              const SizedBox(height: 16),

              // Option buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildOptionButton(
                    icon: Icons.camera_alt,
                    label: 'Camera',
                    onTap: () => _pickImage(ImageSource.camera),
                    color: Colors.indigo,
                  ),
                  _buildOptionButton(
                    icon: Icons.photo_library,
                    label: 'Gallery',
                    onTap: () => _pickImage(ImageSource.gallery),
                    color: Colors.purple,
                  ),
                  _buildOptionButton(
                    icon: Icons.text_fields,
                    label: 'Text',
                    onTap: _setTextStoryMode,
                    color: Colors.deepOrange,
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

  void _showColorPicker() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Select Background Color',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: _backgroundColors.map((color) {
                return GestureDetector(
                  onTap: () {
                    _setBackgroundColor(color);
                    Navigator.pop(context);
                  },
                  child: Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white,
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 4,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // Helper to parse color from string
  Color _parseColor(String colorString) {
    if (colorString.startsWith('#')) {
      return Color(int.parse('FF${colorString.substring(1)}', radix: 16));
    }

    // Return default color if parsing fails
    return Colors.deepPurple;
  }

  // Helper to get contrasting text color (black or white)
  Color _getContrastingColor(Color backgroundColor) {
    // Calculate luminance (brightness) of background color
    double luminance = (0.299 * backgroundColor.red +
            0.587 * backgroundColor.green +
            0.114 * backgroundColor.blue) /
        255;

    // Return white for dark backgrounds, black for light backgrounds
    return luminance > 0.5 ? Colors.black : Colors.white;
  }

  // Get privacy icon based on selected privacy setting
  IconData _getPrivacyIcon() {
    switch (_selectedPrivacy) {
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

  // Show privacy selection bottom sheet
  void _showPrivacyPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        padding: const EdgeInsets.all(16),
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
            
            Text(
              'Who can see your story?',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            
            // Privacy options
            _buildPrivacyOption(
              StoryPrivacy.public,
              Icons.public,
              'Public',
              'Anyone can view your story',
            ),
            _buildPrivacyOption(
              StoryPrivacy.friends,
              Icons.group,
              'Friends',
              'Only your friends can view your story',
            ),
            _buildPrivacyOption(
              StoryPrivacy.private,
              Icons.lock,
              'Private',
              'Only you can view your story',
            ),
            
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // Build privacy option tile
  Widget _buildPrivacyOption(
    StoryPrivacy privacy,
    IconData icon,
    String title,
    String description,
  ) {
    final bool isSelected = _selectedPrivacy == privacy;
    
    return ListTile(
      leading: Icon(
        icon,
        color: isSelected ? Theme.of(context).primaryColor : Colors.grey,
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? Theme.of(context).primaryColor : null,
        ),
      ),
      subtitle: Text(description),
      trailing: isSelected
          ? Icon(
              Icons.check_circle,
              color: Theme.of(context).primaryColor,
            )
          : null,
      onTap: () {
        setState(() {
          _selectedPrivacy = privacy;
        });
        Navigator.pop(context);
      },
    );
  }

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }
}
