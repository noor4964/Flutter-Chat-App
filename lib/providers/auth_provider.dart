import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chat_app/services/auth_service.dart';

enum AuthStatus {
  initial,
  authenticating,
  authenticated,
  unauthenticated,
  error
}

class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();
  AuthStatus _status = AuthStatus.initial;
  String? _errorMessage;
  bool _isLoading = false;

  // Getters
  AuthStatus get status => _status;
  String? get errorMessage => _errorMessage;
  bool get isLoading => _isLoading;
  User? get currentUser => _authService.getCurrentUser();
  bool get isLoggedIn => _authService.isUserLoggedIn();
  Stream<User?> get userStream => _authService.userStream;

  // Sign in with email and password
  Future<bool> signIn(String email, String password) async {
    _status = AuthStatus.authenticating;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final user =
          await _authService.signInWithEmailAndPassword(email, password);
      _status =
          user != null ? AuthStatus.authenticated : AuthStatus.unauthenticated;
      _isLoading = false;
      notifyListeners();
      return user != null;
    } catch (e) {
      _status = AuthStatus.error;
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // Register with email and password
  Future<bool> register(
      String username, String email, String password, String gender) async {
    _status = AuthStatus.authenticating;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final user = await _authService.registerWithEmailAndPassword(
          username, email, password, gender);
      _status =
          user != null ? AuthStatus.authenticated : AuthStatus.unauthenticated;
      _isLoading = false;
      notifyListeners();
      return user != null;
    } catch (e) {
      _status = AuthStatus.error;
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // Sign out
  Future<void> signOut() async {
    _isLoading = true;
    notifyListeners();

    try {
      await _authService.signOut();
      _status = AuthStatus.unauthenticated;
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _status = AuthStatus.error;
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }

  // Send password reset email
  Future<bool> sendPasswordResetEmail(String email) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _authService.sendPasswordResetEmail(email);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // Reset error message
  void resetError() {
    _errorMessage = null;
    notifyListeners();
  }
}
