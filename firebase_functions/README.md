# Firebase Cloud Functions for Chat App Notifications

This directory contains the Cloud Functions that handle push notifications for the chat app.

## Setup & Deployment Instructions

### Prerequisites
- Node.js (v14 or newer)
- Firebase CLI (`npm install -g firebase-tools`)
- Firebase project with Blaze plan (required for external API calls)

### Steps to Deploy

1. Log in to Firebase:
```bash
firebase login
```

2. Initialize Firebase in this directory if not already done:
```bash
cd firebase_functions
firebase init functions
```
Select your project when prompted.

3. Install dependencies:
```bash
cd functions
npm install
```

4. Deploy the functions:
```bash
firebase deploy --only functions
```

5. After deployment, get the function URL from the Firebase console and update the `_functionUrl` variable in `lib/services/chat_notification_service.dart`.

## Functions Description

The following Cloud Functions are included:

1. **sendChatNotification**: HTTP callable function that sends a notification to specific users
2. **onNewMessage**: Triggered when new messages are added to Firestore
3. **onNewFriendRequest**: Triggered when a new friend request is created
4. **cleanupTokens**: Scheduled function that cleans up invalid FCM tokens daily

## Security Rules

Make sure your Firestore security rules allow these functions to read and write to the appropriate collections.