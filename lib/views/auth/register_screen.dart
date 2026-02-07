import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_chat_app/providers/auth_provider.dart' as app_provider;
import 'package:flutter_chat_app/widgets/custom_text_field.dart';
import 'package:flutter_chat_app/widgets/animations.dart';
import 'package:provider/provider.dart';
import 'package:flutter_chat_app/providers/theme_provider.dart';
import 'package:flutter_chat_app/services/platform_helper.dart';
import 'login_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  _RegisterScreenState createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  String username = '';
  String email = '';
  String password = '';
  String confirmPassword = '';
  String gender = '';
  bool _isLoading = false;
  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;
  bool _disposed = false; // Track disposal state

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

    _backgroundAnimation = Tween<double>(begin: 0.0, end: 1.0)
        .animate(_backgroundAnimationController);

    // Loop the animation
    _backgroundAnimationController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
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

          // Registration form
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
                                Icons.person_add,
                                size: 64,
                                color: primaryColor,
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          SlideIn(
                            delay: const Duration(milliseconds: 300),
                            child: const Text(
                              'Create Account',
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
                              'Register to join Flutter Chat',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          const SizedBox(height: 32),

                          // Username field
                          SlideIn(
                            delay: const Duration(milliseconds: 500),
                            child: CustomTextField(
                              hintText: 'Username',
                              controller: _usernameController,
                              prefixIcon: Icons.person,
                              onChanged: (value) {
                                username = value;
                              },
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Email field
                          SlideIn(
                            delay: const Duration(milliseconds: 550),
                            child: CustomTextField(
                              hintText: 'Email',
                              controller: _emailController,
                              prefixIcon: Icons.email,
                              keyboardType: TextInputType.emailAddress,
                              onChanged: (value) {
                                email = value;
                              },
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Password field
                          SlideIn(
                            delay: const Duration(milliseconds: 600),
                            child: CustomTextField(
                              hintText: 'Password',
                              controller: _passwordController,
                              obscureText: !_isPasswordVisible,
                              prefixIcon: Icons.lock,
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
                                password = value;
                              },
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Confirm Password field
                          SlideIn(
                            delay: const Duration(milliseconds: 650),
                            child: CustomTextField(
                              hintText: 'Confirm Password',
                              controller: _confirmPasswordController,
                              obscureText: !_isConfirmPasswordVisible,
                              prefixIcon: Icons.lock,
                              suffix: IconButton(
                                icon: Icon(
                                  _isConfirmPasswordVisible
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                  color: Colors.grey,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _isConfirmPasswordVisible =
                                        !_isConfirmPasswordVisible;
                                  });
                                },
                              ),
                              onChanged: (value) {
                                confirmPassword = value;
                              },
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Gender dropdown
                          SlideIn(
                            delay: const Duration(milliseconds: 700),
                            child: DropdownButtonFormField<String>(
                              decoration: InputDecoration(
                                hintText: 'Gender',
                                prefixIcon: const Icon(Icons.person),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12.0),
                                  borderSide: const BorderSide(
                                      color: Colors.pinkAccent),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12.0),
                                  borderSide: const BorderSide(
                                      color: Colors.pinkAccent),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12.0),
                                  borderSide: const BorderSide(
                                      color: Colors.pinkAccent),
                                ),
                                filled: true,
                                fillColor: Colors.transparent,
                                contentPadding: const EdgeInsets.symmetric(
                                    vertical: 16.0, horizontal: 20.0),
                              ),
                              items: ['Male', 'Female', 'Other']
                                  .map((String value) {
                                return DropdownMenuItem<String>(
                                  value: value,
                                  child: Text(value),
                                );
                              }).toList(),
                              onChanged: (value) {
                                gender = value!;
                              },
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Register button
                          SlideIn(
                            delay: const Duration(milliseconds: 750),
                            child: _isLoading
                                ? const Center(
                                    child: CircularProgressIndicator())
                                : ScaleButton(
                                    onTap: () async {
                                      if (_formKey.currentState!.validate()) {
                                        if (password == confirmPassword) {
                                          _safeSetState(() {
                                            _isLoading = true;
                                          });

                                          try {
                                            // Use AuthProvider instead of AuthService directly
                                            final authProvider = Provider.of<
                                                    app_provider.AuthProvider>(
                                                context,
                                                listen: false);
                                            final success =
                                                await authProvider.register(
                                                    username,
                                                    email,
                                                    password,
                                                    gender);

                                            if (success && mounted) {
                                              print(
                                                  'User registered successfully');
                                              Navigator.pushReplacement(
                                                context,
                                                MaterialPageRoute(
                                                    builder: (context) =>
                                                        LoginScreen()),
                                              );
                                            } else if (mounted) {
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                SnackBar(
                                                    content: Text(authProvider
                                                            .errorMessage ??
                                                        'Registration failed')),
                                              );
                                            }
                                          } catch (e) {
                                            print(
                                                'Error during registration: $e');
                                            if (mounted) {
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                SnackBar(
                                                    content: Text('Error: $e')),
                                              );
                                            }
                                          } finally {
                                            _safeSetState(() {
                                              _isLoading = false;
                                            });
                                          }
                                        } else if (mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            const SnackBar(
                                                content: Text(
                                                    'Passwords do not match')),
                                          );
                                        }
                                      }
                                    },
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
                                      child: const Center(
                                        child: Text(
                                          'REGISTER',
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

                          // Back to login button
                          SlideIn(
                            delay: const Duration(milliseconds: 850),
                            child: ScaleButton(
                              onTap: () {
                                Navigator.pushReplacement(
                                  context,
                                  MaterialPageRoute(
                                      builder: (context) => LoginScreen()),
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
                                    "BACK TO LOGIN",
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
}
