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
    String path = join(await getDatabasesPath(), 'offgridtext.db');
    return await openDatabase(
      path,
      version: 2, // <-- Version incremented from 1 to 2
      onCreate: (db, version) async {
        // Added 'status TEXT' to the table creation
        await db.execute('''
          CREATE TABLE messages(
            id TEXT PRIMARY KEY,
            senderId TEXT,
            receiverId TEXT,
            text TEXT,
            timestamp TEXT,
            status TEXT 
          )
        ''');
      },
      // --- This onUpgrade block is new ---
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // Safely adds the new column to the table if it doesn't exist
          await db.execute("ALTER TABLE messages ADD COLUMN status TEXT");
        }
      },
      // ------------------------------------
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

  Future<List<Message>> getMessages(String peerId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'messages',
      where: 'senderId = ? OR receiverId = ?',
      whereArgs: [peerId, peerId],
      orderBy: 'timestamp ASC'
    );

    return List.generate(maps.length, (i) {
      return Message.fromMap(maps[i]);
    });
  }
}