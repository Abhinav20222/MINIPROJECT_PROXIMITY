import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'dart:async';

class NearbyService {
  static const _channel = MethodChannel('com.example.offgrid/nearby');
  
  // Constants updated to lowerCamelCase
  static const String typingStatusStart = "__typing_start__";
  static const String typingStatusStop = "__typing_stop__";
  static const String readReceiptPrefix = "__read__";

  Function(Map<String, dynamic>)? onEndpointFound;
  Function(String)? onEndpointLost;
  Function(Map<String, dynamic>)? onConnectionResult;
  Function(String)? onDisconnected;
  Function(Map<String, dynamic>)? onPayloadReceived;
  Function(Map<String, dynamic>)? onTypingStatusChanged;
  Function(Map<String, dynamic>)? onMessageRead;

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
      default:
        debugPrint('Unknown method ${call.method}');
    }
  }
  
  Future<void> sendReadReceipt(String endpointId, String messageId) async {
    // Updated to use the new constant name
    final receipt = "$readReceiptPrefix$messageId";
    try {
      await _channel.invokeMethod('sendMessage', {'endpointId': endpointId, 'message': receipt});
    } on PlatformException catch (e) {
      debugPrint("Failed to send read receipt: '${e.message}'.");
    }
  }

  Future<void> sendTypingStatus(String endpointId, bool isTyping) async {
    // Updated to use the new constant names
    final status = isTyping ? typingStatusStart : typingStatusStop;
    try {
      await _channel.invokeMethod('sendMessage', {'endpointId': endpointId, 'message': status});
    } on PlatformException catch (e) {
      debugPrint("Failed to send typing status: '${e.message}'.");
    }
  }
  
  Future<void> startDiscovery(String username) async {
    try {
      await _channel.invokeMethod('startDiscovery', {'username': username});
    } on PlatformException catch (e) {
      debugPrint("Failed to start discovery: '${e.message}'.");
    }
  }

  Future<void> startAdvertising(String username) async {
    try {
      await _channel.invokeMethod('startAdvertising', {'username': username});
    } on PlatformException catch (e) {
      debugPrint("Failed to start advertising: '${e.message}'.");
    }
  }
  
  Future<void> connectToEndpoint(String endpointId) async {
    try {
      await _channel.invokeMethod('connectToEndpoint', {'endpointId': endpointId});
    } on PlatformException catch (e) {
      debugPrint("Failed to connect: '${e.message}'.");
    }
  }

  Future<void> sendMessage(String endpointId, String message) async {
    try {
      await _channel.invokeMethod('sendMessage', {'endpointId': endpointId, 'message': message});
    } on PlatformException catch (e) {
      debugPrint("Failed to send message: '${e.message}'.");
    }
  }

  Future<void> stopAllEndpoints() async {
    try {
      await _channel.invokeMethod('stopAllEndpoints');
    } on PlatformException catch (e) {
      debugPrint("Failed to stop all endpoints: '${e.message}'.");
    }
  }
}