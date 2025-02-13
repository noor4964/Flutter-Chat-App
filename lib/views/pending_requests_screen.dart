import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/chat_service.dart';

class PendingRequestsScreen extends StatefulWidget {
  @override
  _PendingRequestsScreenState createState() => _PendingRequestsScreenState();
}

class _PendingRequestsScreenState extends State<PendingRequestsScreen> {
  final User? user = FirebaseAuth.instance.currentUser;
  final ChatService _chatService = ChatService();
  late ScaffoldMessengerState scaffoldMessenger;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    scaffoldMessenger = ScaffoldMessenger.of(context);
  }

  @override
  Widget build(BuildContext context) {
    if (user == null) {
      return const Center(child: Text('User not authenticated.'));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Pending Requests')),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('connections')
            .where('receiverId', isEqualTo: user!.uid)
            .where('status', isEqualTo: 'pending')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('No pending requests.'));
          }

          var requests = snapshot.data!.docs;

          return ListView.builder(
            itemCount: requests.length,
            itemBuilder: (context, index) {
              var request = requests[index].data() as Map<String, dynamic>;
              String senderId = request['senderId'] ?? 'Unknown';
              String requestId = requests[index].id;

              return FutureBuilder<DocumentSnapshot>(
                future: FirebaseFirestore.instance.collection('users').doc(senderId).get(),
                builder: (context, userSnapshot) {
                  if (userSnapshot.connectionState == ConnectionState.waiting) {
                    return ListTile(
                      title: const Text("Loading..."),
                      subtitle: Text('Request from $senderId'),
                      trailing: _buildActionButtons(requestId, senderId, context, null),
                    );
                  }

                  if (!userSnapshot.hasData || !userSnapshot.data!.exists) {
                    return ListTile(
                      title: const Text("Unknown User"),
                      subtitle: Text('Request from $senderId'),
                      trailing: _buildActionButtons(requestId, senderId, context, null),
                    );
                  }

                  var userData = userSnapshot.data!.data() as Map<String, dynamic>?;
                  return ListTile(
                    title: Text(userData?['username'] ?? "Unknown User", style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('Request from $senderId'),
                    trailing: _buildActionButtons(requestId, senderId, context, userData),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildActionButtons(String requestId, String senderId, BuildContext context, Map<String, dynamic>? userData) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.check, color: Colors.green),
          onPressed: () => acceptRequest(requestId, senderId, context),
        ),
        IconButton(
          icon: const Icon(Icons.close, color: Colors.red),
          onPressed: () => declineRequest(requestId, senderId, context, userData),
        ),
      ],
    );
  }

  void acceptRequest(String requestId, String senderId, BuildContext context) async {
    print("✅ Accept button clicked! Request ID: $requestId");

    try {
      await FirebaseFirestore.instance.collection('connections').doc(requestId).update({
        'status': 'accepted',
      });

      // Create a chat document for both users
      await _chatService.acceptConnectionRequest(requestId, senderId);

      scaffoldMessenger.showSnackBar(
        const SnackBar(content: Text('Request accepted!')),
      );
    } on FirebaseException catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('Error accepting request: ${e.message}')),
      );
      print("❌ Error accepting request: $e");
    } catch (e) {
      scaffoldMessenger.showSnackBar(
        const SnackBar(content: Text('An unexpected error occurred.')),
      );
      print("❌ Unexpected error: $e");
    }
  }

  void declineRequest(String requestId, String senderId, BuildContext context, Map<String, dynamic>? userData) async {
    try {
      await FirebaseFirestore.instance.collection('connections').doc(requestId).delete();

      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('Request from ${userData?['username'] ?? "Unknown User"} declined')),
      );
    } on FirebaseException catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('Error declining request: ${e.message}')),
      );
      print("❌ Error declining request: $e");
    } catch (e) {
      scaffoldMessenger.showSnackBar(
        const SnackBar(content: Text('An unexpected error occurred.')),
      );
      print("❌ Unexpected error: $e");
    }
  }
}