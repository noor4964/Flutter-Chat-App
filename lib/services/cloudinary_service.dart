import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as path;
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:universal_io/io.dart';
import 'package:image_picker/image_picker.dart';

class CloudinaryService {
  // Cloudinary configuration
  static const String cloudName = 'daekv7k8q';
  static const String apiKey = '354918315997393';
  static const String apiSecret = 'J9RlhhbDDovsyNpOGz67futNGj0';
  static const String uploadUrl =
      'https://api.cloudinary.com/v1_1/daekv7k8q/image/upload';

  // Upload preset options - updated to use unsigned upload without presets
  static const String profilePicturePreset =
      'ml_default'; // Using Cloudinary's default preset
  static const String feedPostPreset =
      'ml_default'; // Using Cloudinary's default preset
  static const String storyMediaPreset =
      'ml_default'; // Using Cloudinary's default preset for stories

  /// Upload an image to Cloudinary and return the download URL
  ///
  /// [imageFile] can be File (mobile) or XFile (web)
  /// [webImage] is the Uint8List for web platforms
  /// [preset] is the upload preset to use (e.g., profile_picture, feed_post)
  static Future<String> uploadImage({
    required dynamic imageFile,
    Uint8List? webImage,
    required String preset,
  }) async {
    try {
      String timestamp = DateTime.now().millisecondsSinceEpoch.toString();

      // Add detailed logging for debugging
      print('🔄 Starting Cloudinary upload, preset: $preset');

      // Create multipart request
      var request = http.MultipartRequest('POST', Uri.parse(uploadUrl));

      // Add common fields
      request.fields['api_key'] = apiKey;
      request.fields['timestamp'] = timestamp;

      // Check if we should use a preset or not
      if (preset != 'direct_upload') {
        request.fields['upload_preset'] = preset;
      }

      // Add signature
      request.fields['signature'] =
          _generateSignature(apiSecret, timestamp, preset);

      // Handle file upload differently based on platform
      if (kIsWeb && webImage != null) {
        // For web
        final fileName = path.basename((imageFile as XFile).name);
        print('📂 Web upload: $fileName, size: ${webImage.length} bytes');

        request.files.add(http.MultipartFile.fromBytes(
          'file',
          webImage,
          filename: fileName,
          contentType: MediaType('image', 'jpeg'), // Adjust based on file type
        ));
      } else if (!kIsWeb) {
        // For mobile
        final mobilePath = (imageFile as File).path;
        print('📂 Mobile upload: $mobilePath');
        request.files
            .add(await http.MultipartFile.fromPath('file', mobilePath));
      } else {
        throw Exception("Invalid image data for upload");
      }

      // Send the request with timeout
      var response = await request.send().timeout(Duration(seconds: 30));
      var responseData = await http.Response.fromStream(response);

      print('📡 Cloudinary response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        var responseJson = json.decode(responseData.body);
        print('✅ Cloudinary upload successful: ${responseJson['secure_url']}');
        return responseJson['secure_url'];
      } else {
        print('❌ Cloudinary upload failed: ${responseData.body}');

        // Try direct upload if preset fails
        if (preset != 'direct_upload' &&
            responseData.body.contains("Upload preset not found")) {
          print('🔄 Trying direct upload without preset...');
          return await uploadImage(
            imageFile: imageFile,
            webImage: webImage,
            preset: 'direct_upload',
          );
        }

        throw Exception(
            'Failed to upload image (${response.statusCode}): ${responseData.body}');
      }
    } catch (e) {
      print('❌ Error in CloudinaryService.uploadImage: $e');
      rethrow;
    }
  }

  /// Generate a signature for Cloudinary upload
  static String _generateSignature(
      String apiSecret, String timestamp, String uploadPreset) {
    // Different signature generation for direct uploads vs preset uploads
    String signatureString;

    if (uploadPreset == 'direct_upload') {
      signatureString = 'timestamp=$timestamp$apiSecret';
    } else {
      signatureString =
          'timestamp=$timestamp&upload_preset=$uploadPreset$apiSecret';
    }

    var bytes = utf8.encode(signatureString);
    var digest = sha1.convert(bytes);
    return digest.toString();
  }
}
