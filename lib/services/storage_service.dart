import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;

class StorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;

  // Upload image with platform-specific handling
  Future<String?> uploadImage(XFile imageFile, String folderPath) async {
    try {
      // Create a storage reference
      final fileName = path.basename(imageFile.path);
      final destination = '$folderPath/$fileName';
      final ref = _storage.ref().child(destination);

      UploadTask uploadTask;

      if (kIsWeb) {
        // Web platform handling
        final bytes = await imageFile.readAsBytes();
        uploadTask = ref.putData(bytes);
      } else if (Platform.isWindows) {
        // Windows platform handling
        final file = File(imageFile.path);
        final bytes = await file.readAsBytes();
        uploadTask = ref.putData(bytes);
      } else {
        // Android, iOS, etc.
        final file = File(imageFile.path);
        uploadTask = ref.putFile(file);
      }

      // Wait for the upload to complete
      final snapshot = await uploadTask;

      // Get the download URL
      final downloadUrl = await snapshot.ref.getDownloadURL();
      return downloadUrl;
    } catch (e) {
      print('Error uploading image: $e');
      return null;
    }
  }

  // Pick image with platform-specific handling
  Future<XFile?> pickImage({required ImageSource source}) async {
    try {
      final picker = ImagePicker();
      final XFile? pickedFile = await picker.pickImage(source: source);
      return pickedFile;
    } catch (e) {
      print('Error picking image: $e');
      return null;
    }
  }

  // Delete image from storage
  Future<bool> deleteImage(String imageUrl) async {
    try {
      final ref = _storage.refFromURL(imageUrl);
      await ref.delete();
      return true;
    } catch (e) {
      print('Error deleting image: $e');
      return false;
    }
  }
}
