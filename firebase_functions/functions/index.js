const functions = require('firebase-functions');
const admin = require('firebase-admin');

admin.initializeApp();

// Cloud Function to send chat notifications
exports.sendChatNotification = functions.https.onCall(async (data, context) => {
  // Check if the user is authenticated
  if (!context.auth) {
    throw new functions.https.HttpsError(
      'unauthenticated',
      'The function must be called while authenticated.'
    );
  }

  const { recipientId, message, title, chatId } = data;
  
  try {
    // Get recipient user document
    const userSnapshot = await admin.firestore().collection('users').doc(recipientId).get();
    
    if (!userSnapshot.exists) {
      throw new functions.https.HttpsError(
        'not-found',
        'The specified recipient does not exist.'
      );
    }
    
    const userData = userSnapshot.data();
    const tokens = userData.fcmTokens || [];
    
    if (tokens.length === 0) {
      console.log('No tokens available for user:', recipientId);
      return { success: false, error: 'No notification tokens found' };
    }
    
    // Create notification payload
    const payload = {
      notification: {
        title: title || 'New Message',
        body: message || 'You received a new message',
        clickAction: 'FLUTTER_NOTIFICATION_CLICK',
        sound: 'default',
      },
      data: {
        chatId: chatId,
        senderId: context.auth.uid,
        click_action: 'FLUTTER_NOTIFICATION_CLICK',
        type: 'chat_message',
      },
    };
    
    // Send the notification
    const response = await admin.messaging().sendToDevice(tokens, payload);
    
    // Clean up tokens that are no longer valid
    const tokensToRemove = [];
    response.results.forEach((result, index) => {
      const error = result.error;
      if (error) {
        console.error('FCM error:', error);
        // Check if the error is related to an invalid token
        if (error.code === 'messaging/invalid-registration-token' || 
            error.code === 'messaging/registration-token-not-registered') {
          tokensToRemove.push(tokens[index]);
        }
      }
    });
    
    // Remove invalid tokens
    if (tokensToRemove.length > 0) {
      await admin.firestore().collection('users').doc(recipientId).update({
        fcmTokens: admin.firestore.FieldValue.arrayRemove(...tokensToRemove),
      });
    }
    
    return { success: true, sentTo: tokens.length - tokensToRemove.length };
  } catch (error) {
    console.error('Error sending notification:', error);
    throw new functions.https.HttpsError('internal', error.message);
  }
});

// Firestore trigger for new messages - send notification automatically
exports.onNewMessage = functions.firestore
  .document('chats/{chatId}/messages/{messageId}')
  .onCreate(async (snapshot, context) => {
    const messageData = snapshot.data();
    const chatId = context.params.chatId;
    
    // Don't send notification for system messages
    if (messageData.type === 'system') return null;
    
    try {
      // Get the chat document to find participants
      const chatSnapshot = await admin.firestore().collection('chats').doc(chatId).get();
      if (!chatSnapshot.exists) return null;
      
      const chatData = chatSnapshot.data();
      const participants = chatData.userIds || [];
      
      // Don't send notification to the sender
      const senderId = messageData.senderId;
      const recipientIds = participants.filter(id => id !== senderId);
      
      // Get sender information for the notification
      const senderSnapshot = await admin.firestore().collection('users').doc(senderId).get();
      if (!senderSnapshot.exists) return null;
      
      const senderData = senderSnapshot.data();
      const senderName = senderData.displayName || 'Someone';
      
      // For each recipient, check if they should receive a notification
      const notificationPromises = recipientIds.map(async (recipientId) => {
        // Check if recipient is currently in this chat (presence system)
        const presenceSnapshot = await admin.firestore()
          .collection('presence')
          .doc(recipientId)
          .get();
        
        // If user is active in this chat, don't send notification
        if (presenceSnapshot.exists) {
          const presence = presenceSnapshot.data();
          if (presence.online && presence.activeChatId === chatId) {
            console.log(`User ${recipientId} is active in chat, skipping notification`);
            return null;
          }
        }
        
        // Get recipient tokens
        const recipientSnapshot = await admin.firestore()
          .collection('users')
          .doc(recipientId)
          .get();
        
        if (!recipientSnapshot.exists) return null;
        
        const recipientData = recipientSnapshot.data();
        const tokens = recipientData.fcmTokens || [];
        
        if (tokens.length === 0) return null;
        
        // Message content for notification
        let notificationBody = '';
        if (messageData.type === 'text') {
          notificationBody = messageData.text;
        } else if (messageData.type === 'image') {
          notificationBody = '📷 Photo';
        } else if (messageData.type === 'video') {
          notificationBody = '🎥 Video';
        } else if (messageData.type === 'audio') {
          notificationBody = '🔊 Audio message';
        } else if (messageData.type === 'file') {
          notificationBody = '📎 File';
        } else {
          notificationBody = 'New message';
        }
        
        // Create notification
        const payload = {
          notification: {
            title: senderName,
            body: notificationBody,
            clickAction: 'FLUTTER_NOTIFICATION_CLICK',
            sound: 'default',
          },
          data: {
            chatId: chatId,
            senderId: senderId,
            senderName: senderName,
            type: 'message',
            click_action: 'FLUTTER_NOTIFICATION_CLICK',
          },
        };
        
        // Send message
        return admin.messaging().sendToDevice(tokens, payload);
      });
      
      await Promise.all(notificationPromises);
      return null;
    } catch (error) {
      console.error('Error sending message notification:', error);
      return null;
    }
  });

// Firestore trigger for friend requests - send notification automatically
exports.onNewFriendRequest = functions.firestore
  .document('friendRequests/{requestId}')
  .onCreate(async (snapshot, context) => {
    const requestData = snapshot.data();
    const recipientId = requestData.recipientId;
    const senderId = requestData.senderId;
    
    try {
      // Get sender information
      const senderSnapshot = await admin.firestore()
        .collection('users')
        .doc(senderId)
        .get();
      
      if (!senderSnapshot.exists) return null;
      
      const senderData = senderSnapshot.data();
      const senderName = senderData.displayName || 'Someone';
      
      // Get recipient tokens
      const recipientSnapshot = await admin.firestore()
        .collection('users')
        .doc(recipientId)
        .get();
      
      if (!recipientSnapshot.exists) return null;
      
      const recipientData = recipientSnapshot.data();
      const tokens = recipientData.fcmTokens || [];
      
      if (tokens.length === 0) return null;
      
      // Create notification
      const payload = {
        notification: {
          title: 'New Friend Request',
          body: `${senderName} sent you a friend request`,
          clickAction: 'FLUTTER_NOTIFICATION_CLICK',
          sound: 'default',
        },
        data: {
          requestId: context.params.requestId,
          senderId: senderId,
          senderName: senderName,
          type: 'friend_request',
          click_action: 'FLUTTER_NOTIFICATION_CLICK',
        },
      };
      
      // Send notification
      await admin.messaging().sendToDevice(tokens, payload);
      
      // Create notification document
      await admin.firestore().collection('notifications').add({
        recipientId: recipientId,
        senderId: senderId,
        senderName: senderName,
        senderImageUrl: senderData.profileImageUrl || null,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        type: 'friend_request',
        isRead: false,
      });
      
      return null;
    } catch (error) {
      console.error('Error sending friend request notification:', error);
      return null;
    }
  });

// Cloud Function to send test notifications
exports.sendTestNotification = functions.https.onCall(async (data, context) => {
  // Check if the user is authenticated
  if (!context.auth) {
    throw new functions.https.HttpsError(
      'unauthenticated',
      'The function must be called while authenticated.'
    );
  }

  const { userId, withSound } = data;
  
  try {
    // Get the user document
    const userSnapshot = await admin.firestore().collection('users').doc(userId).get();
    
    if (!userSnapshot.exists) {
      console.log('User not found:', userId);
      return { success: false, error: 'User not found' };
    }
    
    const userData = userSnapshot.data();
    const tokens = userData.fcmTokens || [];
    
    if (tokens.length === 0) {
      console.log('No tokens available for user:', userId);
      return { success: false, error: 'No notification tokens found' };
    }
    
    // Create test notification payload
    const payload = {
      notification: {
        title: 'Test Notification',
        body: 'This is a test notification to verify the notification system is working',
        clickAction: 'FLUTTER_NOTIFICATION_CLICK',
        sound: withSound ? 'default' : null,
      },
      data: {
        type: 'test_notification',
        timestamp: Date.now().toString(),
        click_action: 'FLUTTER_NOTIFICATION_CLICK',
      },
    };
    
    // Send the notification
    const response = await admin.messaging().sendToDevice(tokens, payload);
    
    // Log results
    console.log('Test notification sent to user', userId);
    console.log('Device count:', tokens.length);
    console.log('Successful deliveries:', response.successCount);
    
    return { 
      success: true, 
      sentTo: tokens.length,
      successCount: response.successCount,
      timestamp: new Date().toISOString()
    };
  } catch (error) {
    console.error('Error sending test notification:', error);
    throw new functions.https.HttpsError('internal', error.message);
  }
});

// Cleanup unused FCM tokens periodically
exports.cleanupTokens = functions.pubsub.schedule('every 24 hours').onRun(async (context) => {
  const firestore = admin.firestore();
  const usersSnapshot = await firestore.collection('users').get();
  
  const batchPromises = [];
  
  for (const userDoc of usersSnapshot.docs) {
    const userData = userDoc.data();
    const tokens = userData.fcmTokens || [];
    
    if (tokens.length === 0) continue;
    
    // Check each token's validity
    const checkPromises = tokens.map(async (token) => {
      try {
        // Using a dry run message to test if the token is valid
        await admin.messaging().send({
          token: token,
          data: { test: 'true' },
          android: { priority: 'normal' },
          apns: { headers: { 'apns-priority': '5' } },
        }, true); // true for dryRun
        
        return null; // Token is valid
      } catch (error) {
        // If error occurs, token is invalid
        return token;
      }
    });
    
    const invalidTokens = (await Promise.all(checkPromises)).filter(Boolean);
    
    if (invalidTokens.length > 0) {
      batchPromises.push(
        firestore.collection('users').doc(userDoc.id).update({
          fcmTokens: admin.firestore.FieldValue.arrayRemove(...invalidTokens),
        })
      );
    }
  }
  
  if (batchPromises.length > 0) {
    await Promise.all(batchPromises);
  }
  
  console.log(`Cleaned up tokens for ${batchPromises.length} users`);
  return null;
});