import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
// import 'package:file_selector/file_selector.dart'; // Temporarily removed
import 'dart:io';

class ImagePickerHelper {
  static Future<XFile?> pickImage({required bool isCamera}) async {
    if (kIsWeb) {
      // Web implementation
      final ImagePicker picker = ImagePicker();
      return await picker.pickImage(
        source: isCamera ? ImageSource.camera : ImageSource.gallery,
      );
    } else if (Platform.isWindows) {
      // Windows implementation - temporarily using image_picker fallback
      if (!isCamera) {
        // For Windows, use image_picker with gallery option as fallback
        final ImagePicker picker = ImagePicker();
        return await picker.pickImage(source: ImageSource.gallery);
        
        // Original Windows implementation using file_selector
        /* 
        final XTypeGroup typeGroup = XTypeGroup(
          label: 'Images',
          extensions: ['jpg', 'jpeg', 'png', 'gif'],
        );
        return await openFile(acceptedTypeGroups: [typeGroup]);
        */
      }
      return null;
    } else {
      // Mobile implementation
      final ImagePicker picker = ImagePicker();
      return await picker.pickImage(
        source: isCamera ? ImageSource.camera : ImageSource.gallery,
      );
    }
  }
}
