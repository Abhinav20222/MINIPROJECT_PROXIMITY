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
      version: 3, // <-- Incremented to version 3
      onCreate: (db, version) async {
        // Updated with all necessary columns for new installs
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
            fileName TEXT
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