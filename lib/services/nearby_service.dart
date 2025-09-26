import 'package:flutter/services.dart';
import 'dart:async';

class NearbyService {
  static const _channel = MethodChannel('com.example.offgrid/nearby');

  static const String TYPING_STATUS_START = "__typing_start__";
  static const String TYPING_STATUS_STOP = "__typing_stop__";
  static const String READ_RECEIPT_PREFIX = "__read__";
  static const String DELETE_MESSAGE_PREFIX = "__delete__";
  static const String RECORDING_STATUS_START = "__recording_start__";
  static const String RECORDING_STATUS_STOP = "__recording_stop__";

  Function(Map<String, dynamic>)? onEndpointFound;
  Function(String)? onEndpointLost;
  Function(Map<String, dynamic>)? onConnectionResult;
  Function(String)? onDisconnected;
  Function(Map<String, dynamic>)? onPayloadReceived;
  Function(Map<String, dynamic>)? onTypingStatusChanged;
  Function(Map<String, dynamic>)? onMessageRead;
  Function(Map<String, dynamic>)? onMessageDeleted;
  Function(Map<String, dynamic>)? onRecordingStatusChanged;

  // Track connected endpoints
  final Set<String> _connectedEndpoints = {};

  NearbyService() {
    print("NearbyService: Constructor called");
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onEndpointFound':
        final args = Map<String, dynamic>.from(call.arguments);
        final endpointData = {
          'endpointId': args['id'],
          'endpointName': args['name'],
        };
        onEndpointFound?.call(endpointData);
        break;

      case 'onEndpointLost':
        print("Endpoint lost: ${call.arguments}");
        onEndpointLost?.call(call.arguments as String);
        break;

      case 'onConnectionResult':
        print("Connection result: ${call.arguments}");
        final result = Map<String, dynamic>.from(call.arguments);
        final status = result['status'] as String?;
        final endpointId = result['endpointId'] as String?;

        // Track connection status
        if (status == 'connected' && endpointId != null) {
          _connectedEndpoints.add(endpointId);
          print("Endpoint connected and tracked: $endpointId");
        } else if (endpointId != null) {
          _connectedEndpoints.remove(endpointId);
          print(
            "Endpoint connection failed, removed from tracking: $endpointId",
          );
        }

        onConnectionResult?.call(result);
        break;

      case 'onDisconnected':
        print("Disconnected: ${call.arguments}");
        final endpointId = call.arguments as String;
        _connectedEndpoints.remove(endpointId);
        print("Endpoint disconnected and removed from tracking: $endpointId");
        onDisconnected?.call(endpointId);
        break;

      case 'onPayloadReceived':
        print("Payload received: ${call.arguments}");
        final payload = Map<String, dynamic>.from(call.arguments);
        final message = payload['message'] as String? ?? '';

        if (message.startsWith(DELETE_MESSAGE_PREFIX)) {
          print("Delete message event received");
          final messageId = message.substring(DELETE_MESSAGE_PREFIX.length);
          onMessageDeleted?.call({
            'endpointId': payload['endpointId'],
            'messageId': messageId,
          });
        } else if (message.startsWith(RECORDING_STATUS_START)) {
          // ADD THIS
          print("Recording started");
          onRecordingStatusChanged?.call({
            'endpointId': payload['endpointId'],
            'isRecording': true,
          });
        } else if (message.startsWith(RECORDING_STATUS_STOP)) {
          // ADD THIS
          print("Recording stopped");
          onRecordingStatusChanged?.call({
            'endpointId': payload['endpointId'],
            'isRecording': false,
          });
        } else if (message.startsWith(TYPING_STATUS_START)) {
          print("Typing started");
          onTypingStatusChanged?.call({
            'endpointId': payload['endpointId'],
            'isTyping': true,
          });
        } else if (message.startsWith(TYPING_STATUS_STOP)) {
          print("Typing stopped");
          onTypingStatusChanged?.call({
            'endpointId': payload['endpointId'],
            'isTyping': false,
          });
        } else if (message.startsWith(READ_RECEIPT_PREFIX)) {
          print("Read receipt");
          final messageId = message.substring(READ_RECEIPT_PREFIX.length);
          onMessageRead?.call({
            'endpointId': payload['endpointId'],
            'messageId': messageId,
          });
        } else {
          print("Regular message received");
          onPayloadReceived?.call(payload);
        }
        break;

      case 'onTypingStatusChanged':
        print("Typing status changed: ${call.arguments}");
        onTypingStatusChanged?.call(Map<String, dynamic>.from(call.arguments));
        break;

      case 'onMessageRead':
        print("Message read: ${call.arguments}");
        onMessageRead?.call(Map<String, dynamic>.from(call.arguments));
        break;

      default:
        print("Unknown method: ${call.method}");
    }
  }

  // Check if a specific endpoint is connected
  bool isEndpointConnected(String endpointId) {
    return _connectedEndpoints.contains(endpointId);
  }

  // Get all connected endpoint IDs
  Set<String> get connectedEndpoints => Set.unmodifiable(_connectedEndpoints);

  // Check if any endpoint is connected
  bool get hasAnyConnection => _connectedEndpoints.isNotEmpty;

  Future<void> sendDeleteMessage(String endpointId, String messageId) async {
    final deleteEvent = "$DELETE_MESSAGE_PREFIX$messageId";
    try {
      await _channel.invokeMethod('sendMessage', {
        'endpointId': endpointId,
        'message': deleteEvent,
      });
      print("Delete event sent for message: $messageId");
    } on PlatformException catch (e) {
      print("Failed to send delete message: '${e.message}'.");
    }
  }

  Future<void> sendReadReceipt(String endpointId, String messageId) async {
    final receipt = "$READ_RECEIPT_PREFIX$messageId";
    try {
      await _channel.invokeMethod('sendMessage', {
        'endpointId': endpointId,
        'message': receipt,
      });
    } on PlatformException catch (e) {
      print("Failed to send read receipt: '${e.message}'.");
    }
  }

  Future<void> sendTypingStatus(String endpointId, bool isTyping) async {
    final status = isTyping ? TYPING_STATUS_START : TYPING_STATUS_STOP;
    try {
      await _channel.invokeMethod('sendMessage', {
        'endpointId': endpointId,
        'message': status,
      });
    } on PlatformException catch (e) {
      print("Failed to send typing status: '${e.message}'.");
    }
  }

  Future<void> sendRecordingStatus(String endpointId, bool isRecording) async {
    final status = isRecording ? RECORDING_STATUS_START : RECORDING_STATUS_STOP;
    try {
      await _channel.invokeMethod('sendMessage', {
        'endpointId': endpointId,
        'message': status,
      });
    } on PlatformException catch (e) {
      print("Failed to send recording status: '${e.message}'.");
    }
  }

  Future<void> startDiscovery(String username) async {
    print("Starting discovery with username: $username");
    try {
      await _channel.invokeMethod('startDiscovery', {'username': username});
      print("Discovery started successfully");
    } on PlatformException catch (e) {
      if (e.code == '8002' ||
          e.message?.contains('STATUS_ALREADY_DISCOVERING') == true) {
        print("Discovery already running - this is OK");
      } else {
        print("Failed to start discovery: '${e.message}'.");
      }
    }
  }

  Future<void> startAdvertising(String username) async {
    print("Starting advertising with username: $username");
    try {
      await _channel.invokeMethod('startAdvertising', {'username': username});
      print("Advertising started successfully");
    } on PlatformException catch (e) {
      if (e.code == '8001' ||
          e.message?.contains('STATUS_ALREADY_ADVERTISING') == true) {
        print("Advertising already running - this is OK");
      } else {
        print("Failed to start advertising: '${e.message}'.");
      }
    }
  }

  Future<void> connectToEndpoint(String endpointId) async {
    print("Attempting to connect to endpoint: $endpointId");
    try {
      await _channel.invokeMethod('connectToEndpoint', {
        'endpointId': endpointId,
      });
      print("Connection request sent successfully");
    } on PlatformException catch (e) {
      print("Failed to connect: '${e.message}'.");
    }
  }

  Future<void> sendMessage(String endpointId, String message) async {
    print("Sending message to $endpointId (length: ${message.length})");
    try {
      await _channel.invokeMethod('sendMessage', {
        'endpointId': endpointId,
        'message': message,
      });
      print("Message sent successfully");
    } on PlatformException catch (e) {
      print("Failed to send message: '${e.message}'.");
    }
  }

  Future<void> stopAllEndpoints() async {
    print("Stopping all endpoints");
    try {
      await _channel.invokeMethod('stopAllEndpoints');
      _connectedEndpoints.clear(); // Clear tracked connections
      print("All endpoints stopped successfully");
    } on PlatformException catch (e) {
      print("Failed to stop all endpoints: '${e.message}'.");
    }
  }

  static bool isSystemMessage(String message) {
    return message.startsWith(TYPING_STATUS_START) ||
        message.startsWith(TYPING_STATUS_STOP) ||
        message.startsWith(RECORDING_STATUS_START) || // ADD THIS
        message.startsWith(RECORDING_STATUS_STOP) ||
        message.startsWith(READ_RECEIPT_PREFIX) ||
        message.startsWith(DELETE_MESSAGE_PREFIX);
  }

  void dispose() {
    print("NearbyService: Disposing");
    _connectedEndpoints.clear();
    onEndpointFound = null;
    onEndpointLost = null;
    onConnectionResult = null;
    onDisconnected = null;
    onPayloadReceived = null;
    onTypingStatusChanged = null;
    onRecordingStatusChanged = null; 
    onMessageRead = null;
    onMessageDeleted = null;
  }
}
