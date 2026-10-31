import '../models/marking_code.dart';
import '../models/upload_record.dart';
import 'database_service.dart';
import 'shared_store.dart';

/// Результат синхронизации.
class SyncResult {
  /// Количество новых записей, загруженных с шары.
  final int added;

  /// Количество записей, помеченных удалёнными по надгробиям с шары.
  final int tombstoned;

  /// Количество отложенных записей, успешно досланных на шару.
  final int pushed;

  /// Текст ошибки подключения к шаре; null — шара доступна.
  final String? storeError;

  const SyncResult({
    this.added = 0,
    this.tombstoned = 0,
    this.pushed = 0,
    this.storeError,
  });

  bool get hasChanges => added > 0 || tombstoned > 0 || pushed > 0;

  String get summary {
    if (storeError != null) return 'Нет связи с файловым сервером';
    if (!hasChanges) return 'Данные актуальны';
    final parts = <String>[];
    if (added > 0) parts.add('новых: $added');
    if (tombstoned > 0) parts.add('удалённых: $tombstoned');
    if (pushed > 0) parts.add('дослано: $pushed');
    return 'Синхронизировано (${parts.join(', ')})';
  }
}

/// Синхронизирует локальный кеш с файловым сервером.
///
/// Алгоритм:
///  1. Дослать на шару отложенные записи (pendingRecord=1).
///  2. Дослать на шару отложенные надгробия (pendingTombstone=1).
///  3. Скачать новые записи с шары (чьих storeId нет в кеше).
///  4. Применить новые надгробия (пометить удалёнными в кеше).
class SyncService {
  final DatabaseService _db;
  final SharedStore _store;

  SyncService(this._db, this._store);

  Future<SyncResult> sync() async {
    // Проверяем доступность шары.
    final accessError = await _store.checkAccess();
    if (accessError != null) {
      return SyncResult(storeError: accessError);
    }

    var pushed = 0;
    var added = 0;
    var tombstoned = 0;

    // 1. Отложенные записи → шара.
    final pendingRecords = await _db.getPendingRecords();
    for (final record in pendingRecords) {
      try {
        final codes = await _db.getCodes(record.id!);
        await _store.writeRecord(record, codes);
        await _db.markRecordSynced(record.storeId);
        pushed++;
      } catch (_) {
        // Оставляем в очереди, попробуем в следующий раз.
      }
    }

    // 2. Отложенные надгробия → шара.
    final pendingTombstones = await _db.getPendingTombstones();
    for (final record in pendingTombstones) {
      try {
        await _store.writeTombstone(record.storeId);
        await _db.markTombstoneSynced(record.storeId);
        pushed++;
      } catch (_) {
        // Оставляем в очереди.
      }
    }

    // 3. Новые записи с шары → кеш.
    final knownIds = await _db.getAllStoreIds();
    final newRecords = await _store.readNewRecords(knownIds);
    for (final sr in newRecords) {
      try {
        final record = _recordFromJson(sr);
        final codes = _codesFromJson(sr);
        await _db.upsertFromStore(record, codes);
        added++;
      } catch (_) {
        // Повреждённый файл — пропускаем.
      }
    }

    // 4. Надгробия с шары → пометить удалёнными в кеше.
    final tombstoneIds = await _store.readTombstones();
    for (final storeId in tombstoneIds) {
      try {
        // Ищем запись по storeId; если уже удалена — пропускаем.
        final rows = await _db.getRecordByStoreId(storeId);
        if (rows != null && rows.isLoaded) {
          await _db.markRecordDeletedByStoreId(storeId);
          tombstoned++;
        }
      } catch (_) {
        // Игнорируем.
      }
    }

    return SyncResult(added: added, tombstoned: tombstoned, pushed: pushed);
  }

  // ─── Парсинг JSON файлов шары ────────────────────────────────────────────

  UploadRecord _recordFromJson(StoreRecord sr) {
    final j = sr.json;
    return UploadRecord(
      storeId: sr.storeId,
      terminalUrl: j['terminalUrl'] as String? ?? '',
      terminalKey: j['terminalKey'] as String? ?? '',
      productId: (j['productId'] as num).toInt(),
      productName: j['productName'] as String? ?? '',
      fileName: j['fileName'] as String? ?? '',
      codesCount: (j['codesCount'] as num).toInt(),
      httpStatus: (j['httpStatus'] as num).toInt(),
      status: j['status'] as String? ?? RecordStatus.loaded,
      uploadedAt: DateTime.parse(j['uploadedAt'] as String),
      author: j['machine'] as String? ?? '',
      pendingRecord: false,
      pendingTombstone: false,
    );
  }

  List<MarkingCode> _codesFromJson(StoreRecord sr) {
    final j = sr.json;
    final b64List = (j['base64Codes'] as List<dynamic>?)?.cast<String>() ?? [];
    final rawList = (j['rawCodes'] as List<dynamic>?)?.cast<String>() ?? [];
    final terminalKey = j['terminalKey'] as String? ?? '';

    return [
      for (var i = 0; i < b64List.length; i++)
        MarkingCode(
          recordId: 0, // будет проставлен при upsert
          raw: i < rawList.length ? rawList[i] : '',
          base64: b64List[i],
          terminalKey: terminalKey,
        ),
    ];
  }
}
