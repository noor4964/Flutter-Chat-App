import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_chat_app/services/auth_service.dart';

class PendingRequestsScreen extends StatefulWidget {
  @override
  _PendingRequestsScreenState createState() => _PendingRequestsScreenState();
}

class _PendingRequestsScreenState extends State<PendingRequestsScreen> {
  final AuthService _authService = AuthService();
  final User? user = FirebaseAuth.instance.currentUser;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pending Requests'),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _authService.getPendingRequests(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || snapshot.data == null || snapshot.data!.isEmpty) {
            return const Center(child: Text("No pending requests found."));
          }
          List<Map<String, dynamic>> pendingRequests = snapshot.data!;
          return ListView.builder(
            itemCount: pendingRequests.length,
            itemBuilder: (context, index) {
              var request = pendingRequests[index];
              if (request.isEmpty) {
                return ListTile(
                  title: Text('Request not found'),
                );
              }
              String? requestId = request['id'];
              String? senderId = request['senderId'];
              if (requestId == null || senderId == null) {
                return ListTile(
                  title: Text('Request ID or Sender ID is missing'),
                );
              }
              return ListTile(
                title: Text(senderId),
                subtitle: Text('Pending request'),
                trailing: IconButton(
                  icon: Icon(Icons.check),
                  onPressed: () async {
                    await _authService.acceptConnection(requestId);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Connection request accepted')),
                    );
                    setState(() {
                      pendingRequests.removeAt(index);
                    });
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}