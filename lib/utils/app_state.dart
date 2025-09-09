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
  
  NearbyService? nearbyService;
  final SQLiteService sqliteService = SQLiteService();

  final StreamController<Message> _messageStreamController = StreamController.broadcast();
  Stream<Message> get onMessageReceived => _messageStreamController.stream;

  String? get username => _username;

  AppState() {
    _loadUsername();
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

  void initializeNearbyService() {
    nearbyService = NearbyService();
    nearbyService?.onPayloadReceived = (payload) {
      try {
        final decryptedMessageJson = EncryptionService.decryptText(payload['message']);
        final message = Message.fromMap(jsonDecode(decryptedMessageJson));
        
        sqliteService.insertMessage(message);
        _messageStreamController.add(message);
      } catch (e) {
        debugPrint("Error processing received message in AppState: $e");
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