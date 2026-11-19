import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/labeling_record.dart';
import '../models/marking_code.dart';
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
        if (name.endsWith('.progress.json')) continue;

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
    void Function(String text)? onStatus,
  }) async {
    final token = _settings.token;
    if (token.isEmpty) {
      return const VaultResult(false, 'Не задан токен авторизации');
    }

    final api = TerminalApi(token);

    // 1. Кандидаты — все коды из истории выгрузок этого терминала.
    onStatus?.call('Чтение кодов из локальной базы…');
    final dbWatch = Stopwatch()..start();
    final loaded = await _db.getLoadedCodesForTerminal(terminal.key);
    final known = await _db.getKnownCodesForTerminal(terminal.key);
    dbWatch.stop();
    onStatus?.call('Из базы прочитано кодов: ${loaded.length}, '
        '${dbWatch.elapsedMilliseconds} мс');
    if (known.isEmpty) {
      return const VaultResult(
          false, 'На этом терминале нет кодов в истории — снимать нечего');
    }

    // 2. Оставляем только то, что на терминале ещё не использовано.
    //
    // История выгрузок хранит всё, что мы когда-либо загрузили, а часть
    // этих кодов терминал уже напечатал на товаре. Если снять и потом
    // вернуть и их, напечатанные коды снова станут свободными — это и есть
    // дубликаты. Поэтому всё, что есть в истории печати терминала
    // (Ready, Locked, Cancelled), не трогаем. Если историю получить не
    // удалось, изымать нельзя: иначе проверка бессмысленна.
    final since = await _earliestUpload(known.map((c) => c.recordId).toSet());
    final used = await _fetchUsedKi(
      api,
      terminal,
      since: since,
      onStatus: onStatus,
    );
    if (used.error != null) {
      return VaultResult(
        false,
        'Изъятие не выполнено, ни один код не тронут: ${used.error}.\n'
        'Без истории печати нельзя отличить свободные коды от уже '
        'напечатанных, а возврат последних создал бы дубликаты.',
      );
    }

    final seen = <String>{};
    final codes = <MarkingCode>[];
    var skippedDuplicates = 0;
    for (final code in loaded) {
      final ki = CodeProcessor.kiOf(code.raw);
      if (used.ki!.contains(ki)) {
        continue;
      } else if (!seen.add(ki)) {
        skippedDuplicates++;
      } else {
        codes.add(code);
      }
    }

    // Напечатанные коды тоже нужно убрать с терминала: пока они там, он не даёт
    // удалять товары (внешний ключ honest_sign_code → product). В файл они
    // не пишутся и не возвращаются, поэтому дубликатов не будет.
    final printedSeen = <String>{};
    final printed = <MarkingCode>[];
    for (final code in known) {
      final ki = CodeProcessor.kiOf(code.raw);
      if (used.ki!.contains(ki) && printedSeen.add(ki)) printed.add(code);
    }

    if (codes.isEmpty) {
      if (printed.isEmpty) {
        return const VaultResult(
            false, 'Снимать нечего: на терминале нет кодов из истории выгрузок.');
      }
      final res = await _deletePrinted(api, terminal, printed, onStatus);
      if (res.error != null) {
        return VaultResult(
          false,
          'Свободных кодов нет. Напечатанные удалены не все: '
          '${res.deleted} из ${printed.length} (${res.error}).\n'
          'Повторите «Снять все коды в файл» — удалятся только оставшиеся.',
        );
      }
      return VaultResult(
        true,
        'Свободных кодов на терминале нет — файл изъятия не создан.\n'
        'Удалено напечатанных кодов: ${res.deleted}. Возвращать их не нужно.',
      );
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

    // 3. Сначала сохраняем файл — до любого удаления.
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

    // 4. Удаляем коды с терминала пачками.
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

    // 5. Помечаем записи как изъятые.
    await _db.markWithdrawn(
        vaultCodes.map((c) => c.storeId).where((s) => s.isNotEmpty).toSet());

    final printedResult =
        await _deletePrinted(api, terminal, printed, onStatus);

    final skippedNote = StringBuffer();
    if (printed.isNotEmpty) {
      skippedNote.write('Удалено напечатанных: ${printedResult.deleted} из '
          '${printed.length} — в файл не записаны и возвращены не будут.\n');
    }
    if (printedResult.error != null) {
      skippedNote.write('Напечатанные удалены не все (${printedResult.error}). '
          'Повторите «Снять все коды в файл» — удалятся только оставшиеся.\n');
    }
    if (skippedDuplicates > 0) {
      skippedNote.write('Пропущено повторов в истории: $skippedDuplicates.\n');
    }

    return VaultResult(
      printedResult.error == null,
      'Снято кодов: $deleted.\n'
      '$skippedNote'
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
    void Function(String text)? onStatus,
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

    final api = TerminalApi(token);

    // Файлы изъятия, созданные до исправления, могут содержать коды,
    // которые к тому моменту уже были напечатаны. Возвращать их нельзя:
    // они снова станут свободными и будут нанесены повторно. Поэтому
    // сверяемся с историей печати терминала и при возврате.
    final used = await _fetchUsedKi(
      api,
      terminal,
      since: _earliestUploadOf(vault.codes),
      onStatus: onStatus,
    );
    if (used.error != null) {
      return VaultResult(
        false,
        'Возврат не выполнен, на терминал ничего не загружено: ${used.error}.\n'
        'Без истории печати нельзя исключить уже напечатанные коды.',
      );
    }

    // Коды, которые терминал принял при прошлой, прерванной попытке.
    final alreadyAccepted = await _readProgress(withdrawal.withdrawalId);

    // Не возвращаем коды тех записей, которые успели удалить в истории.
    final records = await _db.getRecordsByStoreIds(
        vault.codes.map((c) => c.storeId).where((s) => s.isNotEmpty).toSet());
    final deletedStoreIds = {
      for (final r in records)
        if (r.isDeleted) r.storeId,
    };

    final seen = <String>{};
    final toRestore = <VaultCode>[];
    final acceptedBefore = <VaultCode>[];
    var skippedDeleted = 0;
    var skippedPrinted = 0;
    var skippedDuplicates = 0;
    for (final code in vault.codes) {
      final ki = CodeProcessor.kiOf(code.raw);
      if (deletedStoreIds.contains(code.storeId)) {
        skippedDeleted++;
      } else if (used.ki!.contains(ki)) {
        skippedPrinted++;
      } else if (!seen.add(ki)) {
        skippedDuplicates++;
      } else if (alreadyAccepted.contains(ki)) {
        acceptedBefore.add(code);
      } else {
        toRestore.add(code);
      }
    }

    if (toRestore.isEmpty && acceptedBefore.isEmpty) {
      return VaultResult(
          false,
          'Возвращать нечего. Удалены в истории: $skippedDeleted, '
          'уже напечатаны на терминале: $skippedPrinted.');
    }

    // Группируем по товару: терминал принимает productId в каждом элементе.
    final byProduct = <int, List<VaultCode>>{};
    for (final code in toRestore) {
      byProduct.putIfAbsent(code.productId, () => []).add(code);
    }

    final batchSize = _settings.batchSize;
    var restored = 0;
    final accepted = <VaultCode>[...acceptedBefore];

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
          // Запоминаем принятое, чтобы повтор не загрузил эти коды второй раз.
          await _writeProgress(
            withdrawal.withdrawalId,
            {for (final c in accepted) CodeProcessor.kiOf(c.raw)},
          );
          return VaultResult(
            false,
            'Возврат прервался на товаре ${entry.key} '
            '(пачка ${i + 1} из ${batches.length}): $detail\n'
            'Возвращено кодов: ${accepted.length} из '
            '${toRestore.length + acceptedBefore.length}.\n'
            'Отметка о возврате не поставлена — можно повторить. '
            'Принятые терминалом коды запомнены и при повторе '
            'загружены не будут.',
          );
        }

        restored += batch.length;
        accepted.addAll(batch);
        onProgress?.call(restored, toRestore.length);
      }
    }

    // Отметка о возврате — и локально, и на шаре.
    await _writeRestoreMarker(withdrawal.withdrawalId, accepted.length);

    final storeIds =
        accepted.map((c) => c.storeId).where((s) => s.isNotEmpty).toSet();
    await _db.markRestored(storeIds);

    final skippedNote = StringBuffer();
    if (skippedPrinted > 0) {
      skippedNote.write('\nНе возвращено (уже напечатаны на терминале): '
          '$skippedPrinted.');
    }
    if (skippedDeleted > 0) {
      skippedNote.write('\nПропущено (записи удалены в истории): '
          '$skippedDeleted.');
    }
    if (skippedDuplicates > 0) {
      skippedNote.write('\nПропущено повторов в файле изъятия: '
          '$skippedDuplicates.');
    }
    if (acceptedBefore.isNotEmpty) {
      skippedNote.write('\nУже были приняты при прошлой попытке: '
          '${acceptedBefore.length}.');
    }
    return VaultResult(
      true,
      'Возвращено кодов: ${accepted.length} на терминал '
      '${terminal.key}.$skippedNote',
      withdrawal.copyWith(restoredAt: DateTime.now()),
    );
  }

  /// Самая ранняя выгрузка среди кодов. Напечатать код можно только после
  /// загрузки на терминал, поэтому историю печати достаточно брать с этой даты.
  /// Запас в сутки нужен на расхождение часов терминала и ПК.
  Future<DateTime?> _earliestUpload(Set<int> recordIds) async {
    if (recordIds.isEmpty) return null;
    final records = await _db.getRecordsByIds(recordIds);
    return _minWithMargin(records.map((r) => r.uploadedAt));
  }

  DateTime? _earliestUploadOf(List<VaultCode> codes) => _minWithMargin([
        for (final c in codes)
          if (DateTime.tryParse(c.uploadedAt) != null)
            DateTime.parse(c.uploadedAt),
      ]);

  static DateTime? _minWithMargin(Iterable<DateTime> dates) {
    DateTime? min;
    for (final d in dates) {
      if (min == null || d.isBefore(min)) min = d;
    }
    return min?.subtract(const Duration(days: 1));
  }

  Future<({int deleted, String? error})> _deletePrinted(
    TerminalApi api,
    TerminalAddress terminal,
    List<MarkingCode> printed,
    void Function(String text)? onStatus,
  ) async {
    var deleted = 0;
    for (final batch in CodeProcessor.chunk(printed, _settings.batchSize)) {
      onStatus?.call(
          'Удаление напечатанных кодов: $deleted из ${printed.length}');
      final res = await api.deleteCodes(
        terminal: terminal,
        base64Codes: batch.map((c) => c.base64).toList(),
      );
      if (!res.ok) {
        final detail = res.statusCode == null
            ? res.error
            : 'HTTP ${res.statusCode}: ${res.error}';
        return (deleted: deleted, error: detail);
      }
      await _db.markCodesPrintedDeleted(
          [for (final c in batch) if (c.id != null) c.id!]);
      deleted += batch.length;
    }
    return (deleted: deleted, error: null);
  }

  // ─── Сверка с историей печати ────────────────────────────────────────

  static const _historyPageSize = 1000;
  static const _historyMaxPages = 500;

  /// Коды, которые терминал уже использовал при печати: статусы
  /// Ready, Locked и Cancelled. Возвращает коды идентификации (до GS).
  ///
  /// При любой неопределённости — ошибка сети, неполная история,
  /// неожиданный ответ — возвращается [error], а не частичный результат:
  /// неполный список привёл бы к тому, что напечатанный код сочли бы
  /// свободным.
  Future<({Set<String>? ki, String? error})> _fetchUsedKi(
    TerminalApi api,
    TerminalAddress terminal, {
    DateTime? since,
    void Function(String text)? onStatus,
  }) async {
    onStatus?.call('Загрузка истории печати с терминала…');
    final res = await api.getAllLabelingHistory(
      terminal: terminal,
      exportStatus: const ['Ready', 'Cancelled', 'Locked'],
      createdAtAfter: since,
      pageSize: _historyPageSize,
      maxPages: _historyMaxPages,
      onPage: (pageNumber, count, took) => onStatus?.call(
          'История печати: стр. $pageNumber, +$count записей, '
          '${took.inMilliseconds} мс'),
    );

    if (!res.ok) {
      final detail = res.statusCode == null
          ? res.error
          : 'HTTP ${res.statusCode}: ${res.error}';
      return (
        ki: null,
        error: 'не удалось получить историю печати с терминала ($detail)',
      );
    }

    final data = res.data;
    if (data is! List) {
      return (
        ki: null,
        error: 'терминал вернул неожиданный ответ на запрос истории печати',
      );
    }
    if (data.length >= _historyPageSize * _historyMaxPages) {
      return (
        ki: null,
        error: 'история печати слишком велика и получена не полностью',
      );
    }

    final ki = <String>{};
    for (final item in data) {
      if (item is! Map<String, dynamic>) continue;
      final record = LabelingRecord.fromJson(item);
      if (record == null) continue;
      ki.add(CodeProcessor.kiOf(record.codeRaw));
    }
    return (ki: ki, error: null);
  }

  // ─── Прогресс возврата ───────────────────────────────────────────────

  /// Коды (по КИ), которые терминал принял при прерванном возврате.
  Future<Set<String>> _readProgress(String withdrawalId) async {
    final result = <String>{};
    final shared = _sharedDir();
    final dirs = <Directory>[await _localDir(), if (shared != null) shared];

    for (final dir in dirs) {
      try {
        final file = File(p.join(dir.path, '$withdrawalId.progress.json'));
        if (!await file.exists()) continue;
        final json = jsonDecode(await file.readAsString(encoding: utf8))
            as Map<String, dynamic>;
        for (final item in (json['acceptedKi'] as List<dynamic>? ?? const [])) {
          if (item is String) result.add(item);
        }
      } catch (_) {
        // Повреждённый файл прогресса пропускаем.
      }
    }
    return result;
  }

  Future<void> _writeProgress(String withdrawalId, Set<String> acceptedKi) async {
    final text = jsonEncode({
      'withdrawalId': withdrawalId,
      'updatedAt': DateTime.now().toIso8601String(),
      'acceptedKi': acceptedKi.toList(),
    });

    try {
      await File(p.join((await _localDir()).path, '$withdrawalId.progress.json'))
          .writeAsString(text, encoding: utf8, flush: true);
    } catch (_) {}

    final shared = _sharedDir();
    if (shared != null) {
      try {
        await shared.create(recursive: true);
        await File(p.join(shared.path, '$withdrawalId.progress.json'))
            .writeAsString(text, encoding: utf8, flush: true);
      } catch (_) {}
    }
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
