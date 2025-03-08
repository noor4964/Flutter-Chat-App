import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';

class ProfileScreen extends StatefulWidget {
  @override
  _ProfileScreenState createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final User? user = FirebaseAuth.instance.currentUser;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  File? _imageFile;
  late TextEditingController _usernameController;
  late TextEditingController _emailController;
  late TextEditingController _genderController;
  String? _profilePictureUrl;

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController();
    _emailController = TextEditingController();
    _genderController = TextEditingController();
    _loadUserProfile();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _genderController.dispose();
    super.dispose();
  }

  Future<void> _loadUserProfile() async {
    if (user != null) {
      DocumentSnapshot userDoc = await _firestore.collection('users').doc(user!.uid).get();
      var userData = userDoc.data() as Map<String, dynamic>?;
      if (mounted) {
        setState(() {
          _usernameController.text = userData?['username'] ?? '';
          _emailController.text = userData?['email'] ?? '';
          _genderController.text = userData?['gender'] ?? '';
          _profilePictureUrl = userData?['profileImageUrl'] ?? null;
        });
      }
    }
  }

  Future<void> _updateProfile() async {
    if (user != null) {
      await _firestore.collection('users').doc(user!.uid).update({
        'username': _usernameController.text,
        'email': _emailController.text,
        'gender': _genderController.text,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Profile updated successfully')),
        );
      }
    }
  }

  Future<void> _pickImage() async {
    final pickedFile = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        _imageFile = File(pickedFile.path);
      });
      // Upload the image to Cloudinary and update the user's profile picture URL
      await _uploadProfilePicture();
    }
  }

  Future<void> _uploadProfilePicture() async {
    if (_imageFile != null && user != null) {
      try {
        // Upload the image to Cloudinary
        String uploadUrl = 'https://api.cloudinary.com/v1_1/daekv7k8q/image/upload';
        String apiKey = '354918315997393';
        String apiSecret = 'J9RlhhbDDovsyNpOGz67futNGj0';
        String timestamp = DateTime.now().millisecondsSinceEpoch.toString();

        var request = http.MultipartRequest('POST', Uri.parse(uploadUrl));
        request.fields['api_key'] = apiKey;
        request.fields['timestamp'] = timestamp;
        request.fields['signature'] = _generateSignature(apiSecret, timestamp, 'profile_picture');
        request.fields['upload_preset'] = 'profile_picture';
        request.files.add(await http.MultipartFile.fromPath('file', _imageFile!.path));

        var response = await request.send();
        var responseData = await http.Response.fromStream(response);

        print('Response status: ${response.statusCode}');
        print('Response body: ${responseData.body}');

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
            });

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Profile picture updated successfully')),
            );
          }
        } else {
          print('Failed to upload profile picture: ${responseData.body}');
          throw Exception('Failed to upload profile picture');
        }
      } catch (e) {
        print('Exception: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to upload profile picture: $e')),
          );
        }
      }
    }
  }

  String _generateSignature(String apiSecret, String timestamp, String uploadPreset) {
    var bytes = utf8.encode('timestamp=$timestamp&upload_preset=$uploadPreset$apiSecret');
    var digest = sha1.convert(bytes);
    return digest.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Profile'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: <Widget>[
            GestureDetector(
              onTap: _pickImage,
              child: CircleAvatar(
                radius: 50,
                backgroundImage: _imageFile != null
                    ? FileImage(_imageFile!)
                    : (_profilePictureUrl != null
                        ? NetworkImage(_profilePictureUrl!)
                        : null),
                child: _imageFile == null && _profilePictureUrl == null
                    ? Icon(Icons.person, size: 50)
                    : null,
              ),
            ),
            SizedBox(height: 20),
            TextField(
              decoration: InputDecoration(labelText: 'Username'),
              controller: _usernameController,
            ),
            TextField(
              decoration: InputDecoration(labelText: 'Email'),
              controller: _emailController,
            ),
            TextField(
              decoration: InputDecoration(labelText: 'Gender'),
              controller: _genderController,
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: _updateProfile,
              child: Text('Update Profile'),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                await FirebaseAuth.instance.signOut();
                Navigator.pushReplacementNamed(context, '/login');
              },
              child: Text('Logout'),
            ),
          ],
        ),
      ),
    );
  }
}