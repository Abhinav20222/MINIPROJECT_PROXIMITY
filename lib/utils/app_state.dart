import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:offgrid/models/message.dart';
import 'package:offgrid/services/encryption_service.dart';
import 'package:offgrid/services/nearby_service.dart';
import 'package:offgrid/storage/sqlite_service.dart';

// The AppMode enum has been removed.

class AppState with ChangeNotifier {
  // The _mode variable and its getter/setter have been removed.
  String? _username = "User-${DateTime.now().millisecondsSinceEpoch % 1000}";
  
  NearbyService? nearbyService;
  final SQLiteService sqliteService = SQLiteService();

  final StreamController<Message> _messageStreamController = StreamController.broadcast();
  Stream<Message> get onMessageReceived => _messageStreamController.stream;

  String? get username => _username;

  void initializeNearbyService() {
    nearbyService = NearbyService();
    nearbyService?.onPayloadReceived = (payload) {
      try {
        final decryptedMessageJson = EncryptionService.decryptText(payload['message']);
        final message = Message.fromMap(jsonDecode(decryptedMessageJson));
        
        sqliteService.insertMessage(message);
        _messageStreamController.add(message);
      } catch (e) {
        print("Error processing received message in AppState: $e");
      }
    };
  }
  
  void setUsername(String newName) {
    _username = newName;
    notifyListeners();
  }

  @override
  void dispose() {
    _messageStreamController.close();
    super.dispose();
  }
}