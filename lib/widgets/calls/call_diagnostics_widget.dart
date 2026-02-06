import 'package:flutter/material.dart';
import 'package:flutter_chat_app/services/calls/call_service.dart';
import 'package:flutter_chat_app/services/platform_helper.dart';

/// Simple widget to display audio diagnostics and provide fixes for call issues
class CallDiagnosticsWidget extends StatefulWidget {
  final CallService callService;
  final bool autoHide;
  
  const CallDiagnosticsWidget({
    Key? key,
    required this.callService,
    this.autoHide = true,
  }) : super(key: key);

  @override
  State<CallDiagnosticsWidget> createState() => _CallDiagnosticsWidgetState();
}

class _CallDiagnosticsWidgetState extends State<CallDiagnosticsWidget> {
  bool _showDiagnostics = false;
  bool _isFixing = false;
  
  @override
  Widget build(BuildContext context) {
    if (!_showDiagnostics) {
      // Show a small icon that can be tapped to expand
      return Positioned(
        top: 40,
        right: 10,
        child: GestureDetector(
          onTap: () => setState(() => _showDiagnostics = true),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.info_outline,
              color: Colors.white,
              size: 24,
            ),
          ),
        ),
      );
    }
    
    return Positioned(
      top: 40,
      right: 10,
      child: Container(
        width: 200,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Call Diagnostics',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                GestureDetector(
                  onTap: () => setState(() => _showDiagnostics = false),
                  child: const Icon(
                    Icons.close,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            
            Text(
              'Platform: ${PlatformHelper.isWeb ? 'Web' : PlatformHelper.isAndroid ? 'Android' : PlatformHelper.isIOS ? 'iOS' : 'Desktop'}',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
              ),
            ),
            
            const SizedBox(height: 4),
            
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Audio status:',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
                _buildStatusIndicator(),
              ],
            ),
            
            const SizedBox(height: 8),
            
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isFixing ? null : _attemptToFixAudio,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
                child: _isFixing 
                    ? const SizedBox(
                        width: 16, 
                        height: 16, 
                        child: CircularProgressIndicator(
                          strokeWidth: 2, 
                          color: Colors.white,
                        )
                      )
                    : const Text('Fix Audio'),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildStatusIndicator() {
    final bool isAudioWorking = widget.callService.isAudioWorking();
    
    return Row(
      children: [
        Icon(
          isAudioWorking ? Icons.check_circle : Icons.warning,
          color: isAudioWorking ? Colors.green : Colors.orange,
          size: 14,
        ),
        const SizedBox(width: 4),
        Text(
          isAudioWorking ? 'OK' : 'Issues',
          style: TextStyle(
            color: isAudioWorking ? Colors.green : Colors.orange,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
  
  Future<void> _attemptToFixAudio() async {
    if (_isFixing) return;
    
    setState(() {
      _isFixing = true;
    });
    
    try {
      await widget.callService.fixVoiceIssues();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Audio fix attempted'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isFixing = false;
        });
      }
    }
  }
}