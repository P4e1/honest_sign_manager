import 'package:flutter/material.dart';

import '../models/marking_code.dart';
import '../models/upload_record.dart';
import '../services/database_service.dart';
import '../services/settings_service.dart';
import '../services/terminal_api.dart';
import '../utils/terminal_address.dart';

/// История выгрузок: фильтры, поиск, удаление с терминала.
class HistoryProvider extends ChangeNotifier {
  final DatabaseService _db;
  final SettingsService _settings;

  HistoryProvider(this._db, this._settings);

  List<UploadRecord> _all = [];
  bool isLoading = false;

  /// Номер записи, которая сейчас удаляется с терминала.
  int? deletingId;

  // ------------------------------ фильтры ------------------------------

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

  /// Товары, встречающиеся в истории: ID → наименование.
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
        final to = DateUtils.dateOnly(dateRange!.end).add(const Duration(days: 1));
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
          '№${r.id}',
        ].join(' ').toLowerCase();
        if (!haystack.contains(q)) return false;
      }
      return true;
    }).toList();
  }

  void setSearch(String v) {
    search = v;
    notifyListeners();
  }

  void setTerminalKey(String? v) {
    terminalKey = v;
    notifyListeners();
  }

  void setProductId(int? v) {
    productId = v;
    notifyListeners();
  }

  void setStatus(String? v) {
    status = v;
    notifyListeners();
  }

  void setDateRange(DateTimeRange? v) {
    dateRange = v;
    notifyListeners();
  }

  void clearFilters() {
    search = '';
    terminalKey = null;
    productId = null;
    status = null;
    dateRange = null;
    notifyListeners();
  }

  // ------------------------------ данные ------------------------------

  Future<void> load() async {
    isLoading = true;
    notifyListeners();
    try {
      _all = await _db.getRecords();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<List<MarkingCode>> codesOf(UploadRecord record) =>
      _db.getCodes(record.id!);

  /// Удаляет все коды записи с терминала. Возвращает текст ошибки или null.
  Future<String?> deleteFromTerminal(UploadRecord record) async {
    final token = _settings.token;
    if (token.isEmpty) return 'Не задан токен авторизации (вкладка «Настройки»)';

    final terminal = TerminalAddress.tryParse(record.terminalUrl);
    if (terminal == null) return 'Некорректный адрес терминала в записи';

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

      await _db.markRecordDeleted(record.id!);
      _all = await _db.getRecords();
      return null;
    } finally {
      deletingId = null;
      notifyListeners();
    }
  }
}
