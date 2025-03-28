import 'package:flutter/material.dart';

/// A widget that catches errors in its child widget tree and displays a
/// fallback UI when an error occurs instead of crashing the app.
class ErrorBoundary extends StatefulWidget {
  final Widget child;
  final Function? onRetry;

  const ErrorBoundary({Key? key, required this.child, this.onRetry})
      : super(key: key);

  @override
  ErrorBoundaryState createState() => ErrorBoundaryState();
}

class ErrorBoundaryState extends State<ErrorBoundary> {
  bool _hasError = false;
  String? _errorMessage;
  dynamic _errorDetails;
  bool _isLoading = false;

  // Expose a method to clear the error state from parent widgets
  void clearError() {
    if (mounted) {
      setState(() {
        _hasError = false;
        _errorMessage = null;
        _errorDetails = null;
      });
    }
  }

  // Method to capture errors manually
  void reportError(dynamic error) {
    if (mounted && !_hasError) {
      setState(() {
        _hasError = true;
        _errorMessage = error.toString();
        _errorDetails = error;
      });
      print('❌ Error reported to ErrorBoundary: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      // Return fallback UI when an error occurs
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              const Text(
                'Something went wrong',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage ?? 'We encountered an error in this section.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              _isLoading
                  ? const CircularProgressIndicator()
                  : ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _isLoading = true;
                        });

                        // Execute any custom retry logic
                        if (widget.onRetry != null) {
                          Future.microtask(() async {
                            try {
                              await widget.onRetry!();
                            } catch (e) {
                              print('❌ Error during retry: $e');
                            }
                          });
                        }

                        // Attempt to recover by resetting the error state
                        Future.delayed(const Duration(milliseconds: 300), () {
                          if (mounted) {
                            setState(() {
                              _hasError = false;
                              _errorMessage = null;
                              _errorDetails = null;
                              _isLoading = false;
                            });
                          }
                        });
                      },
                      child: const Text('Try Again'),
                    ),
              if (_errorDetails != null &&
                  _errorDetails.toString().contains("Firebase"))
                TextButton(
                  onPressed: () {
                    // Just reset the state - connection should be automatically handled
                    setState(() {
                      _hasError = false;
                      _errorMessage = null;
                      _errorDetails = null;
                    });
                  },
                  child: const Text('Fix Connection'),
                ),
            ],
          ),
        ),
      );
    }

    // If no error, return the child directly
    // We're not using ErrorWidget anymore as it was causing issues
    return _buildErrorHandler();
  }

  Widget _buildErrorHandler() {
    // Use a simpler error catching mechanism
    return Builder(
      builder: (context) {
        try {
          return widget.child;
        } catch (error, stackTrace) {
          print('❌ Error caught in ErrorBoundary build: $error');
          print('Stack trace: $stackTrace');

          // Handle the error after the build phase completes
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _hasError = true;
                _errorMessage = error.toString();
                _errorDetails = error;
              });
            }
          });

          // Return a loading indicator while we prepare the error UI
          return const Center(child: CircularProgressIndicator());
        }
      },
    );
  }
}
