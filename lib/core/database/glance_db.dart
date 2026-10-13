import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

import '../models/memory_models.dart';

/// Candidate retrieved chunk with hybrid scoring metrics.
class RetrievalCandidate {
  final Memory memory;
  final MemoryChunk chunk;
  final double vectorScore;
  final double ftsScore;
  final double temporalScore;
  final double metadataScore;
  final double finalScore;

  RetrievalCandidate({
    required this.memory,
    required this.chunk,
    required this.vectorScore,
    required this.ftsScore,
    required this.temporalScore,
    required this.metadataScore,
    required this.finalScore,
  });
}

/// Offline-first database service for Glance.
/// Manages SQLite memory metadata, FTS5 BM25 virtual table indices, vector embeddings, and relationships.
class GlanceDatabase {
  static final GlanceDatabase instance = GlanceDatabase._internal();
  GlanceDatabase._internal();

  Database? _db;

  static const String hiddenStorageDir = '/storage/emulated/0/Android/media/com.example.glance/.glance';
  static const String legacyDownloadDbDir = '/storage/emulated/0/Download/Glance/db';

  final StreamController<void> _changeNotifier = StreamController<void>.broadcast();
  Stream<void> get changeStream => _changeNotifier.stream;

  Database? get database => _db;
  bool get isReady => _db != null && _db!.isOpen;
  Timer? _backupDebounceTimer;

  void notifyListeners() {
    if (!_changeNotifier.isClosed) {
      _changeNotifier.add(null);
    }
    _scheduleDebouncedBackup();
  }

  void _scheduleDebouncedBackup() {
    _backupDebounceTimer?.cancel();
    _backupDebounceTimer = Timer(const Duration(seconds: 30), () {
      _backupDb();
    });
  }

  /// Manually triggers database sync/backup to hidden storage.
  Future<void> triggerBackup() async {
    _backupDebounceTimer?.cancel();
    await _backupDb();
  }

  /// Alias for triggerBackup to sync database to hidden Android media storage.
  Future<void> syncToMediaStorage() => triggerBackup();

  Future<Directory> _getHiddenStoreDir() async {
    final dir = Directory(hiddenStorageDir);
    if (!await dir.exists()) {
      try {
        await dir.create(recursive: true);
      } catch (e) {
        debugPrint('[GlanceDatabase] Note: Could not create hidden storage dir: $e');
      }
    }
    try {
      final nomediaFile = File(join(dir.path, '.nomedia'));
      if (!await nomediaFile.exists()) {
        await nomediaFile.create();
      }
    } catch (_) {}
    return dir;
  }

  Future<void> _migrateLegacyDownloadDb(String hiddenDbPath) async {
    try {
      final legacyFile = File(join(legacyDownloadDbDir, 'glance.db'));
      if (await legacyFile.exists()) {
        final hiddenFile = File(hiddenDbPath);
        if (!await hiddenFile.exists() || (await legacyFile.length() > await hiddenFile.length())) {
          await legacyFile.copy(hiddenDbPath);
          debugPrint('[GlanceDatabase] Migrated legacy DB from Downloads to hidden store: $hiddenDbPath');
        }
        try {
          await legacyFile.delete();
          final legacyDir = Directory(legacyDownloadDbDir);
          if (await legacyDir.exists()) {
            final files = legacyDir.listSync();
            if (files.isEmpty) {
              await legacyDir.delete();
            }
          }
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('[GlanceDatabase] Legacy migration error: $e');
    }
  }

  Future<void> _ensureAllTablesExist(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS memories (
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        title TEXT NOT NULL,
        content TEXT NOT NULL,
        source TEXT,
        source_app TEXT,
        source_package TEXT,
        url TEXT,
        file_path TEXT,
        thumbnail_path TEXT,
        image_base64 TEXT,
        summary TEXT,
        sha_hash TEXT,
        captured_at INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        session_id TEXT,
        location_id TEXT,
        device_id TEXT,
        is_favorite INTEGER NOT NULL DEFAULT 0,
        is_archived INTEGER NOT NULL DEFAULT 0,
        is_hidden INTEGER NOT NULL DEFAULT 0,
        is_processed INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS app_icons (
        package_name TEXT PRIMARY KEY,
        icon_base64 TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS collections (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        description TEXT,
        icon TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS collection_items (
        collection_id TEXT NOT NULL,
        memory_id TEXT NOT NULL,
        added_at INTEGER NOT NULL,
        PRIMARY KEY (collection_id, memory_id),
        FOREIGN KEY (memory_id) REFERENCES memories (id) ON DELETE CASCADE,
        FOREIGN KEY (collection_id) REFERENCES collections (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS app_usage_history (
        package_name TEXT NOT NULL,
        date_key TEXT NOT NULL,
        app_name TEXT NOT NULL,
        usage_time_ms INTEGER NOT NULL DEFAULT 0,
        open_count INTEGER NOT NULL DEFAULT 0,
        last_updated INTEGER NOT NULL,
        PRIMARY KEY (package_name, date_key)
      )
    ''');

    try {
      await db.execute('ALTER TABLE memories ADD COLUMN sha_hash TEXT;');
    } catch (_) {}
    try {
      await db.execute('ALTER TABLE memories ADD COLUMN is_processed INTEGER NOT NULL DEFAULT 0;');
    } catch (_) {}
    try {
      await db.execute('ALTER TABLE memories ADD COLUMN image_base64 TEXT;');
    } catch (_) {}
    try {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS app_usage_history (
          package_name TEXT NOT NULL,
          date_key TEXT NOT NULL,
          app_name TEXT NOT NULL,
          usage_time_ms INTEGER NOT NULL DEFAULT 0,
          open_count INTEGER NOT NULL DEFAULT 0,
          last_updated INTEGER NOT NULL,
          PRIMARY KEY (package_name, date_key)
        );
      ''');
    } catch (_) {}
  }

  Future<void> _backupDb() async {
    try {
      if (_db == null || !_db!.isOpen) return;

      // PRAGMA wal_checkpoint(FULL) ensures all in-memory WAL data is committed to disk
      try {
        await _db!.rawQuery('PRAGMA wal_checkpoint(FULL);');
      } catch (_) {}

      final dbPath = _db!.path;
      final hiddenDir = await _getHiddenStoreDir();
      final backupPath = join(hiddenDir.path, 'glance.db');

      final srcFile = File(dbPath);
      if (await srcFile.exists()) {
        await srcFile.copy(backupPath);
        debugPrint('[GlanceDatabase] Synced entire Glance DB to hidden media store: $backupPath');
      }
    } catch (e) {
      debugPrint('[GlanceDatabase] Backup failure: $e');
    }
  }

  Future<void> initialize() async {
    if (_db != null && _db!.isOpen) return;

    final hiddenDir = await _getHiddenStoreDir();
    final hiddenDbPath = join(hiddenDir.path, 'glance.db');

    // 1. Move/migrate any legacy Downloads/Glance/db/glance.db to the hidden store
    await _migrateLegacyDownloadDb(hiddenDbPath);

    final dbDir = await getDatabasesPath();
    final internalDbPath = join(dbDir, 'glance.db');

    final hiddenDbFile = File(hiddenDbPath);
    final internalDbFile = File(internalDbPath);

    final hiddenExists = await hiddenDbFile.exists();
    final internalExists = await internalDbFile.exists();

    debugPrint('[GlanceDatabase] Checking DB on startup: hiddenExists=$hiddenExists, internalExists=$internalExists');

    // 2. Check if DB is already available in the hidden store
    if (hiddenExists) {
      final hiddenLen = await hiddenDbFile.length();
      final internalLen = internalExists ? await internalDbFile.length() : 0;

      // If internal DB is missing or hidden DB is newer/larger, retrieve and restore it!
      if (!internalExists || hiddenLen > internalLen) {
        try {
          final parentDir = Directory(dbDir);
          if (!await parentDir.exists()) {
            await parentDir.create(recursive: true);
          }
          await hiddenDbFile.copy(internalDbPath);
          debugPrint('[GlanceDatabase] Retrieved existing DB from hidden store ($hiddenLen bytes) into internal store.');
        } catch (e) {
          debugPrint('[GlanceDatabase] Could not restore from hidden store: $e');
        }
      }
    }

    // 3. Open and retrieve database connection (if not exists, SQLite creates it)
    _db = await openDatabase(
      internalDbPath,
      version: 1,
      onOpen: (db) async {
        await _ensureAllTablesExist(db);
      },
      onCreate: (db, version) async {
        await _ensureAllTablesExist(db);
      },
    );

    debugPrint('[GlanceDatabase] Database connection active & verified: ${_db!.path}');

    // 4. Ensure the entire DB is synced/persisted to hidden store
    await _backupDb();

    // 5. Notify listeners so all screens immediately display retrieved content
    if (!_changeNotifier.isClosed) {
      _changeNotifier.add(null);
    }
  }

  /// Insert or update a Memory record.
  Future<void> insertMemory(Memory memory) async {
    await initialize();
    await _db!.insert(
      'memories',
      memory.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    notifyListeners();
  }

  /// Updates or backfills the Base64 image copy for a specific memory record.
  Future<void> updateMemoryImageBase64(String memoryId, String imageBase64) async {
    await initialize();
    await _db!.update(
      'memories',
      {'image_base64': imageBase64},
      where: 'id = ?',
      whereArgs: [memoryId],
    );
  }

  /// Delete a Memory record and its collection associations.
  Future<void> deleteMemory(String id) async {
    await initialize();
    await _db!.delete('memories', where: 'id = ?', whereArgs: [id]);
    await _db!.delete('collection_items', where: 'memory_id = ?', whereArgs: [id]);
    notifyListeners();
  }

  /// Check if memory with given file path exists
  Future<bool> hasMemoryWithFilePath(String filePath) async {
    if (filePath.isEmpty) return false;
    await initialize();
    final maps = await _db!.query(
      'memories',
      columns: ['id'],
      where: 'file_path = ? OR thumbnail_path = ?',
      whereArgs: [filePath, filePath],
      limit: 1,
    );
    return maps.isNotEmpty;
  }

  /// Get memory by file path if present
  Future<Memory?> getMemoryByFilePath(String filePath) async {
    if (filePath.isEmpty) return null;
    await initialize();
    final maps = await _db!.query(
      'memories',
      where: 'file_path = ? OR thumbnail_path = ?',
      whereArgs: [filePath, filePath],
      limit: 1,
    );
    if (maps.isNotEmpty) {
      return Memory.fromMap(maps.first);
    }
    return null;
  }

  /// Check if memory with given SHA-256 hash exists
  Future<bool> hasMemoryWithShaHash(String shaHash) async {
    if (shaHash.isEmpty) return false;
    await initialize();
    final maps = await _db!.query(
      'memories',
      columns: ['id'],
      where: 'sha_hash = ?',
      whereArgs: [shaHash],
      limit: 1,
    );
    return maps.isNotEmpty;
  }

  /// Get memory by SHA-256 hash if present
  Future<Memory?> getMemoryByShaHash(String shaHash) async {
    if (shaHash.isEmpty) return null;
    await initialize();
    final maps = await _db!.query(
      'memories',
      where: 'sha_hash = ?',
      whereArgs: [shaHash],
      limit: 1,
    );
    if (maps.isNotEmpty) {
      return Memory.fromMap(maps.first);
    }
    return null;
  }

  /// Fetch memory by ID.
  Future<Memory?> getMemory(String id) async {
    await initialize();
    final maps = await _db!.query(
      'memories',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isNotEmpty) {
      return Memory.fromMap(maps.first);
    }
    return null;
  }

  /// List all memories (sorted descending by capturedAt timestamp, unique by file path/signature).
  Future<List<Memory>> getAllMemories() async {
    await initialize();
    final maps = await _db!.query(
      'memories',
      orderBy: 'captured_at DESC',
    );
    final list = maps.map((m) => Memory.fromMap(m)).toList();

    final seenPaths = <String>{};
    final seenSigs = <String>{};
    final result = <Memory>[];

    for (final mem in list) {
      final path = mem.filePath ?? mem.thumbnailPath;
      if (path != null && path.trim().isNotEmpty) {
        final normPath = path.trim();
        if (seenPaths.contains(normPath)) continue;
        seenPaths.add(normPath);
      } else {
        final sig = '${mem.type}_${mem.title}_${mem.sourcePackage}_${mem.capturedAt}';
        if (seenSigs.contains(sig)) continue;
        seenSigs.add(sig);
      }
      result.add(mem);
    }

    return result;
  }

  static final Map<String, String> _appIconCache = {};

  /// Synchronously get cached base64 icon if available in memory
  String? getCachedAppIcon(String packageName) {
    return _appIconCache[packageName];
  }

  /// Save an app icon base64
  Future<void> saveAppIcon(String packageName, String base64Icon) async {
    _appIconCache[packageName] = base64Icon;
    await initialize();
    await _db!.insert(
      'app_icons',
      {
        'package_name': packageName,
        'icon_base64': base64Icon,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    // Note: Do not call notifyListeners() here to avoid triggering full-table memory reload cascades
  }

  /// Get an app icon base64
  Future<String?> getAppIcon(String packageName) async {
    if (_appIconCache.containsKey(packageName)) {
      return _appIconCache[packageName];
    }
    await initialize();
    final maps = await _db!.query(
      'app_icons',
      columns: ['icon_base64'],
      where: 'package_name = ?',
      whereArgs: [packageName],
    );
    if (maps.isNotEmpty) {
      final iconBase64 = maps.first['icon_base64'] as String?;
      if (iconBase64 != null) {
        _appIconCache[packageName] = iconBase64;
      }
      return iconBase64;
    }
    return null;
  }

  /// The rest of the functions (chunks, vectors) are intentionally left empty/mocked 
  /// for this specific implementation since we focus on SQFlite for Memory objects first.
  Future<void> insertChunk(MemoryChunk chunk) async {}
  Future<void> insertEmbedding(String chunkId, List<double> embedding) async {}
  Future<void> insertRelationship(MemoryRelationship rel) async {}
  Future<List<MemoryChunk>> searchFTS5(String queryKeywords, {int limit = 30}) async => [];
  Future<List<MapEntry<MemoryChunk, double>>> searchVectorCosine(List<double> queryVector, {int limit = 30}) async => [];
  Future<List<Memory>> getMemoriesInTimeWindow(int startTime, int endTime) async {
    await initialize();
    final maps = await _db!.query(
      'memories',
      where: 'captured_at >= ? AND captured_at <= ?',
      whereArgs: [startTime, endTime],
    );
    return maps.map((m) => Memory.fromMap(m)).toList();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // SMART SEARCH API (Working SQL-based search — primary search path)
  // ═══════════════════════════════════════════════════════════════════════

  /// Intelligent multi-filter search across the memories table.
  /// Combines type filtering, app name matching, keyword search, and time windowing.
  /// This is the primary working search method since FTS5/Vector stubs are not yet wired.
  Future<List<Memory>> searchMemoriesSmart({
    String? query,
    List<String>? keywords,
    String? type,
    String? sourceApp,
    int? startTime,
    int? endTime,
    int limit = 20,
  }) async {
    await initialize();

    final conditions = <String>[];
    final args = <dynamic>[];

    // Type filter (copied_text ↔ clipboard are treated as equivalent, visual includes photos, screenshots, camera_capture)
    if (type != null && type.isNotEmpty) {
      if (type == 'copied_text') {
        conditions.add("(type = ? OR type = ?)");
        args.addAll(['copied_text', 'clipboard']);
      } else if (type == 'screenshot' || type == 'visual' || type == 'image' || type == 'photo') {
        conditions.add("(type IN ('screenshot', 'photo', 'camera_capture') OR file_path IS NOT NULL OR thumbnail_path IS NOT NULL)");
      } else if (type == 'call_log' || type == 'call') {
        conditions.add("(type = 'call_log' OR (type = 'notification' AND (source_app = 'Phone' OR source = 'Phone' OR title LIKE '%Call%' OR content LIKE '%Call%')))");
      } else if (type == 'sms' || type == 'message') {
        conditions.add("(type = 'sms' OR (type = 'notification' AND (source_app = 'Messages' OR source = 'Messages' OR title LIKE '%SMS%' OR content LIKE '%SMS%')))");
      } else if (type == 'calendar_event' || type == 'calendar') {
        conditions.add("(type = 'calendar_event' OR (type = 'notification' AND (source_app = 'Calendar' OR title LIKE '%Meeting%' OR title LIKE '%Event%')))");
      } else if (type == 'notification') {
        conditions.add("(type = 'notification' OR type = 'call_log' OR type = 'sms' OR type = 'calendar_event')");
      } else {
        conditions.add("type = ?");
        args.add(type);
      }
    }

    // Source app filter (fuzzy match across source_app, source, source_package, title)
    if (sourceApp != null && sourceApp.isNotEmpty) {
      conditions.add(
        "(source_app LIKE ? OR source LIKE ? OR source_package LIKE ? OR title LIKE ? OR content LIKE ?)",
      );
      final pattern = '%$sourceApp%';
      args.addAll([pattern, pattern, pattern, pattern, pattern]);
    }

    // Time window filter
    if (startTime != null) {
      conditions.add("captured_at >= ?");
      args.add(startTime);
    }
    if (endTime != null) {
      conditions.add("captured_at <= ?");
      args.add(endTime);
    }

    // Keyword search across title, content, source_app, and summary (OR logic — match any keyword)
    if (keywords != null && keywords.isNotEmpty) {
      final keywordConditions = <String>[];
      for (final kw in keywords) {
        keywordConditions.add("(title LIKE ? OR content LIKE ? OR source_app LIKE ? OR summary LIKE ?)");
        final pattern = '%$kw%';
        args.addAll([pattern, pattern, pattern, pattern]);
      }
      conditions.add("(${keywordConditions.join(' OR ')})");
    }

    // Raw query fallback: split into words and search each
    if (query != null && query.isNotEmpty && (keywords == null || keywords.isEmpty)) {
      final words = query.toLowerCase().split(RegExp(r'\s+'));
      final queryConditions = <String>[];
      for (final word in words) {
        if (word.length < 2) continue;
        queryConditions.add("(title LIKE ? OR content LIKE ? OR source_app LIKE ? OR summary LIKE ?)");
        final pattern = '%$word%';
        args.addAll([pattern, pattern, pattern, pattern]);
      }
      if (queryConditions.isNotEmpty) {
        conditions.add("(${queryConditions.join(' OR ')})");
      }
    }

    // Always exclude hidden memories
    conditions.add("is_hidden = 0");

    final whereClause = conditions.isNotEmpty ? conditions.join(' AND ') : 'is_hidden = 0';

    final maps = await _db!.query(
      'memories',
      where: whereClause,
      whereArgs: args,
      orderBy: 'captured_at DESC',
      limit: limit,
    );

    return maps.map((m) => Memory.fromMap(m)).toList();
  }

  /// Returns all memories of a specific type, ordered by most recent.
  Future<List<Memory>> getMemoriesByType(String type, {int limit = 20}) async {
    await initialize();
    String where;
    List<dynamic> whereArgs;

    if (type == 'copied_text') {
      where = "(type = ? OR type = ?) AND is_hidden = 0";
      whereArgs = ['copied_text', 'clipboard'];
    } else if (type == 'screenshot' || type == 'visual' || type == 'image' || type == 'photo') {
      where = "(type IN ('screenshot', 'photo', 'camera_capture') OR file_path IS NOT NULL OR thumbnail_path IS NOT NULL) AND is_hidden = 0";
      whereArgs = [];
    } else if (type == 'call_log' || type == 'call') {
      where = "(type = 'call_log' OR (type = 'notification' AND (source_app = 'Phone' OR source = 'Phone' OR title LIKE '%Call%' OR content LIKE '%Call%'))) AND is_hidden = 0";
      whereArgs = [];
    } else if (type == 'sms' || type == 'message') {
      where = "(type = 'sms' OR (type = 'notification' AND (source_app = 'Messages' OR source = 'Messages' OR title LIKE '%SMS%' OR content LIKE '%SMS%'))) AND is_hidden = 0";
      whereArgs = [];
    } else {
      where = "type = ? AND is_hidden = 0";
      whereArgs = [type];
    }

    final maps = await _db!.query(
      'memories',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'captured_at DESC',
      limit: limit,
    );
    return maps.map((m) => Memory.fromMap(m)).toList();
  }

  /// Retrieves all visual memories (photos, screenshots, camera captures) ordered by captured_at DESC
  Future<List<Memory>> getAllVisualMemories({
    int? startTime,
    int? endTime,
    int limit = 500,
  }) async {
    await initialize();
    final conditions = <String>[
      "(type IN ('screenshot', 'photo', 'camera_capture') OR file_path IS NOT NULL OR thumbnail_path IS NOT NULL)",
      "is_hidden = 0",
    ];
    final args = <dynamic>[];
    if (startTime != null) {
      conditions.add("captured_at >= ?");
      args.add(startTime);
    }
    if (endTime != null) {
      conditions.add("captured_at <= ?");
      args.add(endTime);
    }
    final maps = await _db!.query(
      'memories',
      where: conditions.join(' AND '),
      whereArgs: args,
      orderBy: 'captured_at DESC',
      limit: limit,
    );
    return maps.map((m) => Memory.fromMap(m)).toList();
  }

  /// Records or updates daily app usage stats in the app_usage_history table.
  /// Even if Android system purges old usage stats, this SQLite record remains persistent forever.
  Future<void> upsertAppUsageHistory({
    required String packageName,
    required String appName,
    required String dateKey, // e.g., '2026-10-13'
    required int usageTimeMs,
    required int openCount,
    int? timestamp,
  }) async {
    await initialize();
    final now = timestamp ?? DateTime.now().millisecondsSinceEpoch;

    // Check existing record for this app on this date
    final existing = await _db!.query(
      'app_usage_history',
      where: 'package_name = ? AND date_key = ?',
      whereArgs: [packageName, dateKey],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      final prevTime = existing.first['usage_time_ms'] as int? ?? 0;
      final prevOpens = existing.first['open_count'] as int? ?? 0;

      // Keep the maximum value so it never regresses even if system resets daily counter
      final finalTime = usageTimeMs > prevTime ? usageTimeMs : prevTime;
      final finalOpens = openCount > prevOpens ? openCount : prevOpens;

      await _db!.update(
        'app_usage_history',
        {
          'app_name': appName,
          'usage_time_ms': finalTime,
          'open_count': finalOpens,
          'last_updated': now,
        },
        where: 'package_name = ? AND date_key = ?',
        whereArgs: [packageName, dateKey],
      );
    } else {
      await _db!.insert(
        'app_usage_history',
        {
          'package_name': packageName,
          'date_key': dateKey,
          'app_name': appName,
          'usage_time_ms': usageTimeMs,
          'open_count': openCount,
          'last_updated': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    _backupDb();
  }

  /// Retrieves the persistent daily usage record for a specific app on a specific date.
  Future<Map<String, dynamic>?> getDailyAppUsage(String packageName, String dateKey) async {
    await initialize();
    final res = await _db!.query(
      'app_usage_history',
      where: 'package_name = ? AND date_key = ?',
      whereArgs: [packageName, dateKey],
      limit: 1,
    );
    if (res.isEmpty) return null;
    return Map<String, dynamic>.from(res.first);
  }

  /// Retrieves all historical daily usage records for an app (ordered newest first).
  Future<List<Map<String, dynamic>>> getAppUsageHistory(String packageName, {int limit = 30}) async {
    await initialize();
    final res = await _db!.query(
      'app_usage_history',
      where: 'package_name = ?',
      whereArgs: [packageName],
      orderBy: 'date_key DESC',
      limit: limit,
    );
    return res.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  /// Cleans up duplicate copied_text memories in SQLite DB, keeping the earliest created record for each unique content.
  Future<void> cleanDuplicateCopiedTexts() async {
    await cleanAllDuplicateMemories();
  }

  /// Cleans up ALL duplicate memories across all categories (screenshots, photos, docs, notifications, app activities, clipboard).
  /// Keeps the most recent record for each unique sha_hash, file_path or signature.
  Future<int> cleanAllDuplicateMemories() async {
    await initialize();
    int deletedCount = 0;
    try {
      // Purge any existing government/public holiday or festival entries from DB
      await _db!.delete(
        'memories',
        where: 'LOWER(title) LIKE ? OR LOWER(title) LIKE ? OR LOWER(content) LIKE ? OR LOWER(title) LIKE ?',
        whereArgs: ['%holiday%', '%festival%', '%holiday%', '%birthday%'],
      );

      final maps = await _db!.query('memories', orderBy: 'captured_at DESC');
      final list = maps.map((m) => Memory.fromMap(m)).toList();

      final Set<String> seenShaHashes = {};
      final Set<String> seenFilePaths = {};
      final Set<String> seenSignatures = {};
      final List<String> idsToDelete = [];

      for (final mem in list) {
        final sha = mem.shaHash ?? Memory.computeShaHash(
          title: mem.title,
          type: mem.type,
          content: mem.content,
          filePath: mem.filePath ?? mem.thumbnailPath,
          sourceApp: mem.sourceApp,
          sourcePackage: mem.sourcePackage,
        );

        if (seenShaHashes.contains(sha)) {
          idsToDelete.add(mem.id);
          continue;
        } else {
          seenShaHashes.add(sha);
        }

        final filePath = mem.filePath ?? mem.thumbnailPath;
        if (filePath != null && filePath.trim().isNotEmpty) {
          final normPath = filePath.trim();
          if (seenFilePaths.contains(normPath)) {
            idsToDelete.add(mem.id);
            continue;
          } else {
            seenFilePaths.add(normPath);
          }
        } else {
          final sig = '${mem.type}_${mem.title}_${mem.sourcePackage}_${mem.capturedAt}';
          if (seenSignatures.contains(sig)) {
            idsToDelete.add(mem.id);
            continue;
          } else {
            seenSignatures.add(sig);
          }
        }
      }

      for (final id in idsToDelete) {
        await _db!.delete('memories', where: 'id = ?', whereArgs: [id]);
        await _db!.delete('collection_items', where: 'memory_id = ?', whereArgs: [id]);
        deletedCount++;
      }
      if (deletedCount > 0) {
        notifyListeners();
      }
    } catch (_) {}
    return deletedCount;
  }

  /// Returns total count of saved memories in database.
  Future<int> getTotalMemoryCount() async {
    await initialize();
    try {
      final res = await _db!.rawQuery('SELECT COUNT(*) as cnt FROM memories');
      return (res.first['cnt'] as int?) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Returns approximate database storage size in bytes.
  Future<int> getDatabaseSizeBytes() async {
    await initialize();
    try {
      final hiddenPath = join(hiddenStorageDir, 'glance.db');
      final f = File(hiddenPath);
      if (await f.exists()) {
        return await f.length();
      }
    } catch (_) {}
    return 0;
  }

  /// Completely wipes all memories, chunks, and vector embeddings from local database.
  Future<int> clearAllMemories() async {
    await initialize();
    int count = 0;
    try {
      count = await _db!.delete('memories');
      await _db!.delete('memory_chunks');
      await _db!.delete('embeddings');
      await _db!.delete('collection_items');
      notifyListeners();
    } catch (_) {}
    return count;
  }

  // --- COLLECTIONS API ---

  Future<void> createCollection(String id, String title, {String? description, String? icon}) async {
    await initialize();
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db!.insert(
      'collections',
      {
        'id': id,
        'title': title,
        'description': description,
        'icon': icon,
        'created_at': now,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    notifyListeners();
  }

  Future<void> deleteCollection(String id) async {
    await initialize();
    await _db!.delete('collections', where: 'id = ?', whereArgs: [id]);
    await _db!.delete('collection_items', where: 'collection_id = ?', whereArgs: [id]);
    notifyListeners();
  }

  Future<List<Map<String, dynamic>>> getCollections() async {
    await initialize();
    return await _db!.query('collections', orderBy: 'updated_at DESC');
  }

  Future<void> addMemoryToCollection(String collectionId, String memoryId) async {
    await initialize();
    await _db!.insert(
      'collection_items',
      {
        'collection_id': collectionId,
        'memory_id': memoryId,
        'added_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    notifyListeners();
  }

  Future<void> removeMemoryFromCollection(String collectionId, String memoryId) async {
    await initialize();
    await _db!.delete(
      'collection_items',
      where: 'collection_id = ? AND memory_id = ?',
      whereArgs: [collectionId, memoryId],
    );
    notifyListeners();
  }

  Future<List<Memory>> getMemoriesForCollection(String collectionId) async {
    await initialize();
    final maps = await _db!.rawQuery('''
      SELECT m.* FROM memories m
      INNER JOIN collection_items ci ON m.id = ci.memory_id
      WHERE ci.collection_id = ?
      ORDER BY ci.added_at DESC
    ''', [collectionId]);
    return maps.map((m) => Memory.fromMap(m)).toList();
  }

  Future<void> addMemoryAndRelated(String collectionId, Memory memory) async {
    await initialize();
    
    // Add the selected memory
    await _db!.insert(
      'collection_items',
      {
        'collection_id': collectionId,
        'memory_id': memory.id,
        'added_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    
    // Find related memories
    // 1. Same session
    if (memory.sessionId != null && memory.sessionId!.isNotEmpty) {
      final sessionMaps = await _db!.query('memories', where: 'session_id = ? AND id != ?', whereArgs: [memory.sessionId, memory.id]);
      for (final sm in sessionMaps) {
        await _db!.insert(
          'collection_items',
          {
            'collection_id': collectionId,
            'memory_id': sm['id'] as String,
            'added_at': DateTime.now().millisecondsSinceEpoch,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    }

    // 2. Temporal closeness (within 5 minutes of this memory)
    final timeWindow = 5 * 60 * 1000;
    final timeMaps = await _db!.query(
      'memories',
      where: 'id != ? AND captured_at BETWEEN ? AND ?',
      whereArgs: [memory.id, memory.capturedAt - timeWindow, memory.capturedAt + timeWindow],
    );
    for (final tm in timeMaps) {
      await _db!.insert(
        'collection_items',
        {
          'collection_id': collectionId,
          'memory_id': tm['id'] as String,
          'added_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    
    // 3. Same location (if location is tagged)
    if (memory.locationId != null && memory.locationId!.isNotEmpty) {
      final locMaps = await _db!.query(
        'memories',
        where: 'location_id = ? AND id != ?',
        whereArgs: [memory.locationId, memory.id],
      );
      for (final lm in locMaps) {
        await _db!.insert(
          'collection_items',
          {
            'collection_id': collectionId,
            'memory_id': lm['id'] as String,
            'added_at': DateTime.now().millisecondsSinceEpoch,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    }

    notifyListeners();
  }
}
