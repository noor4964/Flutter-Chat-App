import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/calls/call_diagnostics.dart';
import '../../services/calls/call_service.dart';
import '../../services/platform_helper.dart';

class CallStatsOverlay extends StatefulWidget {
  final CallService callService;
  final bool showDetailedStats;
  final bool autoHide;
  final VoidCallback? onFixAttempted;

  const CallStatsOverlay({
    Key? key,
    required this.callService,
    this.showDetailedStats = false,
    this.autoHide = true,
    this.onFixAttempted,
  }) : super(key: key);

  @override
  State<CallStatsOverlay> createState() => _CallStatsOverlayState();
}

class _CallStatsOverlayState extends State<CallStatsOverlay> {
  Timer? _refreshTimer;
  Map<String, dynamic>? _diagnosticData;
  bool _isExpanded = false;
  bool _isLoading = false;
  bool _showOverlay = true;
  Timer? _hideTimer;

  late CallDiagnostics _callDiagnostics;

  @override
  void initState() {
    super.initState();
    _callDiagnostics = CallDiagnostics(widget.callService);
    _refreshDiagnostics();
    
    // Set up timer to refresh diagnostics every 5 seconds
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) {
        _refreshDiagnostics();
      }
    });

    if (widget.autoHide) {
      _scheduleHide();
    }
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 10), () {
      if (mounted) {
        setState(() {
          _showOverlay = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _hideTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshDiagnostics() async {
    if (_isLoading) return;
    
    setState(() {
      _isLoading = true;
    });

    try {
      final diagnostics = await _callDiagnostics.runDiagnostics();
      if (mounted) {
        setState(() {
          _diagnosticData = diagnostics;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _diagnosticData = {'error': e.toString()};
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _attemptToFixAudioIssues() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Attempt to fix audio issues by optimizing web audio if on web platform
      if (PlatformHelper.isWeb) {
        // Call the web-specific fix from CallService
        await widget.callService.fixVoiceIssues();
      } else {
        // For mobile/desktop, try to reset audio routing
        final engine = widget.callService.getAgoraEngine();
        if (engine != null) {
          await engine.enableLocalAudio(false);
          await Future.delayed(const Duration(milliseconds: 500));
          await engine.enableLocalAudio(true);
        }
      }

      if (widget.onFixAttempted != null) {
        widget.onFixAttempted!();
      }

      // Refresh the stats after fix attempt
      _refreshDiagnostics();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error fixing audio: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_showOverlay) {
      return Positioned(
        top: 40,
        right: 10,
        child: GestureDetector(
          onTap: () {
            setState(() {
              _showOverlay = true;
              if (widget.autoHide) {
                _scheduleHide();
              }
            });
          },
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
      child: GestureDetector(
        onTap: () {
          if (widget.autoHide) {
            _scheduleHide();
          }
          setState(() {
            _isExpanded = !_isExpanded;
          });
        },
        child: Container(
          width: _isExpanded ? 220 : 120,
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
                    'Call Stats',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () {
                          _refreshDiagnostics();
                          if (widget.autoHide) {
                            _scheduleHide();
                          }
                        },
                        child: Icon(
                          Icons.refresh,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _showOverlay = false;
                          });
                        },
                        child: Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8.0),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              if (!_isLoading && _diagnosticData != null) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Platform:',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      _diagnosticData!['platform'] ?? 'unknown',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Engine:',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      _diagnosticData!['engineInitialized'] ? 'Ready' : 'Not Ready',
                      style: TextStyle(
                        color: _diagnosticData!['engineInitialized'] ? Colors.green : Colors.red,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                if (_isExpanded && _diagnosticData!['webSpecificChecks'] != null) ...[
                  const SizedBox(height: 8),
                  const Divider(color: Colors.white30, height: 1),
                  const SizedBox(height: 8),
                  Text(
                    'Web Audio Diagnostics',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  _buildAudioTestStatus(),
                ],
                const SizedBox(height: 8),
                Center(
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _attemptToFixAudioIssues,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      minimumSize: const Size(120, 30),
                    ),
                    child: Text(
                      'Fix Audio',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
              if (!_isLoading && _diagnosticData == null)
                const Text(
                  'No data available',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAudioTestStatus() {
    final webChecks = _diagnosticData!['webSpecificChecks'];
    if (webChecks == null) return const SizedBox.shrink();
    
    final audioTest = webChecks['audioTest'];
    if (audioTest == null) return const SizedBox.shrink();
    
    final bool microphoneAccessible = audioTest['microphoneAccessible'] ?? false;
    final bool speakerAccessible = audioTest['speakerAccessible'] ?? false;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Microphone:',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 12,
              ),
            ),
            Row(
              children: [
                Icon(
                  microphoneAccessible ? Icons.check_circle : Icons.error,
                  color: microphoneAccessible ? Colors.green : Colors.red,
                  size: 14,
                ),
                const SizedBox(width: 4),
                Text(
                  microphoneAccessible ? 'OK' : 'Issue',
                  style: TextStyle(
                    color: microphoneAccessible ? Colors.green : Colors.red,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Speaker:',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 12,
              ),
            ),
            Row(
              children: [
                Icon(
                  speakerAccessible ? Icons.check_circle : Icons.error,
                  color: speakerAccessible ? Colors.green : Colors.red,
                  size: 14,
                ),
                const SizedBox(width: 4),
                Text(
                  speakerAccessible ? 'OK' : 'Issue',
                  style: TextStyle(
                    color: speakerAccessible ? Colors.green : Colors.red,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}