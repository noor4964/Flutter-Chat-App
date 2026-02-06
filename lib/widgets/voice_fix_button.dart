import 'package:flutter/material.dart';
import '../utils/voice_call_fixer.dart';

/// A widget that provides a button to fix voice transmission issues
class VoiceFixButton extends StatefulWidget {
  /// The color of the button
  final Color? color;
  
  /// The text to display on the button
  final String? text;
  
  /// Tooltip text for better accessibility and UX
  final String? tooltip;

  const VoiceFixButton({
    super.key, 
    this.color,
    this.text,
    this.tooltip,
  });

  @override
  State<VoiceFixButton> createState() => _VoiceFixButtonState();
}

class _VoiceFixButtonState extends State<VoiceFixButton> with SingleTickerProviderStateMixin {
  bool _isFixing = false;
  bool _showSuccess = false;
  bool _showFailure = false;
  
  // Animation controller for the pulsing effect
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  
  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..repeat(reverse: true);
    
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut)
    );
  }
  
  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }
  
  Future<void> _fixVoiceTransmission() async {
    if (_isFixing) return;
    
    setState(() {
      _isFixing = true;
      _showSuccess = false;
      _showFailure = false;
    });
    
    try {
      final success = await VoiceCallFixer.checkAndFixVoiceTransmission();
      
      setState(() {
        _isFixing = false;
        _showSuccess = success;
        _showFailure = !success;
      });
      
      // Auto-hide the status after a few seconds
      if (mounted) {
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) {
            setState(() {
              _showSuccess = false;
              _showFailure = false;
            });
          }
        });
      }
    } catch (e) {
      setState(() {
        _isFixing = false;
        _showFailure = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color buttonColor = widget.color ?? Theme.of(context).primaryColor;
    final String tooltipText = widget.tooltip ?? 'Fix audio issues if you cannot hear others or they cannot hear you';
    
    // Wrap the button in an animated builder to apply the pulse animation when needed
    Widget button = ElevatedButton.icon(
      icon: _isFixing 
        ? const SizedBox(
            width: 16, 
            height: 16, 
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          )
        : Icon(
            _showSuccess ? Icons.check_circle : 
            _showFailure ? Icons.error_outline : 
            Icons.mic_none,
          ),
      label: Text(
        _isFixing ? 'Fixing...' :
        _showSuccess ? 'Fixed!' :
        _showFailure ? 'Try Again' :
        widget.text ?? 'Fix Audio',
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      onPressed: _isFixing ? null : _fixVoiceTransmission,
      style: ElevatedButton.styleFrom(
        backgroundColor: _showSuccess ? Colors.green : 
                         _showFailure ? Colors.orange : 
                         buttonColor,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
    );
    
    // Apply pulsing animation only when not fixing and not showing status
    if (!_isFixing && !_showSuccess && !_showFailure) {
      button = AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: child,
          );
        },
        child: button,
      );
    }
    
    // Wrap in a tooltip for better UX
    button = Tooltip(
      message: tooltipText,
      child: button,
    );
    
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        button,
        if (_showFailure)
          const Padding(
            padding: EdgeInsets.only(top: 8.0),
            child: Text(
              'Could not fix audio. Try again.',
              style: TextStyle(color: Colors.red, fontSize: 12),
            ),
          ),
      ],
    );
  }
}