import 'package:flutter/material.dart';

import '../models/marking_code.dart';
import '../models/upload_record.dart';
import '../services/database_service.dart';
import '../services/settings_service.dart';
import '../services/shared_store.dart';
import '../services/sync_service.dart';
import '../services/terminal_api.dart';
import '../utils/terminal_address.dart';

class HistoryProvider extends ChangeNotifier {
  final DatabaseService _db;
  final SettingsService _settings;

  HistoryProvider(this._db, this._settings);

  List<UploadRecord> _all = [];
  bool isLoading = false;
  int? deletingId;

  /// Результат последней синхронизации.
  SyncResult? lastSync;
  DateTime? lastSyncAt;

  // ─── Фильтры ─────────────────────────────────────────────────────────────────

  String search = '';
  String? terminalKey;
  int? productId;
  String? status;
  DateTimeRange? dateRange;

  bool get hasFilters =>
      search.isNotEmpty ||
      terminalKey != null ||
      productId != null ||
      status != null ||
      dateRange != null;

  List<String> get terminalKeys =>
      (_all.map((r) => r.terminalKey).toSet().toList()..sort());

  Map<int, String> get productsInHistory {
    final map = <int, String>{};
    for (final r in _all) {
      map.putIfAbsent(r.productId, () => r.productName);
    }
    final ids = map.keys.toList()..sort();
    return {for (final id in ids) id: map[id]!};
  }

  List<UploadRecord> get records {
    final q = search.trim().toLowerCase();
    return _all.where((r) {
      if (terminalKey != null && r.terminalKey != terminalKey) return false;
      if (productId != null && r.productId != productId) return false;
      if (status != null && r.status != status) return false;
      if (dateRange != null) {
        final from = DateUtils.dateOnly(dateRange!.start);
        final to = DateUtils.dateOnly(dateRange!.end)
            .add(const Duration(days: 1));
        if (r.uploadedAt.isBefore(from) || !r.uploadedAt.isBefore(to)) {
          return false;
        }
      }
      if (q.isNotEmpty) {
        final haystack = [
          r.productName,
          r.productId.toString(),
          r.terminalKey,
          r.terminalUrl,
          r.fileName,
          r.author,
          r.storeId,
        ].join(' ').toLowerCase();
        if (!haystack.contains(q)) return false;
      }
      return true;
    }).toList();
  }

  // ─── Изменение фильтров ──────────────────────────────────────────────────────

  void setSearch(String v) { search = v; notifyListeners(); }
  void setTerminalKey(String? v) { terminalKey = v; notifyListeners(); }
  void setProductId(int? v) { productId = v; notifyListeners(); }
  void setStatus(String? v) { status = v; notifyListeners(); }
  void setDateRange(DateTimeRange? v) { dateRange = v; notifyListeners(); }

  void clearFilters() {
    search = '';
    terminalKey = null;
    productId = null;
    status = null;
    dateRange = null;
    notifyListeners();
  }

  // ─── Загрузка данных ─────────────────────────────────────────────────────────

  /// Синхронизирует с шарой, потом читает кеш.
  Future<void> load() async {
    isLoading = true;
    notifyListeners();
    try {
      await _sync();
      _all = await _db.getRecords();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  /// Только обновить из локального кеша, без обращения к шаре.
  Future<void> reload() async {
    _all = await _db.getRecords();
    notifyListeners();
  }

  Future<void> _sync() async {
    final storePath = _settings.storePath;
    if (storePath.isEmpty) return;

    final store = SharedStore(storePath);
    final sync = SyncService(_db, store);
    lastSync = await sync.sync();
    lastSyncAt = DateTime.now();
  }

  Future<List<MarkingCode>> codesOf(UploadRecord record) =>
      _db.getCodes(record.id!);

  // ─── Удаление с терминала ────────────────────────────────────────────────────

  /// Возвращает текст ошибки или null при успехе.
  Future<String?> deleteFromTerminal(UploadRecord record) async {
    final token = _settings.token;
    if (token.isEmpty) {
      return 'Не задан токен авторизации (вкладка «Настройки»)';
    }

    final terminal = TerminalAddress.tryParse(record.terminalUrl);
    if (terminal == null) {
      return 'Некорректный адрес терминала в записи';
    }

    deletingId = record.id;
    notifyListeners();

    try {
      final codes = await _db.getCodes(record.id!);
      if (codes.isEmpty) return 'В записи нет кодов';

      final res = await TerminalApi(token).deleteCodes(
        terminal: terminal,
        base64Codes: codes.map((c) => c.base64).toList(),
      );

      if (!res.ok) {
        return res.statusCode == null
            ? res.error
            : 'Ошибка ${res.statusCode}: ${res.error}';
      }

      // Сохраняем локально. Надгробие досылаем на шару.
      await _db.markRecordDeleted(record.id!, pendingTombstone: true);

      // Пробуем сразу досдать надгробие на шару.
      final storePath = _settings.storePath;
      if (storePath.isNotEmpty) {
        try {
          final store = SharedStore(storePath);
          await store.writeTombstone(record.storeId);
          await _db.markTombstoneSynced(record.storeId);
        } catch (_) {
          // Шара недоступна — надгробие в очереди, дойдёт при следующей синхронизации.
        }
      }

      _all = await _db.getRecords();
      return null;
    } finally {
      deletingId = null;
      notifyListeners();
    }
  }
}
