import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class PendingRequestsScreen extends StatefulWidget {
  @override
  _PendingRequestsScreenState createState() => _PendingRequestsScreenState();
}

class _PendingRequestsScreenState extends State<PendingRequestsScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  late Future<List<Map<String, dynamic>>> _pendingRequestsFuture;

  @override
  void initState() {
    super.initState();
    _pendingRequestsFuture = fetchPendingRequests();
  }

  Future<List<Map<String, dynamic>>> fetchPendingRequests() async {
    String userId = _auth.currentUser!.uid;

    // Step 1: Fetch all pending requests
    QuerySnapshot requestSnapshot = await _firestore
        .collection('connections')
        .where('receiverId', isEqualTo: userId)
        .where('status', isEqualTo: 'pending')
        .get();

    if (requestSnapshot.docs.isEmpty) return [];

    // Step 2: Extract all sender IDs
    List<String> senderIds = requestSnapshot.docs
        .map((doc) => doc['senderId'] as String)
        .toSet()
        .toList(); // Remove duplicates

    // Step 3: Fetch sender user details in a single query
    QuerySnapshot userSnapshot = await _firestore
        .collection('users')
        .where('uid', whereIn: senderIds)
        .get();

    // Step 4: Create a combined list of connection requests with user details
    Map<String, Map<String, dynamic>> userMap = {
      for (var doc in userSnapshot.docs) doc['uid']: doc.data() as Map<String, dynamic>
    };

    return requestSnapshot.docs.map((doc) {
      Map<String, dynamic> requestData = doc.data() as Map<String, dynamic>;
      requestData['id'] = doc.id; // Include request document ID
      requestData['senderDetails'] = userMap[requestData['senderId']] ?? {};
      return requestData;
    }).toList();
  }

  Future<void> acceptRequest(String requestId, String senderId) async {
    try {
      await _firestore.collection('connections').doc(requestId).update({
        'status': 'accepted',
      });

      // Create a new chat for these users
      await _firestore.collection('chats').add({
        'userIds': [_auth.currentUser!.uid, senderId],
        'createdAt': FieldValue.serverTimestamp(),
      });

      print("✅ Connection request accepted and chat created.");

      // Refresh UI
      setState(() {
        _pendingRequestsFuture = fetchPendingRequests();
      });
    } catch (e) {
      print("❌ Error accepting request: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Pending Requests")),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _pendingRequestsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text("❌ Error loading requests"));
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return Center(child: Text("No pending requests"));
          }

          List<Map<String, dynamic>> pendingRequests = snapshot.data!;

          return ListView.builder(
            itemCount: pendingRequests.length,
            itemBuilder: (context, index) {
              var request = pendingRequests[index];
              var senderDetails = request['senderDetails'];

              return Card(
                margin: EdgeInsets.all(8),
                child: ListTile(
                  leading: CircleAvatar(
                    child: senderDetails['username'] != null
                        ? Text(senderDetails['username'][0].toUpperCase())
                        : Icon(Icons.person),
                  ),
                  title: Text(senderDetails['username'] ?? 'Unknown'),
                  subtitle: Text(senderDetails['email'] ?? ''),
                  trailing: ElevatedButton(
                    onPressed: () => acceptRequest(request['id'], request['senderId']),
                    child: Text("Accept"),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
