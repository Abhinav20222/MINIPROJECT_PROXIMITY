import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:offgrid/models/message.dart';
import 'package:offgrid/services/encryption_service.dart';
import 'package:offgrid/services/nearby_service.dart';
import 'package:offgrid/storage/sqlite_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppState with ChangeNotifier {
  String? _username;
  String? _currentlyOpenChatPeerId;

  final NearbyService nearbyService = NearbyService();
  final SQLiteService sqliteService = SQLiteService();

  final StreamController<Message> _messageStreamController =
      StreamController.broadcast();
  Stream<Message> get onMessageReceived => _messageStreamController.stream;

  String? get username => _username;
  String? get currentlyOpenChatPeerId => _currentlyOpenChatPeerId;

  void setCurrentlyOpenChat(String? peerName) {
    print('🔵 AppState: Setting currently open chat to: $peerName');
    _currentlyOpenChatPeerId = peerName;
    notifyListeners();
  }

  AppState() {
    _loadUsername();
    _setupCentralMessageHandler();
  }

  Future<void> _loadUsername() async {
    final prefs = await SharedPreferences.getInstance();
    String? savedUsername = prefs.getString('username');

    if (savedUsername == null || savedUsername.isEmpty) {
      savedUsername = "User-${DateTime.now().millisecondsSinceEpoch % 1000}";
      await prefs.setString('username', savedUsername);
    }
    _username = savedUsername;
    notifyListeners();
  }

  // This is the central "inbox" for all incoming messages.
  void _setupCentralMessageHandler() {
    nearbyService.onPayloadReceived = (payload) {
      try {
        final decryptedMessageJson = EncryptionService.decryptText(
          payload['message'],
        );
        final message = Message.fromMap(jsonDecode(decryptedMessageJson));

        print('📨 AppState: Message received from ${message.senderId}');
        print('📱 AppState: Currently open chat is: $_currentlyOpenChatPeerId');

        // Save every valid message to the database.
        sqliteService.insertMessage(message);

        // Broadcast the new message to any listening screens (like the ChatScreen).
        _messageStreamController.add(message);
      } catch (e) {
        print("Error processing received message in AppState: $e");
      }
    };
  }

  Future<void> setUsername(String newName) async {
    _username = newName;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('username', newName);
    notifyListeners();
  }

  @override
  void dispose() {
    _messageStreamController.close();
    super.dispose();
  }
}