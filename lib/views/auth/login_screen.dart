import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chat_app/services/platform_helper.dart';
import 'package:flutter_chat_app/views/forgot_password_screen.dart';
import 'package:flutter_chat_app/widgets/custom_text_field.dart';
import 'package:flutter_chat_app/widgets/animations.dart';
import 'package:provider/provider.dart';
import 'package:flutter_chat_app/providers/theme_provider.dart';
import 'package:flutter_chat_app/providers/auth_provider.dart' as app_provider;
import 'package:flutter_chat_app/views/chat/chat_list_screen.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _isPasswordVisible = false;
  bool _disposed = false; // Track if widget is disposed

  // Animation controller for background
  late AnimationController _backgroundAnimationController;
  late Animation<double> _backgroundAnimation;

  @override
  void initState() {
    super.initState();

    // Initialize animation controller
    _backgroundAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    );

    _backgroundAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(_backgroundAnimationController);

    // Loop the animation
    _backgroundAnimationController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _backgroundAnimationController.dispose();
    _disposed = true; // Mark as disposed
    super.dispose();
  }

  // Safe setState that checks if widget is still mounted
  void _safeSetState(VoidCallback fn) {
    if (!_disposed && mounted) {
      setState(fn);
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final useAnimations = themeProvider.useAnimations;
    final primaryColor = themeProvider.primaryColor;
    final borderRadius = themeProvider.borderRadius;
    final isDarkMode = themeProvider.isDarkMode;

    return Scaffold(
      body: Stack(
        children: [
          // Animated background
          if (useAnimations)
            AnimatedBuilder(
              animation: _backgroundAnimation,
              builder: (context, child) {
                return Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        primaryColor.withOpacity(0.8),
                        primaryColor.withOpacity(0.3),
                      ],
                      stops: [
                        _backgroundAnimation.value * 0.3,
                        _backgroundAnimation.value * 0.9,
                      ],
                    ),
                  ),
                );
              },
            )
          else
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    primaryColor.withOpacity(0.8),
                    primaryColor.withOpacity(0.3),
                  ],
                ),
              ),
            ),

          // Login form
          Center(
            child: SingleChildScrollView(
              padding: PlatformHelper.isDesktop
                  ? const EdgeInsets.all(32.0)
                  : const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: PlatformHelper.isDesktop ? 400 : double.infinity,
                  ),
                  child: Card(
                    elevation: PlatformHelper.isDesktop ? 8.0 : 0.0,
                    shadowColor: primaryColor.withOpacity(0.4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(borderRadius),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          SlideIn.fromTop(
                            child: PulseAnimation(
                              repeat: false,
                              duration: const Duration(milliseconds: 1000),
                              child: Icon(
                                Icons.chat_bubble_outline,
                                size: 64,
                                color: primaryColor,
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          SlideIn(
                            delay: const Duration(milliseconds: 300),
                            child: const Text(
                              'Welcome Back',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          SlideIn(
                            delay: const Duration(milliseconds: 400),
                            child: Text(
                              'Log in to continue to Flutter Chat',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          const SizedBox(height: 32),
                          SlideIn(
                            delay: const Duration(milliseconds: 500),
                            child: CustomTextField(
                              hintText: 'Email',
                              controller: _emailController,
                              prefixIcon: Icons.email,
                              onChanged: (value) {
                                // email = value;
                              },
                              keyboardType: TextInputType.emailAddress,
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Email is required';
                                }
                                if (!value.contains('@') ||
                                    !value.contains('.')) {
                                  return 'Please enter a valid email';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(height: 20),
                          SlideIn(
                            delay: const Duration(milliseconds: 600),
                            child: CustomTextField(
                              hintText: 'Password',
                              controller: _passwordController,
                              obscureText: !_isPasswordVisible,
                              prefixIcon: Icons.lock,
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Password is required';
                                }
                                return null;
                              },
                              suffix: IconButton(
                                icon: Icon(
                                  _isPasswordVisible
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                  color: Colors.grey,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _isPasswordVisible = !_isPasswordVisible;
                                  });
                                },
                              ),
                              onChanged: (value) {
                                // password = value;
                              },
                            ),
                          ),
                          const SizedBox(height: 8),

                          // Forgot password
                          SlideIn(
                            delay: const Duration(milliseconds: 650),
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          const ForgotPasswordScreen(),
                                    ),
                                  );
                                },
                                child: Text(
                                  'Forgot Password?',
                                  style: TextStyle(
                                    color: primaryColor,
                                  ),
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 24),
                          SlideIn(
                            delay: const Duration(milliseconds: 700),
                            child: _isLoading
                                ? const Center(
                                    child: CircularProgressIndicator())
                                : ScaleButton(
                                    onTap: _attemptLogin,
                                    child: Container(
                                      height: 55,
                                      decoration: BoxDecoration(
                                        color: primaryColor,
                                        borderRadius:
                                            BorderRadius.circular(borderRadius),
                                        boxShadow: [
                                          BoxShadow(
                                            color:
                                                primaryColor.withOpacity(0.4),
                                            blurRadius: 10,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: Center(
                                        child: Text(
                                          'LOGIN',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                          ),
                          const SizedBox(height: 24),
                          SlideIn(
                            delay: const Duration(milliseconds: 800),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Divider(
                                    color: isDarkMode
                                        ? const Color(0xFF2C2C2C)
                                        : Colors.grey[300],
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16.0),
                                  child: Text(
                                    "OR",
                                    style: TextStyle(
                                      color: isDarkMode
                                          ? Colors.grey[400]
                                          : Colors.grey[600],
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Divider(
                                    color: isDarkMode
                                        ? const Color(0xFF2C2C2C)
                                        : Colors.grey[300],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                          SlideIn(
                            delay: const Duration(milliseconds: 900),
                            child: ScaleButton(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (context) => RegisterScreen()),
                                );
                              },
                              child: Container(
                                height: 55,
                                decoration: BoxDecoration(
                                  color: Colors.transparent,
                                  borderRadius:
                                      BorderRadius.circular(borderRadius),
                                  border: Border.all(
                                    color: primaryColor,
                                    width: 2,
                                  ),
                                ),
                                child: Center(
                                  child: Text(
                                    "CREATE ACCOUNT",
                                    style: TextStyle(
                                      color: primaryColor,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _attemptLogin() async {
    if (_formKey.currentState!.validate()) {
      _safeSetState(() {
        _isLoading = true;
      });

      try {
        print('📝 Login attempt with email: ${_emailController.text.trim()}');

        // Use AuthProvider instead of AuthService directly
        final authProvider =
            Provider.of<app_provider.AuthProvider>(context, listen: false);
        final success = await authProvider.signIn(
            _emailController.text.trim(), _passwordController.text.trim());

        if (success) {
          print('✅ Login successful');

          // Use Navigator.pop instead of pushReplacement to return to the AuthenticationWrapper
          // which will detect the auth state change and show the ChatListScreen
          if (mounted) {
            print(
                '🔄 Returning to auth wrapper to detect authentication state change');
            // Check current user again to make sure authentication persisted
            final currentUser = FirebaseAuth.instance.currentUser;
            if (currentUser != null) {
              print('✓ User still authenticated: ${currentUser.uid}');
              // Simply pop the login screen and let the AuthenticationWrapper handle navigation
              Navigator.pop(context);
            } else {
              print(
                  '❌ Authentication lost after login - forcing navigation to ChatListScreen');
              // Fallback if authentication state is not maintained
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => ChatListScreen()),
              );
            }
          }
        } else {
          print('❌ Login returned failure');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(authProvider.errorMessage ??
                    'Login failed - please check your credentials'),
              ),
            );
          }
        }
      } catch (e) {
        print('❌ Login error: ${e.toString()}');

        // Check for unsupported operations error (Windows)
        if (e.toString().contains('Unsupported operation')) {
          print(
              '⚠️ Detected unsupported operation, routing to ChatListScreen as fallback');
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => ChatListScreen()),
            );
          }
        } else if (e.toString().contains('user-not-found') ||
            e.toString().contains('wrong-password')) {
          // Handle common auth errors
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Invalid email or password')),
            );
          }
        } else {
          // Handle other errors
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error: ${e.toString()}')),
            );
          }
        }
      } finally {
        if (mounted) {
          _safeSetState(() {
            _isLoading = false;
          });
        }
      }
    }
  }
}
