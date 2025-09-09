import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:offgrid/models/message.dart';
import 'package:offgrid/services/encryption_service.dart';
import 'package:offgrid/utils/app_state.dart';
import 'package:provider/provider.dart';
import 'dart:convert';

class ChatScreen extends StatefulWidget {
  final String peerId;
  final String peerName;

  const ChatScreen({super.key, required this.peerId, required this.peerName});

  @override
  ChatScreenState createState() => ChatScreenState();
}

class ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final List<Message> _messages = [];
  
  late final AppState appState;
  StreamSubscription<Message>? _messageSubscription;

  bool _isPeerTyping = false;
  Timer? _typingTimer;
  bool _amITyping = false;

  @override
  void initState() {
    super.initState();
    appState = Provider.of<AppState>(context, listen: false);

    _loadMessages();
    
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

  void _subscribeToServiceEvents() {
    appState.nearbyService?.onTypingStatusChanged = (status) {
      if (mounted && status['endpointId'] == widget.peerId) {
        setState(() {
          _isPeerTyping = status['isTyping'] as bool;
        });
      }
    };
    
    appState.nearbyService?.onMessageRead = (receipt) {
      if (mounted && receipt['endpointId'] == widget.peerId) {
        final messageId = receipt['messageId'] as String;
        _updateMessageStatus(messageId, MessageStatus.read);
      }
    };

    // --- THIS IS THE CORRECTED LINE ---
    appState.nearbyService?.onDisconnected = (endpointId) {
      if(mounted && endpointId == widget.peerId) {
        if (ScaffoldMessenger.of(context).mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("${widget.peerName} disconnected")));
        }
        Navigator.of(context).pop();
      }
    };
  }

  void _onTextChanged() {
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
        id: oldMessage.id, senderId: oldMessage.senderId, receiverId: oldMessage.receiverId,
        text: oldMessage.text, timestamp: oldMessage.timestamp, status: status,
        type: oldMessage.type, filePath: oldMessage.filePath, fileName: oldMessage.fileName,
      );
      
      appState.sqliteService.insertMessage(newMessage);
      if (mounted) {
        setState(() { _messages[index] = newMessage; });
      }
    }
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    appState.nearbyService?.onTypingStatusChanged = null;
    appState.nearbyService?.onMessageRead = null;
    appState.nearbyService?.onDisconnected = null;

    _messageController.removeListener(_onTextChanged);
    _typingTimer?.cancel();
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
    if (_amITyping) {
      _typingTimer?.cancel();
      _amITyping = false;
      appState.nearbyService?.sendTypingStatus(widget.peerId, false);
    }
    
    if (_messageController.text.isEmpty) return;

    try {
      final myId = appState.username ?? 'me'; 
      final message = Message(
        id: DateTime.now().millisecondsSinceEpoch.toString(), senderId: myId, receiverId: widget.peerName,
        text: _messageController.text, timestamp: DateTime.now(), status: MessageStatus.sent,
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

  @override
  Widget build(BuildContext context) {
    final myId = appState.username ?? 'me';
    
    return Scaffold(
      appBar: AppBar(title: Text(widget.peerName)),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              reverse: true,
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                final isMe = message.senderId == myId; 
                
                if (!isMe && message.status != MessageStatus.read) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _updateMessageStatus(message.id, MessageStatus.read);
                    appState.nearbyService?.sendReadReceipt(widget.peerId, message.id);
                  });
                }
                return _buildMessageBubble(message, isMe);
              },
            ),
          ),
          if (_isPeerTyping)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
              child: Row(
                children: [
                  Text('${widget.peerName} is typing...', style: TextStyle(color: Colors.grey[600], fontStyle: FontStyle.italic)),
                ],
              ),
            ),
          _buildMessageComposer(),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(Message message, bool isMe) {
    final formattedTime = DateFormat('HH:mm').format(message.timestamp);
    Widget statusIcon = const SizedBox.shrink();
    if (isMe) {
      if (message.status == MessageStatus.read) {
        statusIcon = const Icon(Icons.done_all, size: 14, color: Colors.lightBlueAccent);
      } else {
        statusIcon = const Icon(Icons.done, size: 14, color: Colors.white70);
      }
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 16.0),
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
            decoration: BoxDecoration(color: isMe ? Colors.blue : Colors.grey[700], borderRadius: BorderRadius.circular(20.0)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Flexible(child: Text(message.text, style: const TextStyle(color: Colors.white, fontSize: 16))),
                const SizedBox(width: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(formattedTime, style: const TextStyle(color: Colors.white70, fontSize: 10)),
                    if (isMe) const SizedBox(width: 4),
                    if (isMe) statusIcon,
                  ],
                ),
              ],
            )
          ),
        ],
      ),
    );
  }

  Widget _buildMessageComposer() {
    return Container(
      padding: const EdgeInsets.all(8.0),
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              decoration: InputDecoration(
                hintText: 'Enter a message...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(25.0)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 20.0),
              ),
            ),
          ),
          const SizedBox(width: 8.0),
          IconButton(
            icon: const Icon(Icons.send, color: Colors.blue),
            onPressed: _sendMessage,
          ),
        ],
      ),
    );
  }
}