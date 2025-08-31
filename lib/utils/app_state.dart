import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:offgrid/models/message.dart';
import 'package:offgrid/services/encryption_service.dart';
import 'package:offgrid/services/nearby_service.dart';
import 'package:offgrid/storage/sqlite_service.dart';
import 'package:shared_preferences/shared_preferences.dart'; // <-- New import

class AppState with ChangeNotifier {
  // We will initialize the username from storage now.
  String? _username;
  
  NearbyService? nearbyService;
  final SQLiteService sqliteService = SQLiteService();

  final StreamController<Message> _messageStreamController = StreamController.broadcast();
  Stream<Message> get onMessageReceived => _messageStreamController.stream;

  String? get username => _username;

  // The constructor will now trigger the loading process.
  AppState() {
    _loadUsername();
  }

  // --- New method to load the username ---
  Future<void> _loadUsername() async {
    final prefs = await SharedPreferences.getInstance();
    // Try to get the username from storage.
    String? savedUsername = prefs.getString('username');

    if (savedUsername == null || savedUsername.isEmpty) {
      // If no username is saved (first launch), create a random one and save it.
      savedUsername = "User-${DateTime.now().millisecondsSinceEpoch % 1000}";
      await prefs.setString('username', savedUsername);
    }
    
    _username = savedUsername;
    // Notify listeners so the UI updates with the loaded username.
    notifyListeners();
  }
  // ----------------------------------------

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
  
  // --- Updated method to save the username when changed ---
  Future<void> setUsername(String newName) async {
    _username = newName;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('username', newName); // Save the new name
    notifyListeners();
  }
  // ----------------------------------------------------

  @override
  void dispose() {
    _messageStreamController.close();
    super.dispose();
  }
}