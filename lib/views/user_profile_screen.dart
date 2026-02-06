import 'package:flutter/material.dart';

class UserProfileScreen extends StatelessWidget {
  final String profileImageUrl;
  final String username;
  final bool isOnline;

  const UserProfileScreen({
    Key? key,
    required this.profileImageUrl,
    required this.username,
    required this.isOnline,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        title: const Text('Profile'),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 20),
            CircleAvatar(
              backgroundImage: profileImageUrl.isNotEmpty 
                ? NetworkImage(profileImageUrl) 
                : null,
              backgroundColor: profileImageUrl.isEmpty 
                ? Theme.of(context).primaryColor 
                : null,
              radius: 50,
              child: profileImageUrl.isEmpty 
                ? Text(
                    username.isNotEmpty ? username[0].toUpperCase() : '?',
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ) 
                : null,
            ),
            const SizedBox(height: 10),
            Text(
              username,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
                        const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.phone),
                  onPressed: () {
                    // Handle audio call action
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.videocam),
                  onPressed: () {
                    // Handle video call action
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.notifications_off),
                  onPressed: () {
                    // Handle mute action
                  },
                ),
              ],
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.color_lens),
              title: const Text('Theme'),
              onTap: () {
                // Handle theme action
              },
            ),
            ListTile(
              leading: const Icon(Icons.favorite),
              title: const Text('Quick reaction'),
              onTap: () {
                // Handle quick reaction action
              },
            ),
            ListTile(
              leading: const Icon(Icons.text_fields),
              title: const Text('Nicknames'),
              onTap: () {
                // Handle nicknames action
              },
            ),
            ListTile(
              leading: const Icon(Icons.auto_awesome),
              title: const Text('Word effects'),
              onTap: () {
                // Handle word effects action
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.group),
              title: const Text('Create group chat with Sad'),
              onTap: () {
                // Handle create group chat action
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('View media, files & links'),
              onTap: () {
                // Handle view media action
              },
            ),
            ListTile(
              leading: const Icon(Icons.save),
              title: const Text('Save photos & videos'),
              onTap: () {
                // Handle save photos & videos action
              },
            ),
            ListTile(
              leading: const Icon(Icons.push_pin),
              title: const Text('Pinned messages'),
              onTap: () {
                // Handle pinned messages action
              },
            ),
          ],
        ),
      ),
    );
  }
}