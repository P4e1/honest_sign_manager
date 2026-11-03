import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/vault.dart';
import '../services/code_processor.dart';
import '../services/database_service.dart';
import '../services/settings_service.dart';
import '../services/terminal_api.dart';
import '../utils/terminal_address.dart';

class VaultResult {
  final bool ok;
  final String message;
  final Withdrawal? withdrawal;

  const VaultResult(this.ok, this.message, [this.withdrawal]);
}

/// Изъятие кодов с терминала во временный файл и возврат обратно.
///
/// Зачем: терминал не даёт менять справочник товаров, пока на нём есть
/// загруженные коды. Поэтому коды снимаются, товары правятся, коды
/// возвращаются.
///
/// Где хранится файл:
///   <локально>/vault/<id>.json                    — всегда, сразу
///   <шара>/store/withdrawals/<id>.json            — если шара доступна
///   <шара>/store/withdrawals/<id>.restored.json   — отметка о возврате
///
/// Локальный файл пишется ДО удаления с терминала, чтобы коды не потерялись,
/// даже если связь оборвётся посреди операции.
class VaultService {
  final DatabaseService _db;
  final SettingsService _settings;

  VaultService(this._db, this._settings);

  // ─── Пути ───────────────────────────────────────────────────────────────────

  Future<Directory> _localDir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'vault'));
    await dir.create(recursive: true);
    return dir;
  }

  Directory? _sharedDir() {
    final root = _settings.storePath.trim();
    if (root.isEmpty) return null;
    return Directory(p.join(root, 'store', 'withdrawals'));
  }

  // ─── Список изъятий ─────────────────────────────────────────────────────────

  /// Все изъятия: локальные + с шары. При совпадении ID побеждает шара.
  Future<List<Withdrawal>> listWithdrawals() async {
    final byId = <String, Withdrawal>{};

    Future<void> scan(Directory dir, String source) async {
      if (!await dir.exists()) return;
      await for (final e in dir.list()) {
        if (e is! File) continue;
        final name = p.basename(e.path);
        if (!name.endsWith('.json')) continue;
        if (name.endsWith('.restored.json')) continue;

        try {
          final json = jsonDecode(await e.readAsString(encoding: utf8))
              as Map<String, dynamic>;
          final id = json['withdrawalId'] as String? ??
              p.basenameWithoutExtension(name);
          final restoredFile =
              File(p.join(dir.path, '$id.restored.json'));
          final restoredAt = await restoredFile.exists()
              ? DateTime.tryParse(
                  (jsonDecode(await restoredFile.readAsString(encoding: utf8))
                          as Map<String, dynamic>)['restoredAt']
                      as String? ??
                  '')
              : null;

          byId[id] = Withdrawal.fromJson(
            json,
            filePath: e.path,
            source: source,
          ).copyWith(restoredAt: restoredAt);
        } catch (_) {
          // Битый файл — пропускаем.
        }
      }
    }

    await scan(await _localDir(), 'Локально');
    final shared = _sharedDir();
    if (shared != null) await scan(shared, 'Файловый сервер');

    final list = byId.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  Future<List<Withdrawal>> withdrawalsFor(String terminalKey) async =>
      (await listWithdrawals())
          .where((w) => w.terminalKey == terminalKey)
          .toList();

  /// Полное содержимое изъятия — вместе с кодами.
  Future<VaultFile?> loadVault(Withdrawal withdrawal) async {
    final candidates = <String>[
      withdrawal.filePath,
      if (_sharedDir() != null)
        p.join(_sharedDir()!.path, '${withdrawal.withdrawalId}.json'),
      p.join((await _localDir()).path, '${withdrawal.withdrawalId}.json'),
    ];

    for (final path in candidates) {
      if (path.isEmpty) continue;
      final file = File(path);
      if (!await file.exists()) continue;
      try {
        final json = jsonDecode(await file.readAsString(encoding: utf8))
            as Map<String, dynamic>;
        return VaultFile.fromJson(json);
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  // ─── Изъятие ────────────────────────────────────────────────────────────────

  /// Снимает с терминала все коды, известные по истории выгрузок,
  /// и сохраняет их в файл. Возвращает результат с созданным изъятием.
  Future<VaultResult> withdraw({
    required TerminalAddress terminal,
    String? reason,
    void Function(int done, int total)? onProgress,
  }) async {
    final token = _settings.token;
    if (token.isEmpty) {
      return const VaultResult(false, 'Не задан токен авторизации');
    }

    // 1. Собираем коды из истории этого терминала.
    final codes = await _db.getLoadedCodesForTerminal(terminal.key);
    if (codes.isEmpty) {
      return const VaultResult(
          false, 'На этом терминале нет кодов в истории — снимать нечего');
    }

    final records = {
      for (final r in await _db.getRecordsByIds(
          codes.map((c) => c.recordId).toSet()))
        r.id!: r,
    };

    final now = DateTime.now();
    final withdrawalId = _newId(now);

    final vaultCodes = <VaultCode>[];
    for (final code in codes) {
      final record = records[code.recordId];
      vaultCodes.add(VaultCode(
        raw: code.raw,
        base64: code.base64,
        productId: record?.productId ?? 0,
        productName: record?.productName ?? '',
        storeId: record?.storeId ?? '',
        uploadedAt: record?.uploadedAt.toIso8601String() ?? '',
      ));
    }

    final vault = VaultFile(
      withdrawalId: withdrawalId,
      terminalKey: terminal.key,
      terminalUrl: terminal.baseUrl,
      createdAt: now,
      author: _userName(),
      machine: Platform.localHostname,
      reason: (reason != null && reason.trim().isNotEmpty)
          ? reason.trim()
          : null,
      codes: vaultCodes,
    );

    // 2. Сначала сохраняем файл — до любого удаления.
    final localFile = File(
        p.join((await _localDir()).path, '$withdrawalId.json'));
    await localFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(vault.toJson()),
      encoding: utf8,
      flush: true,
    );

    var sharedWritten = false;
    final shared = _sharedDir();
    if (shared != null) {
      try {
        await shared.create(recursive: true);
        await File(p.join(shared.path, '$withdrawalId.json')).writeAsString(
          const JsonEncoder.withIndent('  ').convert(vault.toJson()),
          encoding: utf8,
          flush: true,
        );
        sharedWritten = true;
      } catch (_) {
        // Шара недоступна — продолжаем, файл есть локально.
      }
    }

    // 3. Удаляем коды с терминала пачками.
    final api = TerminalApi(token);
    final batchSize = _settings.batchSize;
    final batches = CodeProcessor.chunk(codes, batchSize);

    var deleted = 0;
    for (var i = 0; i < batches.length; i++) {
      final batch = batches[i];
      final res = await api.deleteCodes(
        terminal: terminal,
        base64Codes: batch.map((c) => c.base64).toList(),
      );

      if (!res.ok) {
        // Не удалось — убираем файл, чтобы не путать с успешным изъятием.
        // Коды остаются в базе, повтор можно сделать сразу.
        await _deleteFiles(withdrawalId);
        final detail = res.statusCode == null
            ? res.error
            : 'HTTP ${res.statusCode}: ${res.error}';
        return VaultResult(
          false,
          'Удаление прервалось на пачке ${i + 1} из ${batches.length} '
          '($detail).\n'
          'Уже удалено кодов: $deleted из ${codes.length}.\n'
          'Файл изъятия не создан, повторите операцию — '
          'она обработает оставшиеся коды.',
        );
      }

      deleted += batch.length;
      onProgress?.call(deleted, codes.length);
    }

    // 4. Помечаем записи как изъятые.
    await _db.markWithdrawn(
        vaultCodes.map((c) => c.storeId).where((s) => s.isNotEmpty).toSet());

    return VaultResult(
      true,
      'Снято кодов: $deleted.\n'
      'Файл: ${localFile.path}\n'
      '${sharedWritten ? 'Скопировано на файловый сервер.' : 'Файловый сервер недоступен — файл только локально.'}',
      Withdrawal(
        withdrawalId: withdrawalId,
        terminalKey: terminal.key,
        terminalUrl: terminal.baseUrl,
        filePath: localFile.path,
        codesCount: vaultCodes.length,
        createdAt: now,
        author: _userName(),
        reason: vault.reason,
        source: sharedWritten ? 'Файловый сервер' : 'Локально',
      ),
    );
  }

  // ─── Возврат ────────────────────────────────────────────────────────────────

  /// Возвращает коды изъятия на терминал, группируя их по товарам.
  Future<VaultResult> restore({
    required Withdrawal withdrawal,
    void Function(int done, int total)? onProgress,
  }) async {
    final token = _settings.token;
    if (token.isEmpty) {
      return const VaultResult(false, 'Не задан токен авторизации');
    }
    if (withdrawal.isRestored) {
      return VaultResult(false,
          'Эти коды уже возвращены ${_fmt(withdrawal.restoredAt!)}');
    }

    final terminal = TerminalAddress.tryParse(withdrawal.terminalUrl) ??
        TerminalAddress.tryParse(withdrawal.terminalKey);
    if (terminal == null) {
      return const VaultResult(false, 'Некорректный адрес терминала в изъятии');
    }

    final vault = await loadVault(withdrawal);
    if (vault == null || vault.codes.isEmpty) {
      return const VaultResult(false,
          'Файл изъятия не найден или пуст. Проверьте папку vault.');
    }

    // Не возвращаем коды тех записей, которые успели удалить в истории.
    final records = await _db.getRecordsByStoreIds(
        vault.codes.map((c) => c.storeId).where((s) => s.isNotEmpty).toSet());
    final deletedStoreIds = {
      for (final r in records)
        if (r.isDeleted) r.storeId,
    };

    final toRestore = vault.codes
        .where((c) => !deletedStoreIds.contains(c.storeId))
        .toList();
    final skipped = vault.codes.length - toRestore.length;

    if (toRestore.isEmpty) {
      return const VaultResult(
          false, 'Все записи этого изъятия удалены в истории — возвращать нечего');
    }

    // Группируем по товару: терминал принимает productId в каждом элементе.
    final byProduct = <int, List<VaultCode>>{};
    for (final code in toRestore) {
      byProduct.putIfAbsent(code.productId, () => []).add(code);
    }

    final api = TerminalApi(token);
    final batchSize = _settings.batchSize;
    var restored = 0;
    final accepted = <VaultCode>[];

    for (final entry in byProduct.entries) {
      if (entry.key <= 0) continue;
      final batches = CodeProcessor.chunk(entry.value, batchSize);

      for (var i = 0; i < batches.length; i++) {
        final batch = batches[i];
        final res = await api.uploadCodes(
          terminal: terminal,
          base64Codes: batch.map((c) => c.base64).toList(),
          productId: entry.key,
        );

        if (!res.ok) {
          final detail = res.statusCode == null
              ? res.error
              : 'HTTP ${res.statusCode}: ${res.error}';
          return VaultResult(
            false,
            'Возврат прервался на товаре ${entry.key} '
            '(пачка ${i + 1} из ${batches.length}): $detail\n'
            'Возвращено кодов: $restored из ${toRestore.length}.\n'
            'Отметка о возврате не поставлена — можно повторить. '
            'Учтите: уже возвращённые коды могут дать дубликат при повторе.',
          );
        }

        restored += batch.length;
        accepted.addAll(batch);
        onProgress?.call(restored, toRestore.length);
      }
    }

    // Отметка о возврате — и локально, и на шаре.
    await _writeRestoreMarker(withdrawal.withdrawalId, restored);

    final storeIds =
        accepted.map((c) => c.storeId).where((s) => s.isNotEmpty).toSet();
    await _db.markRestored(storeIds);

    final skippedNote =
        skipped > 0 ? '\nПропущено (записи удалены в истории): $skipped.' : '';
    return VaultResult(
      true,
      'Возвращено кодов: $restored на терминал ${terminal.key}.$skippedNote',
      withdrawal.copyWith(restoredAt: DateTime.now()),
    );
  }

  Future<void> _writeRestoreMarker(String withdrawalId, int count) async {
    final payload = {
      'withdrawalId': withdrawalId,
      'restoredAt': DateTime.now().toIso8601String(),
      'restoredCount': count,
      'author': _userName(),
      'machine': Platform.localHostname,
    };
    final text = const JsonEncoder.withIndent('  ').convert(payload);

    try {
      await File(p.join((await _localDir()).path, '$withdrawalId.restored.json'))
          .writeAsString(text, encoding: utf8, flush: true);
    } catch (_) {}

    final shared = _sharedDir();
    if (shared != null) {
      try {
        await shared.create(recursive: true);
        await File(p.join(shared.path, '$withdrawalId.restored.json'))
            .writeAsString(text, encoding: utf8, flush: true);
      } catch (_) {}
    }
  }

  Future<void> _deleteFiles(String withdrawalId) async {
    try {
      final file = File(p.join((await _localDir()).path, '$withdrawalId.json'));
      if (await file.exists()) await file.delete();
    } catch (_) {}
    final shared = _sharedDir();
    if (shared != null) {
      try {
        final file = File(p.join(shared.path, '$withdrawalId.json'));
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
  }

  // ─── Утилиты ────────────────────────────────────────────────────────────────

  static String _newId(DateTime at) {
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

  static String _userName() {
    final user = Platform.environment['USERNAME'] ??
        Platform.environment['USER'] ??
        '';
    return user;
  }

  static String _fmt(DateTime dt) {
    final l = dt.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(l.day)}.${two(l.month)}.${l.year} '
        '${two(l.hour)}:${two(l.minute)}';
  }
}
