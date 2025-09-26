import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/message.dart';

class SQLiteService {
  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  Future<Database> _initDB() async {
    String path = join(await getDatabasesPath(), 'offgrid.db');
    return await openDatabase(
      path,
      version: 4, // Incremented to version 4 for voice support
      onCreate: (db, version) async {
        // Updated with all necessary columns including voice support
        await db.execute('''
          CREATE TABLE messages(
            id TEXT PRIMARY KEY,
            senderId TEXT,
            receiverId TEXT,
            timestamp TEXT,
            status TEXT,
            type TEXT,
            text TEXT,
            filePath TEXT,
            fileName TEXT,
            voiceDurationMs INTEGER
          )
        ''');
      },
      // Updated to handle migrations for existing installs
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute("ALTER TABLE messages ADD COLUMN status TEXT");
        }
        if (oldVersion < 3) {
          await db.execute("ALTER TABLE messages ADD COLUMN type TEXT");
          await db.execute("ALTER TABLE messages ADD COLUMN filePath TEXT");
          await db.execute("ALTER TABLE messages ADD COLUMN fileName TEXT");
        }
        if (oldVersion < 4) {
          // Add voice duration column for voice message support
          await db.execute(
            "ALTER TABLE messages ADD COLUMN voiceDurationMs INTEGER",
          );
        }
      },
    );
  }

  Future<void> insertMessage(Message message) async {
    final db = await database;
    await db.insert(
      'messages',
      message.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateMessageStatus(
    String messageId,
    MessageStatus status,
  ) async {
    final db = await database;
    await db.update(
      'messages',
      {'status': status.name},
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }

  Future<List<Message>> getMessages(String peerId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'messages',
      where: 'senderId = ? OR receiverId = ?',
      whereArgs: [peerId, peerId],
      orderBy: 'timestamp ASC',
    );

    return List.generate(maps.length, (i) {
      return Message.fromMap(maps[i]);
    });
  }

  Future<List<Message>> getAllMessages() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'messages',
      orderBy: 'timestamp DESC',
    );

    return List.generate(maps.length, (i) {
      return Message.fromMap(maps[i]);
    });
  }

  Future<void> deleteMessage(String messageId) async {
    final db = await database;
    await db.delete('messages', where: 'id = ?', whereArgs: [messageId]);
  }

  Future<void> clearAllMessages() async {
    final db = await database;
    await db.delete('messages');
  }

  Future<Message?> getMessage(String messageId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'messages',
      where: 'id = ?',
      whereArgs: [messageId],
    );

    if (maps.isNotEmpty) {
      return Message.fromMap(maps.first);
    }
    return null;
  }

  Future<int> getUnreadMessageCount(String peerId) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM messages WHERE senderId = ? AND status != ?',
      [peerId, MessageStatus.read.name],
    );

    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<void> updateUsernameInMessages({
    required String oldUsername,
    required String newUsername,
  }) async {
    final db = await database;

    // Start a transaction to ensure all updates happen together
    await db.transaction((txn) async {
      // Update messages where the user was the sender
      await txn.update(
        'messages',
        {'senderId': newUsername},
        where: 'senderId = ?',
        whereArgs: [oldUsername],
      );

      // Update messages where the user was the receiver
      await txn.update(
        'messages',
        {'receiverId': newUsername},
        where: 'receiverId = ?',
        whereArgs: [oldUsername],
      );
    });
    print('Updated username in messages from "$oldUsername" to "$newUsername"');
  }
}
