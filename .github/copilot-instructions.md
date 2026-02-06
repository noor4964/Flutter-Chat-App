# Flutter Chat App - Copilot Instructions

## Architecture Overview

This is a cross-platform Flutter chat application using **Firebase** backend and **Provider** for state management. The app supports Android, iOS, Web, Windows, Linux, and macOS with platform-specific adaptations.

### Core Data Flow
```
Views (UI) → Providers (State) → Services (Business Logic) → Firebase (Backend)
```

- **Services** (`lib/services/`) handle all Firebase interactions and business logic
- **Providers** (`lib/providers/`) manage app state using `ChangeNotifier` pattern
- **Views** (`lib/views/`) consume providers via `Provider.of<T>()` or `Consumer<T>`
- **Models** (`lib/models/`) define Firestore document structures

### Key Service Boundaries

| Service | Responsibility |
|---------|---------------|
| `ChatService` | Message CRUD, typing indicators, read receipts |
| `AuthService` | Firebase Auth, user sessions, online status |
| `CallService` | Agora SDK integration, call state management |
| `PresenceService` | User online/offline tracking |
| `NotificationService` | FCM push notifications (mobile only) |

## Platform-Specific Patterns

### Always use `PlatformHelper` for platform checks
```dart
// ✅ Correct
if (PlatformHelper.isWeb) { /* web-specific */ }
if (PlatformHelper.isMobile) { /* mobile-specific */ }

// ❌ Avoid direct Platform checks that fail on web
if (Platform.isAndroid) { } // Crashes on web
```

### Windows Firebase limitation
Firebase features may be limited on Windows. Check before Firebase operations:
```dart
if (_isWindowsWithoutFirebase) {
  print('Feature skipped on Windows');
  return;
}
```

### Responsive layouts
- Use `ResponsiveLayout` widget for mobile/desktop view switching (breakpoint: 768px)
- Use `WebLayoutWrapper` for web-specific three-column layout (breakpoint: 1200px)
- Desktop chat screens use sidebar + content pattern via `ChatLayoutWithMainSidebar`

## Firebase Conventions

### Firestore Collections Structure
- `users/{userId}` - User profiles with `isOnline`, `lastActive` fields
- `chats/{chatId}` - Chat metadata with `participants[]`, `lastMessage`
- `chats/{chatId}/messages/{messageId}` - Messages with `readBy[]` array
- `calls/{callId}` - Call records (caller/receiver must match auth user)
- `connections/{connectionId}` - Friend requests with `status: pending|accepted`

### Batch writes for performance
Always use batch writes when updating multiple documents:
```dart
final batch = _firestore.batch();
batch.set(messageRef, messageData);
batch.update(chatRef, chatUpdateData);
await batch.commit();
```

### Read receipts pattern
Messages track readers via `readBy[]` array. Current user is always in sender's `readBy`:
```dart
'readBy': [senderId], // Initialize with sender
```

## State Management Patterns

### Two global providers in `main.dart`
```dart
MultiProvider(
  providers: [
    ChangeNotifierProvider(create: (_) => ThemeProvider()),
    ChangeNotifierProvider(create: (_) => AuthProvider()),
  ],
)
```

### ThemeProvider capabilities
- Dark/light mode, font size scaling, animation toggles
- Settings persisted via `SharedPreferences`
- Access: `Provider.of<ThemeProvider>(context)`

## Calling Features (Agora SDK)

- Voice/video calls use Agora RTC Engine
- `CallService` manages Agora connection and Firestore call documents
- CallKit integration for native iOS/Android call UI (mobile only)
- Calls require microphone/camera permissions via `permission_handler`

## Build & Run Commands

```bash
# Development
flutter pub get
flutter run                    # Default platform
flutter run -d chrome          # Web
flutter run -d windows         # Windows desktop

# Web release build (deploys to Firebase Hosting)
flutter build web
firebase deploy --only hosting

# Analyze code
flutter analyze
```

## Testing Notes

- Tests located in `test/` directory
- Widget tests use standard Flutter test framework
- Firebase calls should be mocked in tests

## Common Patterns to Follow

1. **Error handling**: Use `FirebaseErrorHandler` singleton for Firebase errors
2. **Navigation**: Global `navigatorKey` in `main.dart` for push notification navigation
3. **Caching**: Services cache user info locally to reduce Firestore reads
4. **Cleanup**: Cancel `StreamSubscription` and dispose `AnimationController` in `dispose()`
5. **Timestamps**: Use `FieldValue.serverTimestamp()` for consistent ordering
