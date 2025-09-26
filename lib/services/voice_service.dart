import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

class VoiceService {
  FlutterSoundPlayer? _player;
  FlutterSoundRecorder? _recorder;
  bool _isRecording = false;
  bool _isPlaying = false;
  String? _currentRecordingPath;
  DateTime? _recordingStartTime;
  double _playbackSpeed = 1.0; // Default playback speed

  VoiceService() {
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    _player = FlutterSoundPlayer();
    _recorder = FlutterSoundRecorder();

    await _player!.openPlayer();
    await _recorder!.openRecorder();
  }

  Future<bool> _requestPermissions() async {
    final microphoneStatus = await Permission.microphone.request();
    return microphoneStatus == PermissionStatus.granted;
  }

  Future<String?> startRecording() async {
    if (!await _requestPermissions()) {
      return null;
    }

    try {
      final directory = await getApplicationDocumentsDirectory();
      final fileName = 'voice_${DateTime.now().millisecondsSinceEpoch}.aac';
      _currentRecordingPath = '${directory.path}/$fileName';

      // Store recording start time
      _recordingStartTime = DateTime.now();

      await _recorder!.startRecorder(
        toFile: _currentRecordingPath,
        codec: Codec.aacADTS,
      );

      _isRecording = true;
      return _currentRecordingPath;
    } catch (e) {
      print('Error starting recording: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> stopRecording() async {
    if (!_isRecording) return null;

    try {
      await _recorder!.stopRecorder();
      _isRecording = false;
      
      // Calculate actual recording duration
      int durationMs = 0;
      if (_recordingStartTime != null) {
        durationMs = DateTime.now().difference(_recordingStartTime!).inMilliseconds;
      }
      
      return {
        'path': _currentRecordingPath,
        'duration': durationMs,
      };
    } catch (e) {
      print('Error stopping recording: $e');
      return null;
    }
  }

  Future<void> playVoiceMessage(String filePath) async {
    if (_isPlaying) {
      await stopPlaying();
    }

    try {
      await _player!.startPlayer(
        fromURI: filePath,
        codec: Codec.aacADTS,
        whenFinished: () {
          _isPlaying = false;
        },
      );
      
      // Set playback speed
      await _player!.setSpeed(_playbackSpeed);
      
      _isPlaying = true;
    } catch (e) {
      print('Error playing voice message: $e');
    }
  }

  Future<void> stopPlaying() async {
    if (_player != null && _isPlaying) {
      await _player!.stopPlayer();
      _isPlaying = false;
    }
  }

  // Set playback speed (1.0 = normal, 1.5 = 1.5x, 2.0 = 2x)
  Future<void> setPlaybackSpeed(double speed) async {
    _playbackSpeed = speed;
    if (_isPlaying && _player != null) {
      await _player!.setSpeed(speed);
    }
  }

  // Get current playback speed
  double get playbackSpeed => _playbackSpeed;

  // Cycle through playback speeds (1.0x -> 1.5x -> 2.0x -> 1.0x)
  Future<double> cyclePlaybackSpeed() async {
    if (_playbackSpeed == 1.0) {
      await setPlaybackSpeed(1.5);
    } else if (_playbackSpeed == 1.5) {
      await setPlaybackSpeed(2.0);
    } else {
      await setPlaybackSpeed(1.0);
    }
    return _playbackSpeed;
  }

  Future<int?> getAudioDuration(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        // Use flutter_sound to get actual duration
        final duration = await _player!.startPlayer(
          fromURI: filePath,
          codec: Codec.aacADTS,
        );
        await _player!.stopPlayer();
        return duration?.inMilliseconds;
      }
    } catch (e) {
      print('Error getting audio duration: $e');
    }
    return null;
  }

  bool get isRecording => _isRecording;
  bool get isPlaying => _isPlaying;

  void dispose() {
    _player?.closePlayer();
    _recorder?.closeRecorder();
  }
}