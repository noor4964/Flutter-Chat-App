import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_chat_app/services/calls/call_service.dart';

/// Call state for UI rendering.
enum CallState {
  idle,
  ringing,
  connecting,
  connected,
  ended,
  missed,
  declined,
  error,
}

/// Centralized call state provider.
///
/// Manages call lifecycle, incoming call detection, mute/speaker state,
/// call duration timer, and call history. Follows the same ChangeNotifier
/// pattern as ChatProvider.
class CallProvider extends ChangeNotifier {
  final CallService _callService = CallService();

  // ── Subscriptions ──────────────────────────────────────────────────────
  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<Call>? _incomingCallSubscription;
  StreamSubscription<Call>? _callStatusSubscription;

  // ── State ──────────────────────────────────────────────────────────────
  CallState _callState = CallState.idle;
  Call? _currentCall;
  bool _isMuted = false;
  bool _isSpeakerOn = false;
  bool _initialized = false;

  // ── Duration timer ─────────────────────────────────────────────────────
  Timer? _durationTimer;
  int _durationSeconds = 0;

  // ── Call history ───────────────────────────────────────────────────────
  List<Call> _callHistory = [];
  bool _isLoadingHistory = false;

  // ── Incoming call callback ─────────────────────────────────────────────
  /// Set by the HomeScreen to handle navigation when an incoming call arrives.
  void Function(Call)? onIncomingCall;

  // ── Public getters ─────────────────────────────────────────────────────
  CallState get callState => _callState;
  Call? get currentCall => _currentCall;
  bool get isMuted => _isMuted;
  bool get isSpeakerOn => _isSpeakerOn;
  int get durationSeconds => _durationSeconds;
  List<Call> get callHistory => _callHistory;
  bool get isLoadingHistory => _isLoadingHistory;

  String get formattedDuration {
    final minutes = _durationSeconds ~/ 60;
    final seconds = _durationSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  int get missedCallCount {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return 0;
    return _callHistory
        .where((call) => call.status == 'missed' && call.missedBy == user.uid)
        .length;
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────

  /// Call once from main.dart MultiProvider. Guards against duplicate init.
  void initialize() {
    if (_initialized) return;
    _initialized = true;

    _authSubscription =
        FirebaseAuth.instance.authStateChanges().listen((User? user) {
      if (user != null) {
        _initCallService();
        _listenForIncomingCalls();
        loadCallHistory();
      } else {
        _cleanup();
      }
    });
  }

  Future<void> _initCallService() async {
    try {
      await _callService.initialize();
    } catch (e) {
      debugPrint('Error initializing call service: $e');
    }
  }

  void _listenForIncomingCalls() {
    _incomingCallSubscription?.cancel();
    try {
      _incomingCallSubscription =
          _callService.listenForIncomingCalls().listen((call) {
        if (call.callId != 'no-call' &&
            call.callId != 'error' &&
            call.status == 'ringing') {
          _currentCall = call;
          _callState = CallState.ringing;
          notifyListeners();
          onIncomingCall?.call(call);
        }
      }, onError: (error) {
        debugPrint('Error listening for incoming calls: $error');
      });
    } catch (e) {
      debugPrint('Error setting up incoming call listener: $e');
    }
  }

  // ── Call actions ───────────────────────────────────────────────────────

  /// Start an outgoing call. Returns the Call object or null on failure.
  Future<Call?> startCall(String receiverId, bool isVideo) async {
    _callState = CallState.ringing;
    _isMuted = false;
    _isSpeakerOn = false;
    _durationSeconds = 0;
    notifyListeners();

    final call = await _callService.startCall(receiverId, isVideo);
    if (call != null) {
      _currentCall = call;
      _listenForCallStatusChanges(call.callId);
      notifyListeners();
    } else {
      _callState = CallState.error;
      notifyListeners();
      _autoResetAfterDelay();
    }
    return call;
  }

  /// Answer an incoming call.
  Future<bool> answerCall(String callId) async {
    _callState = CallState.connecting;
    notifyListeners();

    final success = await _callService.answerCall(callId);
    if (success) {
      _listenForCallStatusChanges(callId);
    } else {
      _callState = CallState.error;
      notifyListeners();
      _autoResetAfterDelay();
    }
    return success;
  }

  /// End or decline the current call.
  Future<void> endCall({bool isDeclined = false}) async {
    await _callService.endCall(isDeclined: isDeclined);
    _stopDurationTimer();
    _callState = isDeclined ? CallState.declined : CallState.ended;
    notifyListeners();
    loadCallHistory();
  }

  /// Toggle microphone mute.
  Future<void> toggleMute() async {
    _isMuted = await _callService.toggleMute();
    notifyListeners();
  }

  /// Toggle speakerphone.
  Future<void> toggleSpeaker() async {
    _isSpeakerOn = await _callService.toggleSpeaker();
    notifyListeners();
  }

  // ── Call status listener ───────────────────────────────────────────────

  void _listenForCallStatusChanges(String callId) {
    _callStatusSubscription?.cancel();
    _callStatusSubscription =
        _callService.listenForCallStatusChanges(callId).listen((call) {
      _currentCall = call;

      switch (call.status) {
        case 'ringing':
          _callState = CallState.ringing;
          break;
        case 'ongoing':
          if (_callState != CallState.connected) {
            _callState = CallState.connected;
            _startDurationTimer();
          }
          break;
        case 'ended':
          _callState = CallState.ended;
          _stopDurationTimer();
          _autoResetAfterDelay();
          break;
        case 'declined':
          _callState = CallState.declined;
          _stopDurationTimer();
          _autoResetAfterDelay();
          break;
        case 'missed':
          _callState = CallState.missed;
          _stopDurationTimer();
          _autoResetAfterDelay();
          break;
        default:
          break;
      }
      notifyListeners();
    }, onError: (error) {
      debugPrint('Error in call status stream: $error');
      _callState = CallState.error;
      notifyListeners();
      _autoResetAfterDelay();
    });
  }

  // ── Duration timer ─────────────────────────────────────────────────────

  void _startDurationTimer() {
    _durationSeconds = 0;
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _durationSeconds++;
      notifyListeners();
    });
  }

  void _stopDurationTimer() {
    _durationTimer?.cancel();
  }

  /// Reset state to idle after a terminal status (ended/declined/missed).
  void _autoResetAfterDelay() {
    Future.delayed(const Duration(seconds: 3), () {
      if (_callState == CallState.ended ||
          _callState == CallState.declined ||
          _callState == CallState.missed ||
          _callState == CallState.error) {
        _callState = CallState.idle;
        _currentCall = null;
        _durationSeconds = 0;
        _isMuted = false;
        _isSpeakerOn = false;
        _callStatusSubscription?.cancel();
        notifyListeners();
      }
    });
  }

  // ── Call history ───────────────────────────────────────────────────────

  /// Load recent call history from Firestore (caller + receiver queries).
  Future<void> loadCallHistory() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _isLoadingHistory = true;
    notifyListeners();

    try {
      // Query calls where user is caller
      final callerSnapshot = await FirebaseFirestore.instance
          .collection('calls')
          .where('callerId', isEqualTo: user.uid)
          .orderBy('timestamp', descending: true)
          .limit(50)
          .get();

      // Query calls where user is receiver
      final receiverSnapshot = await FirebaseFirestore.instance
          .collection('calls')
          .where('receiverId', isEqualTo: user.uid)
          .orderBy('timestamp', descending: true)
          .limit(50)
          .get();

      // Merge and deduplicate
      final callMap = <String, Call>{};
      for (final doc in callerSnapshot.docs) {
        final call = Call.fromMap(doc.data());
        callMap[call.callId] = call;
      }
      for (final doc in receiverSnapshot.docs) {
        final call = Call.fromMap(doc.data());
        callMap[call.callId] = call;
      }

      // Sort by timestamp descending and limit
      final allCalls = callMap.values.toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      _callHistory = allCalls.take(50).toList();
    } catch (e) {
      debugPrint('Error loading call history: $e');
    } finally {
      _isLoadingHistory = false;
      notifyListeners();
    }
  }

  // ── Cleanup ────────────────────────────────────────────────────────────

  void _cleanup() {
    _incomingCallSubscription?.cancel();
    _callStatusSubscription?.cancel();
    _durationTimer?.cancel();
    _currentCall = null;
    _callState = CallState.idle;
    _callHistory = [];
    _durationSeconds = 0;
    _isMuted = false;
    _isSpeakerOn = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _incomingCallSubscription?.cancel();
    _callStatusSubscription?.cancel();
    _durationTimer?.cancel();
    super.dispose();
  }
}
