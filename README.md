# flutter_chat_app

A comprehensive Flutter-based communication platform with real-time messaging, voice/video calling, and social features. Built with modern architecture principles, the application supports multiple platforms including Android, iOS, web, Windows, Linux, and macOS.

## Features

### Core Functionality
- **Real-time Messaging**: Send and receive messages instantly using Firebase Firestore
- **Voice & Video Calls**: Make high-quality calls with Agora SDK and CallKit integration 
- **Media Sharing**: Exchange images, videos, and files with cloud storage integration
- **End-to-End Encryption**: Secure communication with message encryption
- **Push Notifications**: Stay updated with Firebase Cloud Messaging
- **Social Feed**: Share posts and updates with your network
- **Responsive Design**: Optimized interfaces for both mobile and desktop experiences

### User Management
- **Multi-platform Authentication**: Sign up and login using Firebase Authentication
- **User Connections**: Add contacts and manage your network
- **Detailed Profiles**: Customize profiles with photos and personal information
- **Connection Requests**: Send and accept connection requests

### Chat Features
- **Group Chats**: Create and manage group conversations
- **Chat Management**: Archive, mute, block, or delete conversations
- **Message Status**: See when messages are delivered and read
- **Typing Indicators**: Know when others are typing

### Customization
- **Theme Support**: Choose between light and dark mode
- **Notification Settings**: Configure how and when you receive alerts
- **Privacy Controls**: Manage who can contact you and see your information

### Technical Features
- **Cross-Platform**: One codebase for Android, iOS, web, Windows, Linux, and macOS
- **Offline Support**: Access messages even without internet connection
- **Error Handling**: Robust error management with clear user feedback
- **Analytics**: Usage tracking for app improvement (opt-in)

## Technology Stack

- **Frontend**: Flutter SDK with Provider for state management
- **Backend**: Firebase (Authentication, Firestore, Storage, Cloud Functions)
- **Database**: Cloud Firestore for real-time data
- **Call Infrastructure**: Agora SDK with CallKit integration
- **Data Connector**: DataConnect for enhanced database operations

## Getting Started

### Prerequisites

- [Flutter SDK](https://flutter.dev/docs/get-started/install) (version ^3.5.4)
- [Firebase Project](https://firebase.google.com/) with Firestore and Authentication enabled
- [Agora Account](https://www.agora.io/) for voice/video call functionality (optional)

### Installation

1. Clone the repository:
   ```sh
   git clone https://github.com/yourusername/flutter_chat_app.git
   cd flutter_chat_app
   ```

2. Install dependencies:
   ```sh
   flutter pub get
   ```

3. Configure Firebase:
   - Create a Firebase project in the [Firebase Console](https://console.firebase.google.com/)
   - Enable Authentication and Firestore
   - Add your app to the Firebase project and download the configuration files:
     - For Android: `google-services.json` to `android/app/`
     - For iOS: `GoogleService-Info.plist` to `ios/Runner/`
     - For Web: Update the Firebase config in `web/index.html`

4. Configure Agora (for call functionality):
   - Create an Agora project and get your App ID
   - Update the Agora App ID in the app configuration

5. Run the application:
   ```sh
   flutter run
   ```
 Run the application in Web:
   ```sh
   https://flutter-chat-app-e52b5.web.app/
   ```
## Project Structure

```
lib/
  ├── core/           # Core utilities, constants, and theme
  ├── models/         # Data models
  ├── providers/      # State management
  ├── services/       # API and backend services
  ├── views/          # UI screens
  ├── widgets/        # Reusable UI components
  └── main.dart       # App entry point
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details.
