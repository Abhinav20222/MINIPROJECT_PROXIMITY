import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:offgrid/models/message.dart';
import 'package:offgrid/services/encryption_service.dart';
import 'package:offgrid/utils/app_state.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import '../services/voice_service.dart';
import '../widgets/voice_message_bubble.dart';
import '../widgets/voice_recording_widget.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:math' as math;

class ChatScreen extends StatefulWidget {
  final String peerId;
  final String peerName;
  final String? peerAvatar;

  const ChatScreen({
    super.key,
    required this.peerId,
    required this.peerName,
    this.peerAvatar,
  });

  @override
  ChatScreenState createState() => ChatScreenState();
}

class ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin {
  final TextEditingController _messageController = TextEditingController();
  final List<Message> _messages = [];
  final ScrollController _scrollController = ScrollController();
  final Set<String> _markedAsReadMessageIds = {};
  final Set<String> _pendingReadReceipts = {};
  Timer? _readReceiptBatchTimer;

  late final AppState appState;
  StreamSubscription<Message>? _messageSubscription;

  late VoiceService _voiceService;
  bool _showVoiceRecording = false;
  String? _currentlyPlayingMessageId;
  double _playbackSpeed = 1.0;

  bool _isPeerTyping = false;
  Timer? _typingTimer;
  bool _amITyping = false;

  bool _isPeerRecording = false;
  bool _amIRecording = false;
  bool _isConnected = false;

  late AnimationController _typingAnimController;
  late AnimationController _recordingAnimController;

  @override
  void initState() {
    super.initState();
    appState = Provider.of<AppState>(context, listen: false);

    appState.setCurrentlyOpenChat(widget.peerName);
    print('🟢 ChatScreen: Set currently open chat to ${widget.peerName}');

    _voiceService = VoiceService();
    _loadMessages();
    _checkConnectionStatus();

    _typingAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    _recordingAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _messageSubscription = appState.onMessageReceived.listen((message) {
      if (message.senderId == widget.peerName && mounted) {
        setState(() {
          _messages.insert(0, message);
        });
      }
    });

    _subscribeToServiceEvents();
    _messageController.addListener(_onTextChanged);
  }

  void _checkConnectionStatus() {
    setState(() {
      _isConnected =
          appState.nearbyService?.isEndpointConnected(widget.peerId) ?? false;
    });
  }

  void _subscribeToServiceEvents() {
    appState.nearbyService?.onTypingStatusChanged = (status) {
      if (mounted && status['endpointId'] == widget.peerId) {
        setState(() {
          _isPeerTyping = status['isTyping'] as bool;
        });
      }
    };

    appState.nearbyService?.onRecordingStatusChanged = (status) {
      if (mounted && status['endpointId'] == widget.peerId) {
        setState(() {
          _isPeerRecording = status['isRecording'] as bool;
        });
      }
    };

    appState.nearbyService?.onMessageRead = (receipt) {
      if (mounted && receipt['endpointId'] == widget.peerId) {
        final messageId = receipt['messageId'] as String;
        _updateMessageStatus(messageId, MessageStatus.read);
      }
    };

    appState.nearbyService?.onMessageDeleted = (deleteEvent) {
      if (mounted && deleteEvent['endpointId'] == widget.peerId) {
        final messageId = deleteEvent['messageId'] as String;
        _handleRemoteMessageDeletion(messageId);
      }
    };

    appState.nearbyService?.onConnectionResult = (result) {
      if (mounted && result['endpointId'] == widget.peerId) {
        final status = result['status'] as String?;
        setState(() {
          _isConnected = status == 'connected';
        });
      }
    };

    appState.nearbyService?.onDisconnected = (endpointId) {
      if (mounted && endpointId == widget.peerId) {
        setState(() {
          _isConnected = false;
        });

        if (ScaffoldMessenger.of(context).mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("${widget.peerName} disconnected - view only mode"),
              duration: const Duration(seconds: 3),
              backgroundColor: Colors.orange.shade800,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              action: SnackBarAction(
                label: 'Close',
                textColor: Colors.white,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          );
        }
      }
    };
  }

  void _handleRemoteMessageDeletion(String messageId) {
    final index = _messages.indexWhere((msg) => msg.id == messageId);
    if (index != -1) {
      appState.sqliteService.deleteMessage(messageId);
      if (mounted) {
        setState(() {
          _messages.removeAt(index);
        });
      }
    }
  }

  void _onTextChanged() {
    if (!_isConnected) return;

    if (_messageController.text.isNotEmpty && !_amITyping) {
      _amITyping = true;
      appState.nearbyService?.sendTypingStatus(widget.peerId, true);
    }

    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 2), () {
      if (_amITyping) {
        _amITyping = false;
        appState.nearbyService?.sendTypingStatus(widget.peerId, false);
      }
    });
  }

  void _updateMessageStatus(String messageId, MessageStatus status) {
    final index = _messages.indexWhere((msg) => msg.id == messageId);
    if (index != -1) {
      final oldMessage = _messages[index];
      if (oldMessage.status == status) return;

      final newMessage = Message(
        id: oldMessage.id,
        senderId: oldMessage.senderId,
        receiverId: oldMessage.receiverId,
        text: oldMessage.text,
        timestamp: oldMessage.timestamp,
        status: status,
        type: oldMessage.type,
        filePath: oldMessage.filePath,
        fileName: oldMessage.fileName,
        voiceDurationMs: oldMessage.voiceDurationMs,
      );abcdrfggh

      appState.sqliteService.insertMessage(newMessage);
      if (mounted) {
        setState(() {
          _messages[index] = newMessage;
        });
      }
    }
  }

  void _processPendingReadReceipts() {
    if (_pendingReadReceipts.isEmpty) return;

    final messageIds = List<String>.from(_pendingReadReceipts);
    _pendingReadReceipts.clear();

    // Update all messages in one setState
    setState(() {
      for (final messageId in messageIds) {
        final index = _messages.indexWhere((msg) => msg.id == messageId);
        if (index != -1) {
          final oldMessage = _messages[index];
          final newMessage = oldMessage.copyWith(status: MessageStatus.read);
          _messages[index] = newMessage;
          appState.sqliteService.insertMessage(newMessage);
          appState.nearbyService?.sendReadReceipt(widget.peerId, messageId);
        }
      }
    });
  }

  @override
  void dispose() {
    print('🔴 ChatScreen: Clearing currently open chat');
    appState.setCurrentlyOpenChat(null);
    _messageSubscription?.cancel();
    appState.nearbyService?.onTypingStatusChanged = null;
    appState.nearbyService?.onRecordingStatusChanged = null;
    appState.nearbyService?.onMessageRead = null;
    appState.nearbyService?.onMessageDeleted = null;
    appState.nearbyService?.onDisconnected = null;
    appState.nearbyService?.onConnectionResult = null;

    _messageController.removeListener(_onTextChanged);
    _typingTimer?.cancel();
    _readReceiptBatchTimer?.cancel();
    _voiceService.dispose();
    _typingAnimController.dispose();
    _recordingAnimController.dispose();
    _scrollController.dispose();
    _markedAsReadMessageIds.clear();
    _pendingReadReceipts.clear();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    final messages = await appState.sqliteService.getMessages(widget.peerName);
    if (mounted) {
      setState(() {
        _messages.addAll(messages.reversed);
      });
    }
  }

  void _sendMessage() {
    if (!_isConnected) {
      _showNotConnectedDialog();
      return;
    }

    if (_amITyping) {
      _typingTimer?.cancel();
      _amITyping = false;
      appState.nearbyService?.sendTypingStatus(widget.peerId, false);
    }

    if (_messageController.text.isEmpty) return;

    try {
      final myId = appState.username ?? 'me';
      final message = Message(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        senderId: myId,
        receiverId: widget.peerName,
        text: _messageController.text,
        timestamp: DateTime.now(),
        status: MessageStatus.sent,
        type: MessageType.text,
      );

      appState.sqliteService.insertMessage(message);
      setState(() {
        _messages.insert(0, message);
      });
      _messageController.clear();

      final messageJson = jsonEncode(message.toMap());
      final packagedMessage = EncryptionService.encryptText(messageJson);

      appState.nearbyService?.sendMessage(widget.peerId, packagedMessage);
    } catch (e) {
      debugPrint("Error in _sendMessage: $e");
    }
  }

  void _handleRecordingStatusChange(bool isRecording) {
    if (!_isConnected) return;

    _amIRecording = isRecording;
    appState.nearbyService?.sendRecordingStatus(widget.peerId, isRecording);
  }

  Future<void> _sendVoiceMessage(String voiceFilePath, int durationMs) async {
    if (!_isConnected) {
      _showNotConnectedDialog();
      return;
    }

    try {
      final myId = appState.username ?? 'me';

      final voiceFile = File(voiceFilePath);
      final voiceBytes = await voiceFile.readAsBytes();
      final base64Voice = base64Encode(voiceBytes);

      final message = Message(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        senderId: myId,
        receiverId: widget.peerName,
        text: base64Voice,
        timestamp: DateTime.now(),
        status: MessageStatus.sent,
        type: MessageType.voice,
        filePath: voiceFilePath,
        fileName: 'voice_${DateTime.now().millisecondsSinceEpoch}.aac',
        voiceDurationMs: durationMs,
      );

      appState.sqliteService.insertMessage(message);
      setState(() {
        _messages.insert(0, message);
        _showVoiceRecording = false;
      });

      final messageJson = jsonEncode(message.toMap());
      final packagedMessage = EncryptionService.encryptText(messageJson);

      appState.nearbyService?.sendMessage(widget.peerId, packagedMessage);
    } catch (e) {
      debugPrint("Error in _sendVoiceMessage: $e");
    }
  }

  void _showNotConnectedDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Not Connected',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'You need to be connected to send messages. Go back to the home screen to connect with this device.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF8B5CF6),
            ),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _playVoiceMessage(Message message) async {
    if (_currentlyPlayingMessageId == message.id) {
      await _voiceService.stopPlaying();
      setState(() {
        _currentlyPlayingMessageId = null;
      });
    } else {
      await _voiceService.stopPlaying();

      String? filePath = message.filePath;

      if (filePath == null || !File(filePath).existsSync()) {
        try {
          final voiceData = base64Decode(message.text);
          final directory = await getApplicationDocumentsDirectory();
          filePath = '${directory.path}/temp_${message.id}.aac';
          await File(filePath).writeAsBytes(voiceData);
        } catch (e) {
          debugPrint("Error creating temp voice file: $e");
          return;
        }
      }

      await _voiceService.setPlaybackSpeed(_playbackSpeed);
      await _voiceService.playVoiceMessage(filePath);

      setState(() {
        _currentlyPlayingMessageId = message.id;
      });

      final adjustedDuration =
          ((message.voiceDurationMs ?? 5000) / _playbackSpeed).round();
      Timer(Duration(milliseconds: adjustedDuration), () {
        if (mounted && _currentlyPlayingMessageId == message.id) {
          setState(() {
            _currentlyPlayingMessageId = null;
          });
        }
      });
    }
  }

  Future<void> _changePlaybackSpeed() async {
    final newSpeed = await _voiceService.cyclePlaybackSpeed();
    setState(() {
      _playbackSpeed = newSpeed;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Playback speed: ${newSpeed}x'),
          duration: const Duration(milliseconds: 800),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF8B5CF6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
  }

  void _copyMessage(Message message) {
    if (message.type == MessageType.text) {
      Clipboard.setData(ClipboardData(text: message.text));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Message copied to clipboard'),
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF10B981),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
  }

  Future<void> _deleteMessage(Message message) async {
    final myId = appState.username ?? 'me';
    final isMyMessage = message.senderId == myId;

    final deleteOption = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Delete Message',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isMyMessage && _isConnected)
              const Text(
                'Choose delete option:',
                style: TextStyle(color: Colors.white70),
              )
            else if (isMyMessage && !_isConnected)
              const Text(
                'Device not connected. This will only delete the message from your device.',
                style: TextStyle(color: Colors.white70),
              )
            else
              const Text(
                'This will delete the message from your device only.',
                style: TextStyle(color: Colors.white70),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'delete_for_me'),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF8B5CF6),
            ),
            child: const Text('Delete for Me'),
          ),
          if (isMyMessage && _isConnected)
            TextButton(
              onPressed: () => Navigator.pop(context, 'delete_for_everyone'),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Delete for Everyone'),
            ),
        ],
      ),
    );

    if (deleteOption == null) return;

    await appState.sqliteService.deleteMessage(message.id);
    if (mounted) {
      setState(() {
        _messages.removeWhere((m) => m.id == message.id);
      });
    }

    if (deleteOption == 'delete_for_everyone' && _isConnected) {
      appState.nearbyService?.sendDeleteMessage(widget.peerId, message.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Message deleted for everyone'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFFEF4444),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Message deleted'),
            duration: const Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFF6B7280),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    }
  }

  Future<void> _clearChatHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Clear Chat History',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Are you sure you want to delete all messages with ${widget.peerName}? This action cannot be undone and will only clear messages on your device.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      for (var message in _messages) {
        await appState.sqliteService.deleteMessage(message.id);
      }

      if (mounted) {
        setState(() {
          _messages.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Chat history cleared'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFF6B7280),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    }
  }

  void _showMessageOptions(Message message, bool isMe) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[600],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            if (message.type == MessageType.text)
              ListTile(
                leading: const Icon(Icons.copy, color: Color(0xFF8B5CF6)),
                title: const Text(
                  'Copy Text',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _copyMessage(message);
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text(
                'Delete Message',
                style: TextStyle(color: Colors.red),
              ),
              onTap: () {
                Navigator.pop(context);
                _deleteMessage(message);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final myId = appState.username ?? 'me';

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1E),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF1E1E2E).withOpacity(0.95),
                const Color(0xFF2D2D44).withOpacity(0.95),
              ],
            ),
          ),
        ),
        title: Row(
          children: [
            Hero(
              tag: 'avatar_${widget.peerId}',
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [const Color(0xFF8B5CF6), const Color(0xFF06B6D4)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF8B5CF6).withOpacity(0.3),
                      blurRadius: 12,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: CircleAvatar(
                  radius: 20,
                  backgroundColor: Colors.transparent,
                  backgroundImage: widget.peerAvatar != null
                      ? NetworkImage(widget.peerAvatar!)
                      : null,
                  child: widget.peerAvatar == null
                      ? Text(
                          widget.peerName[0].toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        )
                      : null,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.peerName,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _isConnected
                              ? const Color(0xFF10B981)
                              : Colors.grey[600],
                          shape: BoxShape.circle,
                          boxShadow: _isConnected
                              ? [
                                  BoxShadow(
                                    color: const Color(
                                      0xFF10B981,
                                    ).withOpacity(0.5),
                                    blurRadius: 8,
                                    spreadRadius: 2,
                                  ),
                                ]
                              : null,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _isConnected ? 'Online' : 'Offline',
                        style: TextStyle(
                          fontSize: 13,
                          color: _isConnected
                              ? const Color(0xFF10B981)
                              : Colors.grey[500],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            color: const Color(0xFF1E1E2E),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            onSelected: (value) {
              if (value == 'clear_chat') {
                _clearChatHistory();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'clear_chat',
                child: Row(
                  children: [
                    Icon(Icons.delete_sweep, color: Colors.red),
                    SizedBox(width: 12),
                    Text('Clear Chat', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [const Color(0xFF0F0F1E), const Color(0xFF1A1A2E)],
          ),
        ),
        child: Column(
          children: [
            const SizedBox(height: 100),
            Expanded(
              child: _messages.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: [
                                  const Color(0xFF8B5CF6).withOpacity(0.2),
                                  const Color(0xFF06B6D4).withOpacity(0.2),
                                ],
                              ),
                            ),
                            child: Icon(
                              Icons.chat_bubble_outline,
                              size: 64,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            'No messages yet',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[400],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Start the conversation!',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      reverse: true,
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 16,
                      ),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        final message = _messages[index];
                        final isMe = message.senderId == myId;

                        if (!isMe &&
                            message.status != MessageStatus.read &&
                            _isConnected &&
                            !_markedAsReadMessageIds.contains(message.id)) {
                          // Add this check
                          _markedAsReadMessageIds.add(message.id);
                          _pendingReadReceipts.add(message.id);
                          _readReceiptBatchTimer?.cancel();
                          _readReceiptBatchTimer = Timer(
                            const Duration(milliseconds: 100),
                            () {
                              _processPendingReadReceipts();
                            },
                          );
                        }

                        if (message.type == MessageType.voice) {
                          return GestureDetector(
                            onLongPress: () =>
                                _showMessageOptions(message, isMe),
                            child: VoiceMessageBubble(
                              message: message,
                              isMe: isMe,
                              isPlaying:
                                  _currentlyPlayingMessageId == message.id,
                              playbackSpeed: _playbackSpeed,
                              onPlay: () => _playVoiceMessage(message),
                              onSpeedChange: _changePlaybackSpeed,
                            ),
                          );
                        } else {
                          return GestureDetector(
                            onLongPress: () =>
                                _showMessageOptions(message, isMe),
                            child: _buildMessageBubble(message, isMe),
                          );
                        }
                      },
                    ),
            ),
            if (_isPeerRecording && _isConnected)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.red.withOpacity(0.1),
                      Colors.red.withOpacity(0.05),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.red.withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedBuilder(
                      animation: _recordingAnimController,
                      builder: (context, child) {
                        return Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(
                              0.5 + 0.5 * _recordingAnimController.value,
                            ),
                            shape: BoxShape.circle,
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${widget.peerName} is recording audio...',
                      style: const TextStyle(
                        color: Colors.red,
                        fontStyle: FontStyle.italic,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              )
            else if (_isPeerTyping && _isConnected)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF8B5CF6).withOpacity(0.1),
                      const Color(0xFF06B6D4).withOpacity(0.05),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFF8B5CF6).withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedBuilder(
                      animation: _typingAnimController,
                      builder: (context, child) {
                        return Row(
                          children: List.generate(3, (index) {
                            final delay = index * 0.2;
                            final animValue =
                                (_typingAnimController.value + delay) % 1.0;
                            // Fix: Use sine wave for smooth animation
                            final opacity =
                                0.3 +
                                0.7 *
                                    ((1 + math.sin(animValue * 2 * math.pi)) /
                                        2);

                            return Container(
                              margin: const EdgeInsets.symmetric(horizontal: 2),
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFF8B5CF6,
                                ).withOpacity(opacity.clamp(0.0, 1.0)),
                                shape: BoxShape.circle,
                              ),
                            );
                          }),
                        );
                      },
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${widget.peerName} is typing...',
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontStyle: FontStyle.italic,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            if (_showVoiceRecording && _isConnected)
              VoiceRecordingWidget(
                voiceService: _voiceService,
                onVoiceMessageSent: (path, duration) =>
                    _sendVoiceMessage(path, duration),
                onRecordingStatusChanged: _handleRecordingStatusChange,
              )
            else
              _buildMessageComposer(),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(Message message, bool isMe) {
    final formattedTime = DateFormat('HH:mm').format(message.timestamp);
    Widget statusIcon = const SizedBox.shrink();
    if (isMe) {
      if (message.status == MessageStatus.read) {
        statusIcon = const Icon(
          Icons.done_all,
          size: 14,
          color: Color(0xFF06B6D4),
        );
      } else {
        statusIcon = Icon(Icons.done, size: 14, color: Colors.grey[500]);
      }
    }

    return Container(
      // REMOVED TweenAnimationBuilder - it's causing the opacity error
      margin: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: isMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFF06B6D4), Color(0xFF3B82F6)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF06B6D4).withOpacity(0.3),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: CircleAvatar(
                radius: 16,
                backgroundColor: Colors.transparent,
                backgroundImage: widget.peerAvatar != null
                    ? NetworkImage(widget.peerAvatar!)
                    : null,
                child: widget.peerAvatar == null
                    ? Text(
                        widget.peerName[0].toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      )
                    : null,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(
                vertical: 12.0,
                horizontal: 16.0,
              ),
              decoration: BoxDecoration(
                gradient: isMe
                    ? const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF8B5CF6), Color(0xFF6366F1)],
                      )
                    : LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          const Color(0xFF374151),
                          const Color(0xFF1F2937),
                        ],
                      ),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(20),
                  topRight: const Radius.circular(20),
                  bottomLeft: Radius.circular(isMe ? 20 : 4),
                  bottomRight: Radius.circular(isMe ? 4 : 20),
                ),
                boxShadow: [
                  BoxShadow(
                    color: isMe
                        ? const Color(0xFF8B5CF6).withOpacity(0.3)
                        : Colors.black.withOpacity(0.2),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                    spreadRadius: 0,
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.text,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      height: 1.4,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        formattedTime,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.6),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (isMe) const SizedBox(width: 4),
                      if (isMe) statusIcon,
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageComposer() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF1A1A2E).withOpacity(0.95),
            const Color(0xFF1E1E2E).withOpacity(0.95),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Column(
        children: [
          if (!_isConnected)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.orange.withOpacity(0.15),
                    Colors.deepOrange.withOpacity(0.1),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.orange.withOpacity(0.4),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.info_outline,
                      size: 16,
                      color: Colors.orange,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Not connected - View only mode',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.orange[300],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  gradient: _isConnected
                      ? const LinearGradient(
                          colors: [Color(0xFF8B5CF6), Color(0xFF6366F1)],
                        )
                      : LinearGradient(
                          colors: [Colors.grey[800]!, Colors.grey[700]!],
                        ),
                  shape: BoxShape.circle,
                  boxShadow: _isConnected
                      ? [
                          BoxShadow(
                            color: const Color(0xFF8B5CF6).withOpacity(0.4),
                            blurRadius: 12,
                            spreadRadius: 2,
                          ),
                        ]
                      : null,
                ),
                child: IconButton(
                  icon: const Icon(Icons.mic, color: Colors.white),
                  onPressed: _isConnected
                      ? () {
                          setState(() {
                            _showVoiceRecording = true;
                          });
                        }
                      : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFF374151),
                        const Color(0xFF1F2937),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: _isConnected
                          ? const Color(0xFF8B5CF6).withOpacity(0.3)
                          : Colors.grey[800]!,
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: TextField(
                    controller: _messageController,
                    enabled: _isConnected,
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                    decoration: InputDecoration(
                      hintText: _isConnected
                          ? 'Type a message...'
                          : 'Connect to send messages',
                      hintStyle: TextStyle(
                        color: Colors.grey[500],
                        fontSize: 15,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                    ),
                    maxLines: 5,
                    minLines: 1,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                decoration: BoxDecoration(
                  gradient: _isConnected
                      ? const LinearGradient(
                          colors: [Color(0xFF06B6D4), Color(0xFF3B82F6)],
                        )
                      : LinearGradient(
                          colors: [Colors.grey[800]!, Colors.grey[700]!],
                        ),
                  shape: BoxShape.circle,
                  boxShadow: _isConnected
                      ? [
                          BoxShadow(
                            color: const Color(0xFF06B6D4).withOpacity(0.4),
                            blurRadius: 12,
                            spreadRadius: 2,
                          ),
                        ]
                      : null,
                ),
                child: IconButton(
                  icon: const Icon(Icons.send_rounded, color: Colors.white),
                  onPressed: _isConnected ? _sendMessage : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
