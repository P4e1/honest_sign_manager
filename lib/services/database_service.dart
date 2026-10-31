import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/marking_code.dart';
import '../models/product.dart';
import '../models/upload_record.dart';

/// Совпадение кода с уже загруженным (для проверки дублей).
class DuplicateHit {
  final String raw;
  final int recordId;
  const DuplicateHit(this.raw, this.recordId);
}

/// Локальная база SQLite: справочник товаров, история, коды.
class DatabaseService {
  late final Database _db;
  late final String path;

  Future<void> init() async {
    sqfliteFfiInit();
    final dir = await getApplicationSupportDirectory();
    await Directory(dir.path).create(recursive: true);
    path = p.join(dir.path, 'honest_sign.db');

    _db = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: _onCreate,
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
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        terminal_url TEXT    NOT NULL,
        terminal_key TEXT    NOT NULL,
        product_id   INTEGER NOT NULL,
        product_name TEXT    NOT NULL,
        file_name    TEXT    NOT NULL,
        codes_count  INTEGER NOT NULL,
        http_status  INTEGER NOT NULL,
        status       TEXT    NOT NULL,
        uploaded_at  TEXT    NOT NULL,
        deleted_at   TEXT
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
  }

  // ============================ ТОВАРЫ ============================

  /// Полностью заменяет справочник товаров.
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

  // ============================ ИСТОРИЯ ============================

  /// Сохраняет запись и её коды в одной транзакции. Возвращает номер записи.
  Future<int> saveUpload(UploadRecord record, List<MarkingCode> codes) {
    return _db.transaction((txn) async {
      final recordId = await txn.insert('upload_records', record.toMap());
      final batch = txn.batch();
      for (final code in codes) {
        final map = code.toMap()..['record_id'] = recordId;
        batch.insert('codes', map);
      }
      await batch.commit(noResult: true);
      return recordId;
    });
  }

  Future<List<UploadRecord>> getRecords() async {
    final rows = await _db.query('upload_records', orderBy: 'id DESC');
    return rows.map(UploadRecord.fromMap).toList();
  }

  Future<List<UploadRecord>> getRecordsByIds(Iterable<int> ids) async {
    final list = ids.toList();
    if (list.isEmpty) return [];
    final placeholders = List.filled(list.length, '?').join(',');
    final rows = await _db.query('upload_records',
        where: 'id IN ($placeholders)', whereArgs: list, orderBy: 'id');
    return rows.map(UploadRecord.fromMap).toList();
  }

  Future<void> markRecordDeleted(int recordId) async {
    await _db.update(
      'upload_records',
      {
        'status': RecordStatus.deleted,
        'deleted_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [recordId],
    );
  }

  Future<List<MarkingCode>> getCodes(int recordId) async {
    final rows = await _db.query('codes',
        where: 'record_id = ?', whereArgs: [recordId], orderBy: 'id');
    return rows.map(MarkingCode.fromMap).toList();
  }

  /// Ищет среди [raws] коды, уже загруженные на терминал [terminalKey]
  /// в записях со статусом «Загружено».
  Future<List<DuplicateHit>> findLoadedDuplicates(
      String terminalKey, List<String> raws) async {
    final hits = <DuplicateHit>[];
    const chunkSize = 500; // ограничение SQLite на число параметров
    for (var i = 0; i < raws.length; i += chunkSize) {
      final part = raws.sublist(
          i, i + chunkSize > raws.length ? raws.length : i + chunkSize);
      final placeholders = List.filled(part.length, '?').join(',');
      final rows = await _db.rawQuery('''
        SELECT c.raw, c.record_id
        FROM codes c
        JOIN upload_records r ON r.id = c.record_id
        WHERE c.terminal_key = ?
          AND r.status = ?
          AND c.raw IN ($placeholders)
      ''', [terminalKey, RecordStatus.loaded, ...part]);
      for (final row in rows) {
        hits.add(DuplicateHit(row['raw'] as String, row['record_id'] as int));
      }
    }
    return hits;
  }

  Future<void> close() => _db.close();
}
