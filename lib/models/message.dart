// An enum to distinguish between message types
enum MessageType { text, image, file }

// An enum to represent the possible statuses of a message
enum MessageStatus { sent, delivered, read }

class Message {
  final String id;
  final String senderId;
  final String receiverId;
  final DateTime timestamp;
  final MessageStatus status;

  // Properties for message type and files
  final MessageType type;
  final String text; // For text messages
  final String? filePath; // For file/image messages
  final String? fileName; // To display the name of the file

  Message({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.timestamp,
    this.status = MessageStatus.sent,
    this.type = MessageType.text,
    this.text = '',
    this.filePath,
    this.fileName,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'senderId': senderId,
      'receiverId': receiverId,
      // --- This line has been corrected ---
      'timestamp': timestamp.toIso8601String(),
      // ------------------------------------
      'status': status.name,
      'type': type.name,
      'text': text,
      'filePath': filePath,
      'fileName': fileName,
    };
  }

  factory Message.fromMap(Map<String, dynamic> map) {
    return Message(
      id: map['id'],
      senderId: map['senderId'],
      receiverId: map['receiverId'],
      timestamp: DateTime.parse(map['timestamp']),
      status: MessageStatus.values.firstWhere(
        (e) => e.name == map['status'],
        orElse: () => MessageStatus.sent,
      ),
      type: MessageType.values.firstWhere(
        (e) => e.name == map['type'],
        orElse: () => MessageType.text,
      ),
      text: map['text'] ?? '',
      filePath: map['filePath'],
      fileName: map['fileName'],
    );
  }
}