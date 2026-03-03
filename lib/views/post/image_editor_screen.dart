import 'dart:convert';
import 'dart:math' show pi;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

/// Image editor screen with crop, rotate, and Instagram-style filters.
/// Accepts image bytes, returns edited image bytes.
class ImageEditorScreen extends StatefulWidget {
  final Uint8List imageBytes;

  const ImageEditorScreen({Key? key, required this.imageBytes})
      : super(key: key);

  @override
  State<ImageEditorScreen> createState() => _ImageEditorScreenState();
}

class _ImageEditorScreenState extends State<ImageEditorScreen> {
  late Uint8List _currentBytes;
  String _selectedFilter = 'Normal';
  bool _isProcessing = false;
  final GlobalKey _repaintKey = GlobalKey();

  // Instagram-style filter matrices (4x5 color matrix values)
  static final Map<String, List<double>> _filters = {
    'Normal': [
      1, 0, 0, 0, 0,
      0, 1, 0, 0, 0,
      0, 0, 1, 0, 0,
      0, 0, 0, 1, 0,
    ],
    'Clarendon': [
      1.2, 0, 0, 0, 10,
      0, 1.2, 0, 0, 10,
      0, 0, 1.2, 0, 10,
      0, 0, 0, 1, 0,
    ],
    'Gingham': [
      0.8, 0.1, 0.1, 0, 20,
      0.1, 0.8, 0.1, 0, 20,
      0.1, 0.1, 0.7, 0, 20,
      0, 0, 0, 1, 0,
    ],
    'Moon': [
      0.33, 0.33, 0.33, 0, 10,
      0.33, 0.33, 0.33, 0, 10,
      0.33, 0.33, 0.33, 0, 10,
      0, 0, 0, 1, 0,
    ],
    'Lark': [
      1.2, 0.05, 0.05, 0, 15,
      0.05, 1.1, 0.05, 0, 15,
      0.05, 0.05, 0.9, 0, 15,
      0, 0, 0, 1, 0,
    ],
    'Reyes': [
      0.9, 0.1, 0.1, 0, 30,
      0.1, 0.85, 0.1, 0, 30,
      0.1, 0.1, 0.8, 0, 25,
      0, 0, 0, 0.9, 0,
    ],
    'Juno': [
      1.3, 0, 0, 0, 0,
      0, 1.1, 0, 0, 0,
      0, 0, 0.9, 0, 0,
      0, 0, 0, 1, 0,
    ],
  };

  @override
  void initState() {
    super.initState();
    _currentBytes = widget.imageBytes;
  }

  Future<void> _cropImage() async {
    setState(() => _isProcessing = true);
    try {
      String sourcePath;

      if (kIsWeb) {
        // On web, the image_cropper plugin sets sourcePath as the <img> element's src.
        // We must provide a valid URL the browser can load — a base64 data URL works.
        final base64Str = base64Encode(_currentBytes);
        sourcePath = 'data:image/jpeg;base64,$base64Str';
      } else {
        // On mobile, write bytes to a temp file for image_cropper
        final tempDir = await getTemporaryDirectory();
        final tempFile = File(
            '${tempDir.path}/crop_source_${DateTime.now().millisecondsSinceEpoch}.jpg');
        await tempFile.writeAsBytes(_currentBytes);
        sourcePath = tempFile.path;
      }

      final croppedFile = await ImageCropper().cropImage(
        sourcePath: sourcePath,
        compressFormat: ImageCompressFormat.jpg,
        compressQuality: 90,
        uiSettings: [
          if (!kIsWeb) ...[
            AndroidUiSettings(
              toolbarTitle: 'Crop Image',
              toolbarColor: Colors.black,
              toolbarWidgetColor: Colors.white,
              activeControlsWidgetColor: Colors.blue,
              initAspectRatio: CropAspectRatioPreset.original,
              lockAspectRatio: false,
              aspectRatioPresets: [
                CropAspectRatioPreset.original,
                CropAspectRatioPreset.square,
                CropAspectRatioPreset.ratio4x3,
                CropAspectRatioPreset.ratio16x9,
              ],
            ),
            IOSUiSettings(
              title: 'Crop Image',
              aspectRatioPresets: [
                CropAspectRatioPreset.original,
                CropAspectRatioPreset.square,
                CropAspectRatioPreset.ratio4x3,
                CropAspectRatioPreset.ratio16x9,
              ],
            ),
          ],
          if (kIsWeb)
            WebUiSettings(
              context: context,
              presentStyle: WebPresentStyle.dialog,
              size: const CropperSize(width: 520, height: 520),
            ),
        ],
      );

      if (croppedFile != null) {
        // Use CroppedFile.readAsBytes() — works cross-platform (web + mobile)
        final bytes = await croppedFile.readAsBytes();
        setState(() => _currentBytes = bytes);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Crop failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _rotateImage() async {
    setState(() => _isProcessing = true);
    try {
      final codec = await ui.instantiateImageCodec(_currentBytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;

      final int newWidth = image.height;
      final int newHeight = image.width;

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.translate(newWidth.toDouble(), 0);
      canvas.rotate(pi / 2);
      canvas.drawImage(image, Offset.zero, Paint());

      final picture = recorder.endRecording();
      final rotatedImage = await picture.toImage(newWidth, newHeight);
      final byteData =
          await rotatedImage.toByteData(format: ui.ImageByteFormat.png);

      image.dispose();
      rotatedImage.dispose();

      if (byteData != null && mounted) {
        setState(() {
          _currentBytes = byteData.buffer.asUint8List();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Rotate failed: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<Uint8List?> _captureFilteredImage() async {
    try {
      final boundary = _repaintKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return null;

      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (e) {
      return null;
    }
  }

  void _onDone() async {
    if (_selectedFilter == 'Normal') {
      Navigator.of(context).pop(_currentBytes);
      return;
    }

    setState(() => _isProcessing = true);
    final filtered = await _captureFilteredImage();
    if (mounted) {
      setState(() => _isProcessing = false);
      Navigator.of(context).pop(filtered ?? _currentBytes);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Edit Photo'),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(null),
        ),
        actions: [
          TextButton(
            onPressed: _isProcessing ? null : _onDone,
            child: Text(
              'Done',
              style: TextStyle(
                color: _isProcessing ? Colors.grey : Colors.blue,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
      body: _isProcessing
          ? const Center(
              child: CircularProgressIndicator(color: Colors.white))
          : Column(
              children: [
                // Image preview with filter applied
                Expanded(
                  child: Center(
                    child: RepaintBoundary(
                      key: _repaintKey,
                      child: ColorFiltered(
                        colorFilter: ColorFilter.matrix(
                          _filters[_selectedFilter]!,
                        ),
                        child: Image.memory(
                          _currentBytes,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                ),

                // Edit action buttons
                Container(
                  color: Colors.black,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildActionButton(
                        icon: Icons.crop,
                        label: 'Crop',
                        onTap: _cropImage,
                      ),
                      _buildActionButton(
                        icon: Icons.rotate_right,
                        label: 'Rotate',
                        onTap: _rotateImage,
                      ),
                    ],
                  ),
                ),

                // Filter strip
                Container(
                  color: Colors.black,
                  height: 120,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    itemCount: _filters.length,
                    itemBuilder: (context, index) {
                      final filterName =
                          _filters.keys.elementAt(index);
                      final isSelected =
                          _selectedFilter == filterName;
                      return GestureDetector(
                        onTap: () {
                          setState(
                              () => _selectedFilter = filterName);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6),
                          child: Column(
                            mainAxisAlignment:
                                MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  borderRadius:
                                      BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isSelected
                                        ? Colors.blue
                                        : Colors.transparent,
                                    width: 2,
                                  ),
                                ),
                                child: ClipRRect(
                                  borderRadius:
                                      BorderRadius.circular(6),
                                  child: ColorFiltered(
                                    colorFilter:
                                        ColorFilter.matrix(
                                      _filters[filterName]!,
                                    ),
                                    child: Image.memory(
                                      _currentBytes,
                                      fit: BoxFit.cover,
                                      width: 72,
                                      height: 72,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                filterName,
                                style: TextStyle(
                                  color: isSelected
                                      ? Colors.blue
                                      : Colors.white70,
                                  fontSize: 11,
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
          const SizedBox(height: 4),
          Text(label,
              style:
                  const TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ),
    );
  }
}
