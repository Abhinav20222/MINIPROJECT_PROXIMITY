import 'package:flutter/material.dart';
import 'package:offgrid/screens/chat_screen.dart';
import 'package:offgrid/screens/settings_screen.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:app_settings/app_settings.dart';
import 'package:intl/intl.dart';
import '../utils/app_state.dart';
import '../models/message.dart';
import 'dart:async';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late AppState appState;
  late TabController _tabController;

  final Map<String, String> _discoveredEndpoints = {};
  String? _connectedEndpointId;
  String? _connectedEndpointName;

  String? _connectingToEndpointId;
  bool _isDiscovering = false;
  bool _isAdvertising = false;

  Map<String, ChatSummary> _chatHistory = {};
  bool _isLoadingHistory = true;

  StreamSubscription<Message>? _messageSubscription;

  @override
  void initState() {
    super.initState();
    appState = Provider.of<AppState>(context, listen: false);
    _tabController = TabController(length: 2, vsync: this);

    _requestPermissions().then((_) => _checkServices());
    _subscribeToServiceEvents();
    _loadChatHistory();

    _messageSubscription = appState.onMessageReceived.listen((message) {
      if (mounted) {
        _loadChatHistory(); // Refresh chat list

        final myId = appState.username ?? 'me';
        final senderId = message.senderId;

        final isInChatWithSender = appState.currentlyOpenChatPeerId == senderId;

        if (senderId != myId && !isInChatWithSender) {
          _showMessageNotification(senderId, message);
        }
      }
    });
  }

  Future<void> _loadChatHistory() async {
    setState(() => _isLoadingHistory = true);

    try {
      final allMessages = await appState.sqliteService.getAllMessages();
      final Map<String, ChatSummary> history = {};

      final myId = appState.username ?? 'me';

      // Group messages by peer
      for (var message in allMessages) {
        // Determine the peer - the person who is NOT me
        String peerId;
        if (message.senderId == myId) {
          peerId = message.receiverId;
        } else if (message.receiverId == myId) {
          peerId = message.senderId;
        } else {
          // This message doesn't involve current user, skip it
          // This handles old messages from previous usernames
          continue;
        }

        // Skip if peerId is somehow empty or same as myId
        if (peerId.isEmpty || peerId == myId) continue;

        if (!history.containsKey(peerId)) {
          history[peerId] = ChatSummary(
            peerId: peerId,
            peerName: peerId,
            lastMessage: message,
            unreadCount: 0,
            totalMessages: 1,
          );
        } else {
          final current = history[peerId]!;

          // Update if this message is more recent
          if (message.timestamp.isAfter(current.lastMessage.timestamp)) {
            history[peerId] = ChatSummary(
              peerId: peerId,
              peerName: peerId,
              lastMessage: message,
              unreadCount: current.unreadCount,
              totalMessages: current.totalMessages + 1,
            );
          } else {
            history[peerId] = ChatSummary(
              peerId: peerId,
              peerName: peerId,
              lastMessage: current.lastMessage,
              unreadCount: current.unreadCount,
              totalMessages: current.totalMessages + 1,
            );
          }

          // Count unread messages (messages from peer that aren't read)
          if (message.senderId == peerId &&
              message.status != MessageStatus.read) {
            history[peerId] = ChatSummary(
              peerId: history[peerId]!.peerId,
              peerName: history[peerId]!.peerName,
              lastMessage: history[peerId]!.lastMessage,
              unreadCount: history[peerId]!.unreadCount + 1,
              totalMessages: history[peerId]!.totalMessages,
            );
          }
        }
      }

      if (mounted) {
        setState(() {
          _chatHistory = history;
          _isLoadingHistory = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading chat history: $e');
      if (mounted) {
        setState(() => _isLoadingHistory = false);
      }
    }
  }

  Future<void> _requestPermissions() async {
    await [
      Permission.location,
      Permission.bluetoothScan,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.nearbyWifiDevices,
    ].request();
  }

  Future<void> _checkServices() async {
    if (await Permission.location.serviceStatus.isDisabled && mounted) {
      _showServiceDisabledDialog(
        'Services Disabled',
        'For offline chat to work, please enable Location, Wi-Fi, and Bluetooth in your phone\'s settings.',
        AppSettingsType.location,
      );
    }
  }

  void _showServiceDisabledDialog(
    String title,
    String content,
    AppSettingsType settingsType,
  ) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E2E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(title, style: const TextStyle(color: Colors.white)),
          content: Text(content, style: const TextStyle(color: Colors.white70)),
          actions: <Widget>[
            TextButton(
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.white70),
              ),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF8B5CF6),
              ),
              child: const Text('Open Settings'),
              onPressed: () {
                AppSettings.openAppSettings(type: settingsType);
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  void _subscribeToServiceEvents() {
    appState.nearbyService.onEndpointFound = (endpoint) {
      final endpointId = endpoint['endpointId'] as String?;
      final endpointName = endpoint['endpointName'] as String?;

      if (mounted && endpointId != null && endpointName != null) {
        setState(() {
          _discoveredEndpoints[endpointId] = endpointName;
        });
      }
    };

    appState.nearbyService.onEndpointLost = (endpointId) {
      if (mounted) {
        setState(() {
          _discoveredEndpoints.remove(endpointId);
        });
      }
    };

    appState.nearbyService.onConnectionResult = (result) {
      if (mounted) {
        final status = result['status'] as String?;

        if (status == 'connected') {
          setState(() {
            _connectedEndpointId = result['endpointId'] as String?;
            _connectedEndpointName = result['endpointName'] as String?;
            _discoveredEndpoints.clear();
            _isDiscovering = false;
            _isAdvertising = false;
            _connectingToEndpointId = null;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Connected to $_connectedEndpointName!'),
              backgroundColor: const Color(0xFF10B981),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        } else {
          setState(() {
            _connectingToEndpointId = null;
            _isDiscovering = false;
            _isAdvertising = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Connection failed'),
              backgroundColor: const Color(0xFFEF4444),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        }
      }
    };

    appState.nearbyService.onDisconnected = (endpointId) {
      if (mounted) {
        final disconnectedPeerName = _connectedEndpointName ?? 'the device';
        setState(() {
          _isDiscovering = false;
          _isAdvertising = false;
          _connectingToEndpointId = null;
          _connectedEndpointId = null;
          _connectedEndpointName = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Disconnected from $disconnectedPeerName.'),
            backgroundColor: Colors.orange.shade800,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    };
  }

  void _showMessageNotification(String senderId, Message message) {
    String messagePreview;

    switch (message.type) {
      case MessageType.voice:
        messagePreview = '🎤 Voice message';
        break;
      case MessageType.image:
        messagePreview = '📷 Image';
        break;
      case MessageType.file:
        messagePreview = '📎 File';
        break;
      default:
        messagePreview = message.text.length > 50
            ? '${message.text.substring(0, 50)}...'
            : message.text;
    }

    if (ScaffoldMessenger.of(context).mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Container(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF06B6D4), Color(0xFF3B82F6)],
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: CircleAvatar(
                    radius: 20,
                    backgroundColor: Colors.transparent,
                    child: Text(
                      senderId[0].toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        senderId,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        messagePreview,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.white.withOpacity(0.9),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF1E1E2E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          action: SnackBarAction(
            label: 'View',
            textColor: Colors.blue[300],
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();

              // Check if we're already viewing this chat
              if (appState.currentlyOpenChatPeerId == senderId) {
                return;
              }

              // Find the endpoint ID for this sender
              // Check if this sender is the currently connected endpoint
              String? endpointIdToUse;

              if (_connectedEndpointName == senderId) {
                // The sender is the currently connected peer
                endpointIdToUse = _connectedEndpointId;
              } else {
                // Check discovered endpoints
                _discoveredEndpoints.forEach((id, name) {
                  if (name == senderId) {
                    endpointIdToUse = id;
                  }
                });
              }

              // If no endpoint found, use senderId as fallback (will show view-only mode)
              final peerIdToUse = endpointIdToUse ?? senderId;

              // If a chat is open, pop it first
              if (appState.currentlyOpenChatPeerId != null) {
                Navigator.pop(context);
              }

              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      ChatScreen(peerId: peerIdToUse, peerName: senderId),
                ),
              ).then((_) {
                _loadChatHistory();
              });
            },
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _messageSubscription?.cancel();
    appState.nearbyService.onEndpointFound = null;
    appState.nearbyService.onEndpointLost = null;
    appState.nearbyService.onConnectionResult = null;
    appState.nearbyService.onDisconnected = null;
    super.dispose();
  }

  Future<void> _deleteChatHistory(String peerId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Chat', style: TextStyle(color: Colors.white)),
        content: Text(
          'Delete all messages with $peerId? This cannot be undone.',
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
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final messages = await appState.sqliteService.getMessages(peerId);
      for (var message in messages) {
        await appState.sqliteService.deleteMessage(message.id);
      }
      _loadChatHistory();
    }
  }

  Widget _buildChatHistoryTab() {
    if (_isLoadingHistory) {
      return Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(const Color(0xFF8B5CF6)),
        ),
      );
    }

    if (_chatHistory.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(32),
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
                size: 80,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No conversations yet',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: Colors.grey[400],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Connect to nearby devices to start chatting',
              style: TextStyle(fontSize: 15, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    final sortedChats = _chatHistory.values.toList()
      ..sort(
        (a, b) => b.lastMessage.timestamp.compareTo(a.lastMessage.timestamp),
      );

    return RefreshIndicator(
      onRefresh: _loadChatHistory,
      color: const Color(0xFF8B5CF6),
      backgroundColor: const Color(0xFF1E1E2E),
      child: ListView.builder(
        physics: const BouncingScrollPhysics(),
        itemCount: sortedChats.length,
        itemBuilder: (context, index) {
          final chat = sortedChats[index];
          final isOnline =
              _discoveredEndpoints.containsKey(chat.peerId) ||
              _connectedEndpointId == chat.peerId;

          return Dismissible(
            key: Key(chat.peerId),
            background: Container(
              margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 24),
              child: const Icon(
                Icons.delete_sweep,
                color: Colors.white,
                size: 28,
              ),
            ),
            direction: DismissDirection.endToStart,
            confirmDismiss: (direction) =>
                _deleteChatHistory(chat.peerId).then((_) => false),
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [const Color(0xFF1E1E2E), const Color(0xFF2D2D44)],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isOnline
                      ? const Color(0xFF10B981).withOpacity(0.3)
                      : Colors.transparent,
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
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                leading: Stack(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF06B6D4), Color(0xFF3B82F6)],
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF06B6D4).withOpacity(0.3),
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: CircleAvatar(
                        radius: 26,
                        backgroundColor: Colors.transparent,
                        child: Text(
                          chat.peerName[0].toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                          ),
                        ),
                      ),
                    ),
                    if (isOnline)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(0xFF1E1E2E),
                              width: 3,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF10B981).withOpacity(0.5),
                                blurRadius: 8,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        chat.peerName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    Text(
                      _formatTimestamp(chat.lastMessage.timestamp),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[500],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    children: [
                      if (chat.lastMessage.senderId ==
                          (appState.username ?? 'me'))
                        Icon(
                          chat.lastMessage.status == MessageStatus.read
                              ? Icons.done_all
                              : Icons.done,
                          size: 16,
                          color: chat.lastMessage.status == MessageStatus.read
                              ? const Color(0xFF06B6D4)
                              : Colors.grey[600],
                        ),
                      if (chat.lastMessage.senderId ==
                          (appState.username ?? 'me'))
                        const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          chat.lastMessage.type == MessageType.voice
                              ? '🎤 Voice message'
                              : chat.lastMessage.text,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: chat.unreadCount > 0
                                ? FontWeight.w600
                                : FontWeight.normal,
                            color: chat.unreadCount > 0
                                ? Colors.white
                                : Colors.grey[400],
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                trailing: chat.unreadCount > 0
                    ? Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF8B5CF6), Color(0xFF6366F1)],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF8B5CF6).withOpacity(0.4),
                              blurRadius: 8,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: Text(
                          chat.unreadCount.toString(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      )
                    : null,
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ChatScreen(
                        peerId: chat.peerId,
                        peerName: chat.peerName,
                      ),
                    ),
                  );

                  _loadChatHistory();
                },
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildConnectionTab() {
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF8B5CF6).withOpacity(0.15),
                const Color(0xFF06B6D4).withOpacity(0.15),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color(0xFF8B5CF6).withOpacity(0.3),
              width: 1,
            ),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF8B5CF6), Color(0xFF6366F1)],
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.person,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Your Name',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[500],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          appState.username ?? 'Unknown',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: _isDiscovering
                            ? LinearGradient(
                                colors: [Colors.grey[800]!, Colors.grey[700]!],
                              )
                            : const LinearGradient(
                                colors: [Color(0xFF06B6D4), Color(0xFF3B82F6)],
                              ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: !_isDiscovering
                            ? [
                                BoxShadow(
                                  color: const Color(
                                    0xFF06B6D4,
                                  ).withOpacity(0.4),
                                  blurRadius: 12,
                                  spreadRadius: 2,
                                ),
                              ]
                            : null,
                      ),
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.search, size: 20),
                        label: const Text(
                          'Discover',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: (_isDiscovering || _isAdvertising)
                            ? null
                            : () {
                                setState(() => _isDiscovering = true);
                                appState.nearbyService.startDiscovery(
                                  appState.username!,
                                );
                              },
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: _isAdvertising
                            ? LinearGradient(
                                colors: [Colors.grey[800]!, Colors.grey[700]!],
                              )
                            : const LinearGradient(
                                colors: [Color(0xFF8B5CF6), Color(0xFF6366F1)],
                              ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: !_isAdvertising
                            ? [
                                BoxShadow(
                                  color: const Color(
                                    0xFF8B5CF6,
                                  ).withOpacity(0.4),
                                  blurRadius: 12,
                                  spreadRadius: 2,
                                ),
                              ]
                            : null,
                      ),
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.wifi_tethering, size: 20),
                        label: const Text(
                          'Advertise',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: (_isDiscovering || _isAdvertising)
                            ? null
                            : () {
                                setState(() => _isAdvertising = true);
                                appState.nearbyService.startAdvertising(
                                  appState.username!,
                                );
                              },
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_connectedEndpointId != null)
          _buildConnectedView(appState)
        else
          _buildDiscoveryListView(appState),
      ],
    );
  }

  Widget _buildConnectedView(AppState appState) {
    return Expanded(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF10B981).withOpacity(0.2),
                    const Color(0xFF059669).withOpacity(0.2),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF10B981).withOpacity(0.3),
                    blurRadius: 30,
                    spreadRadius: 10,
                  ),
                ],
              ),
              child: const Icon(
                Icons.check_circle,
                size: 80,
                color: Color(0xFF10B981),
              ),
            ),
            const SizedBox(height: 32),
            Text(
              'Connected to',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[500],
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _connectedEndpointName ?? 'Unknown',
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 40),
            Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF8B5CF6), Color(0xFF6366F1)],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF8B5CF6).withOpacity(0.4),
                    blurRadius: 16,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: ElevatedButton.icon(
                icon: const Icon(Icons.chat_rounded, size: 22),
                label: const Text(
                  'Open Chat',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ChatScreen(
                        peerId: _connectedEndpointId!,
                        peerName: _connectedEndpointName!,
                      ),
                    ),
                  );

                  _loadChatHistory();
                },
              ),
            ),
            const SizedBox(height: 16),
            TextButton(
              child: Text(
                'Disconnect',
                style: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
              onPressed: () {
                appState.nearbyService.stopAllEndpoints();
                setState(() {
                  _isDiscovering = false;
                  _isAdvertising = false;
                  _connectingToEndpointId = null;
                  _connectedEndpointId = null;
                  _connectedEndpointName = null;
                  _discoveredEndpoints.clear();
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiscoveryListView(AppState appState) {
    return Expanded(
      child: _discoveredEndpoints.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [
                          Colors.grey[800]!.withOpacity(0.3),
                          Colors.grey[700]!.withOpacity(0.3),
                        ],
                      ),
                    ),
                    child: Icon(
                      Icons.devices,
                      size: 80,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'No devices found yet',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[400],
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_isDiscovering || _isAdvertising)
                    Column(
                      children: [
                        const SizedBox(height: 16),
                        CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(
                            const Color(0xFF8B5CF6),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _isDiscovering ? 'Discovering...' : 'Advertising...',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    )
                  else
                    Text(
                      'Tap Discover or Advertise to connect',
                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                    ),
                ],
              ),
            )
          : ListView.builder(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _discoveredEndpoints.length,
              itemBuilder: (context, index) {
                final endpointId = _discoveredEndpoints.keys.elementAt(index);
                final endpointName = _discoveredEndpoints[endpointId];
                final bool isConnecting = _connectingToEndpointId == endpointId;

                return Container(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        const Color(0xFF1E1E2E),
                        const Color(0xFF2D2D44),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    leading: Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF06B6D4), Color(0xFF3B82F6)],
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF06B6D4).withOpacity(0.3),
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: CircleAvatar(
                        radius: 26,
                        backgroundColor: Colors.transparent,
                        child: Text(
                          endpointName?[0].toUpperCase() ?? '?',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                          ),
                        ),
                      ),
                    ),
                    title: Text(
                      endpointName ?? 'Unknown Device',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                        color: Colors.white,
                      ),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        endpointId,
                        style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                      ),
                    ),
                    trailing: isConnecting
                        ? SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                const Color(0xFF8B5CF6),
                              ),
                            ),
                          )
                        : Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF8B5CF6), Color(0xFF6366F1)],
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.arrow_forward,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                    onTap: _connectingToEndpointId != null
                        ? null
                        : () {
                            setState(() {
                              _connectingToEndpointId = endpointId;
                            });
                            appState.nearbyService.connectToEndpoint(
                              endpointId,
                            );
                          },
                  ),
                );
              },
            ),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inDays == 0) {
      return DateFormat('HH:mm').format(timestamp);
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return DateFormat('EEEE').format(timestamp);
    } else {
      return DateFormat('dd/MM/yyyy').format(timestamp);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1E),
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
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF8B5CF6), Color(0xFF6366F1)],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.chat_bubble, size: 20),
            ),
            const SizedBox(width: 12),
            const Text(
              'Proximity',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 22,
                color: Colors.white,
              ),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF8B5CF6),
          indicatorWeight: 3,
          labelColor: const Color(0xFF8B5CF6),
          unselectedLabelColor: Colors.grey[500],
          labelStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
          tabs: const [
            Tab(icon: Icon(Icons.chat_rounded, size: 22), text: 'Chats'),
            Tab(icon: Icon(Icons.wifi_tethering, size: 22), text: 'Connect'),
          ],
        ),
        actions: [
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.settings, size: 20),
            ),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
              _loadChatHistory();
            },
          ),
          const SizedBox(width: 8),
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
        child: TabBarView(
          controller: _tabController,
          children: [_buildChatHistoryTab(), _buildConnectionTab()],
        ),
      ),
    );
  }
}

class ChatSummary {
  final String peerId;
  final String peerName;
  final Message lastMessage;
  final int unreadCount;
  final int totalMessages;

  ChatSummary({
    required this.peerId,
    required this.peerName,
    required this.lastMessage,
    required this.unreadCount,
    required this.totalMessages,
  });
}
