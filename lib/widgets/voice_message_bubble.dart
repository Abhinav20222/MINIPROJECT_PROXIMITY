import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:offgrid/models/message.dart';
import 'dart:async';

class VoiceMessageBubble extends StatefulWidget {
  final Message message;
  final bool isMe;
  final VoidCallback? onPlay;
  final bool isPlaying;
  final double playbackSpeed;
  final VoidCallback? onSpeedChange;

  const VoiceMessageBubble({
    Key? key,
    required this.message,
    required this.isMe,
    this.onPlay,
    this.isPlaying = false,
    this.playbackSpeed = 1.0,
    this.onSpeedChange,
  }) : super(key: key);

  @override
  String toString({DiagnosticLevel minLevel = DiagnosticLevel.info}) {
    return 'VoiceMessageBubble(messageId: ${message.id}, isPlaying: $isPlaying, speed: $playbackSpeed)';
  }

  @override
  State<VoiceMessageBubble> createState() => _VoiceMessageBubbleState();
}

class _VoiceMessageBubbleState extends State<VoiceMessageBubble> with SingleTickerProviderStateMixin {
  late AnimationController _waveAnimationController;
  Timer? _progressTimer;
  double _currentPosition = 0.0;
  double _progress = 0.0;

  @override
  void initState() {
    super.initState();
    _waveAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
  }

  @override
  void didUpdateWidget(VoiceMessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    if (widget.isPlaying && !oldWidget.isPlaying) {
      _startPlayback();
    } else if (!widget.isPlaying && oldWidget.isPlaying) {
      _stopPlayback();
    }
  }

  void _startPlayback() {
    _waveAnimationController.repeat();
    
    _progressTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (mounted) {
        setState(() {
          _currentPosition += 100 * widget.playbackSpeed;
          final duration = widget.message.voiceDurationMs ?? 1000;
          _progress = (_currentPosition / duration).clamp(0.0, 1.0);
          
          if (_currentPosition >= duration) {
            _stopPlayback();
            _currentPosition = 0;
            _progress = 0.0;
          }
        });
      }
    });
  }

  void _stopPlayback() {
    _waveAnimationController.stop();
    _progressTimer?.cancel();
    
    if (!widget.isPlaying) {
      setState(() {
        _currentPosition = 0;
        _progress = 0.0;
      });
    }
  }

  @override
  void dispose() {
    _waveAnimationController.dispose();
    _progressTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final formattedTime = DateFormat('HH:mm').format(widget.message.timestamp);
    final duration = widget.message.voiceDurationMs ?? 0;
    final remainingTime = duration - _currentPosition.toInt();
    final durationText = _formatDuration(widget.isPlaying ? remainingTime : duration);

    Widget statusIcon = const SizedBox.shrink();
    if (widget.isMe) {
      if (widget.message.status == MessageStatus.read) {
        statusIcon = const Icon(Icons.done_all, size: 16, color: Colors.lightBlueAccent);
      } else if (widget.message.status == MessageStatus.delivered) {
        statusIcon = const Icon(Icons.done_all, size: 16, color: Colors.white70);
      } else {
        statusIcon = const Icon(Icons.done, size: 16, color: Colors.white70);
      }
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
      child: Row(
        mainAxisAlignment: widget.isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75,
              minWidth: 200,
            ),
            decoration: BoxDecoration(
              color: widget.isMe ? Colors.blue : Colors.grey[700],
              borderRadius: BorderRadius.circular(20.0),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: widget.onPlay,
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          widget.isPlaying ? Icons.pause : Icons.play_arrow,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    
                    Expanded(
                      child: Container(
                        height: 30,
                        alignment: Alignment.center,
                        child: _buildWaveformBars(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    
                    GestureDetector(
                      onTap: widget.onSpeedChange,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${widget.playbackSpeed}x',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 48),
                      child: Text(
                        durationText,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                    
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          formattedTime,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 10,
                          ),
                        ),
                        if (widget.isMe) const SizedBox(width: 4),
                        if (widget.isMe) statusIcon,
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWaveformBars() {
    // Static base heights for bars
    final baseHeights = [0.4, 0.7, 0.5, 0.9, 0.6, 0.8, 0.5, 0.7, 0.6, 0.8, 0.4, 0.9, 0.5, 0.7, 0.6, 0.8, 0.5, 0.7];
    
    return AnimatedBuilder(
      animation: _waveAnimationController,
      builder: (context, child) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: List.generate(18, (index) {
            double barHeight = baseHeights[index % baseHeights.length];
            
            // Simple animation when playing - just pulse all bars slightly
            if (widget.isPlaying) {
              final pulse = 0.85 + 0.15 * _waveAnimationController.value;
              barHeight = (barHeight * pulse).clamp(0.3, 1.0);
            }
            
            // Determine if this bar has been "played"
            final barProgress = index / 18.0;
            final isPassed = barProgress <= _progress;
            
            // Simple color logic - no complex opacity calculations
            final Color barColor;
            if (isPassed) {
              barColor = widget.isMe ? Colors.white : Colors.lightBlueAccent;
            } else {
              barColor = Colors.white30;
            }
            
            return Container(
              width: 3,
              height: 24 * barHeight,
              decoration: BoxDecoration(
                color: barColor,
                borderRadius: BorderRadius.circular(2),
              ),
            );
          }),
        );
      },
    );
  }

  String _formatDuration(int milliseconds) {
    final duration = Duration(milliseconds: milliseconds.abs());
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(1, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}