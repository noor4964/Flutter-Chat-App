# Web Chat User Persistence Fix

## Issue
When extending/resizing the window in the web app, the selected chat user information was being lost. This happened because the layout switches between mobile and desktop views at the 1200px breakpoint, causing the widget tree to rebuild and losing the selected chat state.

## Root Cause
The selected chat state (`_selectedChatId`, `_selectedChatName`, etc.) was only stored in `ChatLayoutWithMainSidebar`. When the window was resized and the layout switched between mobile (<1200px) and desktop (>=1200px) views, the `ChatLayoutWithMainSidebar` widget was destroyed and recreated, losing all state.

## Solution
The fix implements state persistence at the parent level:

### 1. Added persistent state variables in `messenger_home_screen.dart`
```dart
// State variables for selected chat (persisted across layout changes)
String? _selectedChatId;
String? _selectedChatName;
String? _selectedChatProfileUrl;
bool _selectedChatIsOnline = false;
```

### 2. Pass state to `ChatLayoutWithMainSidebar`
```dart
ChatLayoutWithMainSidebar(
  // ... other parameters
  initialChatId: _selectedChatId,
  initialChatName: _selectedChatName,
  initialChatProfileUrl: _selectedChatProfileUrl,
  initialChatIsOnline: _selectedChatIsOnline,
  onChatSelected: (chatId, chatName, profileUrl, isOnline) {
    setState(() {
      _selectedChatId = chatId;
      _selectedChatName = chatName;
      _selectedChatProfileUrl = profileUrl;
      _selectedChatIsOnline = isOnline;
    });
  },
)
```

### 3. Updated `ChatLayoutWithMainSidebar` to accept initial values
- Added parameters: `initialChatId`, `initialChatName`, `initialChatProfileUrl`, `initialChatIsOnline`
- Added callback: `onChatSelected` to notify parent of state changes
- Initialize state from these values in `initState()`
- Added `didUpdateWidget()` to handle state updates when widget rebuilds

### 4. Key improvements
- State is now preserved when window is resized
- Smooth transition between mobile and desktop layouts
- Sidebar automatically collapses/expands based on chat selection state
- Works like WhatsApp Web where the selected chat persists across layout changes

## Files Modified
1. `lib/views/messenger_home_screen.dart`
   - Added persistent chat selection state variables
   - Pass state to ChatLayoutWithMainSidebar

2. `lib/widgets/chat_layout_with_main_sidebar.dart`
   - Added initial value parameters
   - Added onChatSelected callback
   - Implemented state restoration in initState()
   - Added didUpdateWidget() for state updates

## Testing
To test the fix:
1. Open the web app and navigate to the Chats tab
2. Select a chat conversation
3. Resize the browser window to cross the 1200px breakpoint (extend/shrink)
4. Verify that the selected chat and user information persists
5. The chat conversation should remain open with the correct user details displayed
