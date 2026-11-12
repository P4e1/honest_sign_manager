import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/marking_code.dart';
import '../models/product.dart';
import '../models/upload_record.dart';

/// Совпадение кода с уже загруженным (для проверки дублей).
class DuplicateHit {
  final String raw;
  final int recordId;
  const DuplicateHit(this.raw, this.recordId);
}

/// Локальный SQLite-кеш.
/// Может быть полностью удалён и пересоздан из файлового сервера.
class DatabaseService {
  late final Database _db;
  late final String path;

  Future<void> init() async {
    sqfliteFfiInit();
    final dir = await getApplicationSupportDirectory();
    await Directory(dir.path).create(recursive: true);
    path = p.join(dir.path, 'cache.db');

    _db = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 2,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      ),
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE products (
        id     INTEGER PRIMARY KEY,
        name   TEXT    NOT NULL,
        hidden INTEGER NOT NULL DEFAULT 0
      )''');

    await db.execute('''
      CREATE TABLE upload_records (
        id                INTEGER PRIMARY KEY AUTOINCREMENT,
        store_id          TEXT    NOT NULL UNIQUE,
        terminal_url      TEXT    NOT NULL,
        terminal_key      TEXT    NOT NULL,
        product_id        INTEGER NOT NULL,
        product_name      TEXT    NOT NULL,
        file_name         TEXT    NOT NULL,
        codes_count       INTEGER NOT NULL,
        http_status       INTEGER NOT NULL,
        status            TEXT    NOT NULL,
        uploaded_at       TEXT    NOT NULL,
        deleted_at        TEXT,
        author            TEXT    NOT NULL DEFAULT '',
        pending_record    INTEGER NOT NULL DEFAULT 0,
        pending_tombstone INTEGER NOT NULL DEFAULT 0
      )''');

    await db.execute('''
      CREATE TABLE codes (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        record_id    INTEGER NOT NULL REFERENCES upload_records(id) ON DELETE CASCADE,
        raw          TEXT    NOT NULL,
        base64       TEXT    NOT NULL,
        terminal_key TEXT    NOT NULL,
        type         TEXT,
        status       TEXT,
        created_at   TEXT
      )''');

    await db.execute(
        'CREATE INDEX idx_codes_terminal_raw ON codes(terminal_key, raw)');
    await db.execute('CREATE INDEX idx_codes_record ON codes(record_id)');
    await db.execute(
        'CREATE UNIQUE INDEX idx_records_store_id ON upload_records(store_id)');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
          'ALTER TABLE upload_records ADD COLUMN store_id TEXT NOT NULL DEFAULT ""');
      await db.execute(
          'ALTER TABLE upload_records ADD COLUMN author TEXT NOT NULL DEFAULT ""');
      await db.execute(
          'ALTER TABLE upload_records ADD COLUMN pending_record INTEGER NOT NULL DEFAULT 0');
      await db.execute(
          'ALTER TABLE upload_records ADD COLUMN pending_tombstone INTEGER NOT NULL DEFAULT 0');
    }
  }

  // ──────────────────────── ТОВАРЫ ────────────────────────

  Future<void> replaceProducts(List<Product> products) async {
    await _db.transaction((txn) async {
      await txn.delete('products');
      final batch = txn.batch();
      for (final product in products) {
        batch.insert('products', product.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    });
  }

  Future<List<Product>> getProducts() async {
    final rows = await _db.query('products', orderBy: 'id');
    return rows.map(Product.fromMap).toList();
  }

  // ──────────────────────── ЗАПИСИ ────────────────────────

  /// Сохраняет запись и её коды; возвращает rowid.
  Future<int> saveUpload(UploadRecord record, List<MarkingCode> codes) {
    return _db.transaction((txn) async {
      final recordId = await txn.insert('upload_records', record.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
      final batch = txn.batch();
      for (final code in codes) {
        batch.insert('codes', code.toMap()..['record_id'] = recordId,
            conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      await batch.commit(noResult: true);
      return recordId;
    });
  }

  /// Вставляет записи из файлового сервера; пропускает уже существующие.
  Future<void> upsertFromStore(
      UploadRecord record, List<MarkingCode> codes) async {
    await _db.transaction((txn) async {
      final existing = await txn.query('upload_records',
          where: 'store_id = ?', whereArgs: [record.storeId]);
      if (existing.isNotEmpty) return;
      final recordId = await txn.insert('upload_records', record.toMap());
      final batch = txn.batch();
      for (final code in codes) {
        batch.insert('codes', code.toMap()..['record_id'] = recordId,
            conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      await batch.commit(noResult: true);
    });
  }

  Future<List<UploadRecord>> getRecords() async {
    final rows =
        await _db.query('upload_records', orderBy: 'uploaded_at DESC');
    return rows.map(UploadRecord.fromMap).toList();
  }

  Future<List<UploadRecord>> getRecordsByIds(Iterable<int> ids) async {
    final list = ids.toList();
    if (list.isEmpty) return [];
    final ph = List.filled(list.length, '?').join(',');
    final rows = await _db.query('upload_records',
        where: 'id IN ($ph)', whereArgs: list);
    return rows.map(UploadRecord.fromMap).toList();
  }

  Future<Set<String>> getAllStoreIds() async {
    final rows =
        await _db.query('upload_records', columns: ['store_id']);
    return rows.map((r) => r['store_id'] as String).toSet();
  }

  Future<void> markRecordDeleted(int recordId,
      {bool pendingTombstone = false}) async {
    await _db.update(
      'upload_records',
      {
        'status': RecordStatus.deleted,
        'deleted_at': DateTime.now().toIso8601String(),
        'pending_tombstone': pendingTombstone ? 1 : 0,
      },
      where: 'id = ?',
      whereArgs: [recordId],
    );
  }

  Future<void> markTombstoneSynced(String storeId) async {
    await _db.update(
      'upload_records',
      {'pending_tombstone': 0},
      where: 'store_id = ?',
      whereArgs: [storeId],
    );
  }

  Future<void> markRecordSynced(String storeId) async {
    await _db.update(
      'upload_records',
      {'pending_record': 0},
      where: 'store_id = ?',
      whereArgs: [storeId],
    );
  }

  /// Все записи, не сохранённые на шару.
  Future<List<UploadRecord>> getPendingRecords() async {
    final rows = await _db.query('upload_records',
        where: 'pending_record = 1');
    return rows.map(UploadRecord.fromMap).toList();
  }

  /// Все надгробия, не доставленные на шару.
  Future<List<UploadRecord>> getPendingTombstones() async {
    final rows = await _db.query('upload_records',
        where: 'pending_tombstone = 1');
    return rows.map(UploadRecord.fromMap).toList();
  }

  // ──────────────────────── КОДЫ ────────────────────────

  Future<List<MarkingCode>> getCodes(int recordId) async {
    final rows = await _db.query('codes',
        where: 'record_id = ?', whereArgs: [recordId], orderBy: 'id');
    return rows.map(MarkingCode.fromMap).toList();
  }

  Future<MarkingCode?> getCodeByRecordAndRaw(
      int recordId, String raw) async {
    final rows = await _db.query('codes',
        where: 'record_id = ? AND raw = ?', whereArgs: [recordId, raw]);
    return rows.isEmpty ? null : MarkingCode.fromMap(rows.first);
  }

  /// Все коды, загруженные на [terminalKey] в записях «Загружено».
  /// Используется изъятием кодов с терминала.
  Future<List<MarkingCode>> getLoadedCodesForTerminal(
      String terminalKey) async {
    final rows = await _db.rawQuery('''
      SELECT c.* FROM codes c
      JOIN upload_records r ON r.id = c.record_id
      WHERE c.terminal_key = ?
        AND r.status = ?
      ORDER BY c.id
    ''', [terminalKey, RecordStatus.loaded]);
    return rows.map(MarkingCode.fromMap).toList();
  }

  Future<List<UploadRecord>> getRecordsByStoreIds(
      Set<String> storeIds) async {
    if (storeIds.isEmpty) return [];
    final list = storeIds.toList();
    const chunk = 400;
    final result = <UploadRecord>[];
    for (var i = 0; i < list.length; i += chunk) {
      final part = list.sublist(
          i, (i + chunk < list.length) ? i + chunk : list.length);
      final ph = List.filled(part.length, '?').join(',');
      final rows = await _db.query('upload_records',
          where: 'store_id IN ($ph)', whereArgs: part);
      result.addAll(rows.map(UploadRecord.fromMap));
    }
    return result;
  }

  /// Помечает записи как изъятые: коды сняты с терминала во временный файл.
  Future<void> markWithdrawn(Set<String> storeIds) async {
    if (storeIds.isEmpty) return;
    final list = storeIds.toList();
    const chunk = 400;
    for (var i = 0; i < list.length; i += chunk) {
      final part = list.sublist(
          i, (i + chunk < list.length) ? i + chunk : list.length);
      final ph = List.filled(part.length, '?').join(',');
      await _db.update(
        'upload_records',
        {'status': RecordStatus.withdrawn},
        where: 'store_id IN ($ph) AND status = ?',
        whereArgs: [...part, RecordStatus.loaded],
      );
    }
  }

  /// Возвращает коды изъятия в рабочий статус.
  Future<void> markRestored(Set<String> storeIds) async {
    if (storeIds.isEmpty) return;
    final list = storeIds.toList();
    const chunk = 400;
    for (var i = 0; i < list.length; i += chunk) {
      final part = list.sublist(
          i, (i + chunk < list.length) ? i + chunk : list.length);
      final ph = List.filled(part.length, '?').join(',');
      await _db.update(
        'upload_records',
        {'status': RecordStatus.loaded},
        where: 'store_id IN ($ph) AND status = ?',
        whereArgs: [...part, RecordStatus.withdrawn],
      );
    }
  }

  /// Все коды, загруженные на [terminalKey] по товару [productId]
  /// в записях со статусом «Загружено». Используется разделом «Остатки».
  Future<List<MarkingCode>> getLoadedCodesForProduct(
      String terminalKey, int productId) async {
    final rows = await _db.rawQuery('''
      SELECT c.* FROM codes c
      JOIN upload_records r ON r.id = c.record_id
      WHERE c.terminal_key = ?
        AND r.product_id = ?
        AND r.status = ?
      ORDER BY c.id
    ''', [terminalKey, productId, RecordStatus.loaded]);
    return rows.map(MarkingCode.fromMap).toList();
  }

  /// Ищет коды, уже загруженные на [terminalKey] со статусом «Загружено».
  Future<List<DuplicateHit>> findLoadedDuplicates(
      String terminalKey, List<String> raws) async {
    final hits = <DuplicateHit>[];
    const chunkSize = 500;
    for (var i = 0; i < raws.length; i += chunkSize) {
      final part = raws.sublist(
          i, (i + chunkSize < raws.length) ? i + chunkSize : raws.length);
      final ph = List.filled(part.length, '?').join(',');
      final rows = await _db.rawQuery('''
        SELECT c.raw, c.record_id
        FROM codes c
        JOIN upload_records r ON r.id = c.record_id
        WHERE c.terminal_key = ?
          AND r.status = ?
          AND c.raw IN ($ph)
      ''', [terminalKey, RecordStatus.loaded, ...part]);
      for (final row in rows) {
        hits.add(
            DuplicateHit(row['raw'] as String, row['record_id'] as int));
      }
    }
    return hits;
  }

  Future<UploadRecord?> getRecordByStoreId(String storeId) async {
    final rows = await _db.query('upload_records',
        where: 'store_id = ?', whereArgs: [storeId]);
    return rows.isEmpty ? null : UploadRecord.fromMap(rows.first);
  }

  Future<void> markRecordDeletedByStoreId(String storeId) async {
    await _db.update(
      'upload_records',
      {
        'status': RecordStatus.deleted,
        'deleted_at': DateTime.now().toIso8601String(),
        'pending_tombstone': 0,
      },
      where: 'store_id = ?',
      whereArgs: [storeId],
    );
  }

  Future<void> close() => _db.close();
}
