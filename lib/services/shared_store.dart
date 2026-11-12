import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'dart:math' as math;

import '../models/marking_code.dart';
import '../models/upload_record.dart';

/// Один файл записи, прочитанный с шары.
class StoreRecord {
  final String storeId;
  final Map<String, dynamic> json;
  const StoreRecord(this.storeId, this.json);
}

/// Источник правды — сетевая папка (SMB / UNC).
///
///  <root>/store/records/<year>/<storeId>.json  — неизменяемые JSON выгрузок
///  <root>/store/tombstones/<storeId>.json      — надгробия удалённых записей
class SharedStore {
  final String rootPath;
  SharedStore(this.rootPath);

  // ─── Доступность ────────────────────────────────────────────────────────────

  /// Возвращает текст ошибки или null при успехе.
  Future<String?> checkAccess() async {
    try {
      final dir = Directory(rootPath);
      if (!await dir.exists()) return 'Папка не найдена:\n$rootPath';
      final probe = File(p.join(rootPath, '.write_probe_${math.Random().nextInt(0x7fffffff)}'));
      await probe.writeAsString('ok');
      await probe.delete();
      return null;
    } on PathAccessException catch (e) {
      return 'Нет прав на запись: ${e.message}';
    } on FileSystemException catch (e) {
      return 'Ошибка файловой системы: ${e.message}';
    } catch (e) {
      return 'Ошибка проверки доступа: $e';
    }
  }

  // ─── Записи ─────────────────────────────────────────────────────────────────

  /// Читает записи, ID которых нет в [alreadyKnown].
  Future<List<StoreRecord>> readNewRecords(Set<String> alreadyKnown) async {
    final dir = Directory(p.join(rootPath, 'store', 'records'));
    if (!await dir.exists()) return const [];

    final result = <StoreRecord>[];
    await for (final e in dir.list(recursive: true)) {
      if (e is! File || !e.path.endsWith('.json')) continue;
      final id = p.basenameWithoutExtension(e.path);
      if (alreadyKnown.contains(id)) continue;
      try {
        final raw = await e.readAsString(encoding: utf8);
        final json = jsonDecode(raw) as Map<String, dynamic>;
        result.add(StoreRecord(id, json));
      } catch (_) {
        // Повреждённый файл — пропускаем без падения.
      }
    }
    return result;
  }

  /// Сохраняет запись атомарно: сначала temp-файл, потом rename.
  Future<void> writeRecord(UploadRecord record, List<MarkingCode> codes) async {
    final year = record.uploadedAt.year.toString();
    final dir = Directory(p.join(rootPath, 'store', 'records', year));
    await dir.create(recursive: true);

    final payload = {
      'storeId': record.storeId,
      'terminalUrl': record.terminalUrl,
      'terminalKey': record.terminalKey,
      'productId': record.productId,
      'productName': record.productName,
      'fileName': record.fileName,
      'codesCount': record.codesCount,
      'httpStatus': record.httpStatus,
      'status': RecordStatus.loaded,
      'uploadedAt': record.uploadedAt.toIso8601String(),
      'machine': Platform.localHostname,
      'base64Codes': codes.map((c) => c.base64).toList(),
      'rawCodes': codes.map((c) => c.raw).toList(),
    };

    final target = File(p.join(dir.path, '${record.storeId}.json'));
    final temp = File('${target.path}.tmp');
    await temp.writeAsString(
        const JsonEncoder.withIndent('  ').convert(payload),
        encoding: utf8);
    await temp.rename(target.path);
  }

  // ─── Надгробия ───────────────────────────────────────────────────────────────

  Future<Set<String>> readTombstones() async {
    final dir = Directory(p.join(rootPath, 'store', 'tombstones'));
    if (!await dir.exists()) return const {};
    final ids = <String>{};
    await for (final e in dir.list()) {
      if (e is File && e.path.endsWith('.json')) {
        ids.add(p.basenameWithoutExtension(e.path));
      }
    }
    return ids;
  }

  Future<void> writeTombstone(String storeId) async {
    final dir = Directory(p.join(rootPath, 'store', 'tombstones'));
    await dir.create(recursive: true);
    final payload = {
      'storeId': storeId,
      'deletedAt': DateTime.now().toIso8601String(),
      'machine': Platform.localHostname,
    };
    await File(p.join(dir.path, '$storeId.json'))
        .writeAsString(jsonEncode(payload), encoding: utf8);
  }

  // ─── Вспомогательное ────────────────────────────────────────────────────────

  static String generateStoreId(DateTime at) {
    final rand = math.Random().nextInt(0xffff).toRadixString(16).padLeft(4, '0');
    return '${at.year}'
        '${at.month.toString().padLeft(2, '0')}'
        '${at.day.toString().padLeft(2, '0')}'
        '-'
        '${at.hour.toString().padLeft(2, '0')}'
        '${at.minute.toString().padLeft(2, '0')}'
        '${at.second.toString().padLeft(2, '0')}'
        '-$rand';
  }
}
