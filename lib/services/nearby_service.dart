import 'package:flutter/services.dart';
import 'dart:async';

class NearbyService {
  static const _channel = MethodChannel('com.example.offgrid/nearby');
  
  static const String TYPING_STATUS_START = "__typing_start__";
  static const String TYPING_STATUS_STOP = "__typing_stop__";
  static const String READ_RECEIPT_PREFIX = "__read__";

  // Callbacks are public, assignable properties
  Function(Map<String, dynamic>)? onEndpointFound;
  Function(String)? onEndpointLost;
  Function(Map<String, dynamic>)? onConnectionResult;
  Function(String)? onDisconnected;
  Function(Map<String, dynamic>)? onPayloadReceived;
  Function(Map<String, dynamic>)? onTypingStatusChanged;
  Function(Map<String, dynamic>)? onMessageRead;
  // --- Failure callbacks have been removed ---

  NearbyService() {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onEndpointFound':
        onEndpointFound?.call(Map<String, dynamic>.from(call.arguments));
        break;
      case 'onEndpointLost':
        onEndpointLost?.call(call.arguments as String);
        break;
      case 'onConnectionResult':
        onConnectionResult?.call(Map<String, dynamic>.from(call.arguments));
        break;
      case 'onDisconnected':
        onDisconnected?.call(call.arguments as String);
        break;
      case 'onPayloadReceived':
        onPayloadReceived?.call(Map<String, dynamic>.from(call.arguments));
        break;
      case 'onTypingStatusChanged':
        onTypingStatusChanged?.call(Map<String, dynamic>.from(call.arguments));
        break;
      case 'onMessageRead':
        onMessageRead?.call(Map<String, dynamic>.from(call.arguments));
        break;
      // --- Failure cases have been removed ---
      default:
        print('Unknown method ${call.method}');
    }
  }
  
  // ... (The rest of the methods are unchanged)
  Future<void> sendReadReceipt(String endpointId, String messageId) async {
    final receipt = "$READ_RECEIPT_PREFIX$messageId";
    try {
      await _channel.invokeMethod('sendMessage', {'endpointId': endpointId, 'message': receipt});
    } on PlatformException catch (e) {
      print("Failed to send read receipt: '${e.message}'.");
    }
  }

  Future<void> sendTypingStatus(String endpointId, bool isTyping) async {
    final status = isTyping ? TYPING_STATUS_START : TYPING_STATUS_STOP;
    try {
      await _channel.invokeMethod('sendMessage', {'endpointId': endpointId, 'message': status});
    } on PlatformException catch (e) {
      print("Failed to send typing status: '${e.message}'.");
    }
  }
  
  Future<void> startDiscovery(String username) async {
    try {
      await _channel.invokeMethod('startDiscovery', {'username': username});
    } on PlatformException catch (e) {
      print("Failed to start discovery: '${e.message}'.");
    }
  }

  Future<void> startAdvertising(String username) async {
    try {
      await _channel.invokeMethod('startAdvertising', {'username': username});
    } on PlatformException catch (e) {
      print("Failed to start advertising: '${e.message}'.");
    }
  }
  
  Future<void> connectToEndpoint(String endpointId) async {
    try {
      await _channel.invokeMethod('connectToEndpoint', {'endpointId': endpointId});
    } on PlatformException catch (e) {
      print("Failed to connect: '${e.message}'.");
    }
  }

  Future<void> sendMessage(String endpointId, String message) async {
    try {
      await _channel.invokeMethod('sendMessage', {'endpointId': endpointId, 'message': message});
    } on PlatformException catch (e) {
      print("Failed to send message: '${e.message}'.");
    }
  }

  Future<void> stopAllEndpoints() async {
    try {
      await _channel.invokeMethod('stopAllEndpoints');
    } on PlatformException catch (e) {
      print("Failed to stop all endpoints: '${e.message}'.");
    }
  }
}