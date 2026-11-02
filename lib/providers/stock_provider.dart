import 'package:flutter/foundation.dart';

import '../models/labeling_record.dart';
import '../models/product.dart';
import '../services/database_service.dart';
import '../services/labeling_exporter.dart';
import '../services/settings_service.dart';
import '../services/terminal_api.dart';
import '../utils/terminal_address.dart';

/// Период, за который смотреть историю маркировки.
enum StockPeriod {
  day('За сутки', Duration(days: 1)),
  week('За неделю', Duration(days: 7)),
  month('За месяц', Duration(days: 30)),
  quarter('За 3 месяца', Duration(days: 90)),
  all('За всё время', null);

  final String label;
  final Duration? duration;
  const StockPeriod(this.label, this.duration);

  DateTime? get since =>
      duration == null ? null : DateTime.now().subtract(duration!);
}

/// Раздел «Остатки»: сколько кодов свободно, что напечатано,
/// а что загружено, но ещё не нанесено.
class StockProvider extends ChangeNotifier {
  final DatabaseService _db;
  final SettingsService _settings;

  StockProvider(this._db, this._settings);

  // ─── Состояние ──────────────────────────────────────────────────────────────

  List<Product> products = [];
  bool showHiddenProducts = false;
  Product? selectedProduct;

  String terminalUrl = '';
  List<String> recentUrls = [];

  StockPeriod period = StockPeriod.month;

  bool isLoading = true;
  String? error;
  String? progressText;

  /// Итоговые данные; null — ещё не запрашивали.
  StockReport? report;

  DateTime? loadedAt;

  // ─── Вычисляемые ────────────────────────────────────────────────────────────

  TerminalAddress? get terminal => TerminalAddress.tryParse(terminalUrl);

  List<Product> get visibleProducts => showHiddenProducts
      ? products
      : products.where((p) => !p.isHidden).toList();

  bool get canLoad =>
      !isLoading && terminal != null && selectedProduct != null;

  // ─── Инициализация ──────────────────────────────────────────────────────────

  Future<void> init() async {
    recentUrls = _settings.recentUrls;
    if (recentUrls.isNotEmpty) terminalUrl = recentUrls.first;
    await reloadProducts();
  }

  Future<void> reloadProducts() async {
    products = await _db.getProducts();
    if (selectedProduct != null && !products.contains(selectedProduct)) {
      selectedProduct = null;
    }
    isLoading = false;
    notifyListeners();
  }

  // ─── Ввод ───────────────────────────────────────────────────────────────────

  void setProduct(Product? value) {
    if (value == selectedProduct) return;
    selectedProduct = value;
    report = null;
    loadedAt = null;
    error = null;
    notifyListeners();
  }

  void setTerminalUrl(String value) {
    if (value == terminalUrl) return;
    terminalUrl = value;
    report = null;
    loadedAt = null;
    error = null;
    notifyListeners();
  }

  void setPeriod(StockPeriod value) {
    if (value == period) return;
    period = value;
    notifyListeners();
  }

  void setShowHiddenProducts(bool value) {
    showHiddenProducts = value;
    notifyListeners();
  }

  // ─── Загрузка остатков ──────────────────────────────────────────────────────

  Future<void> load() async {
    final product = selectedProduct;
    final terminal = this.terminal;
    final token = _settings.token;

    if (product == null) {
      error = 'Выберите товар';
      notifyListeners();
      return;
    }
    if (terminal == null) {
      error = 'Некорректный адрес терминала';
      notifyListeners();
      return;
    }
    if (token.isEmpty) {
      error = 'Не задан токен авторизации (вкладка «Настройки»)';
      notifyListeners();
      return;
    }

    isLoading = true;
    error = null;
    report = null;
    progressText = 'Запрос остатка кодов…';
    notifyListeners();

    try {
      final api = TerminalApi(token);

      // 1. Остаток свободных кодов.
      final countResult = await api.countFreeCodes(
          terminal: terminal, productId: product.id);

      if (!countResult.ok) {
        error = countResult.statusCode == null
            ? 'Не удалось получить остаток: ${countResult.error}'
            : 'Остаток — ошибка ${countResult.statusCode}: ${countResult.error}';
        return;
      }

      final freeCount = _extractCount(countResult.data);
      if (freeCount == null) {
        error = 'Терминал вернул неожиданный ответ на запрос остатка:\n'
            '${countResult.data}';
        return;
      }

      // 2. История маркировки: печатаем страницами.
      progressText = 'Загрузка истории маркировки…';
      notifyListeners();

      final historyResult = await api.getAllLabelingHistory(
        terminal: terminal,
        exportStatus: const ['Ready', 'Cancelled', 'Locked'],
        createdAtAfter: period.since,
        onProgress: (loaded) {
          progressText = 'Загрузка истории маркировки: $loaded записей…';
          notifyListeners();
        },
      );

      if (!historyResult.ok) {
        error = historyResult.statusCode == null
            ? 'Не удалось загрузить историю: ${historyResult.error}'
            : 'История — ошибка ${historyResult.statusCode}: '
                '${historyResult.error}';
        return;
      }

      final rawList = historyResult.data as List;
      final all = <LabelingRecord>[];
      var unknown = 0;

      for (final item in rawList) {
        if (item is! Map<String, dynamic>) continue;
        final record = LabelingRecord.fromJson(item);
        if (record == null) continue;
        if (record.productId == null) {
          unknown++;
          continue;
        }
        if (record.productId == product.id) all.add(record);
      }

      // 3. Коды из нашей истории выгрузок на этот терминал.
      final uploaded = await _db.getLoadedCodesForProduct(
          terminal.key, product.id);

      report = StockReport(
        freeCount: freeCount,
        labeling: all,
        uploadedRawCodes: uploaded.map((c) => c.raw).toList(),
        unknownProduct: unknown,
      );
      loadedAt = DateTime.now();
    } catch (e) {
      error = 'Ошибка: $e';
    } finally {
      isLoading = false;
      progressText = null;
      notifyListeners();
    }
  }

  /// Ответ на /count бывает `{"count": 0}` — берём первое числовое поле.
  int? _extractCount(dynamic data) {
    if (data is Map) {
      final value = data['count'];
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value);
    }
    if (data is int) return data;
    return null;
  }

  // ─── Отчёт Excel ────────────────────────────────────────────────────────────

  Future<String?> exportToExcel(String filePath) async {
    final product = selectedProduct;
    final terminal = this.terminal;
    final current = report;

    if (product == null || terminal == null || current == null) {
      return 'Сначала загрузите остатки';
    }

    try {
      await LabelingExporter.writeStockReport(
        path: filePath,
        product: product,
        terminal: terminal,
        report: current,
        period: period,
        generatedAt: DateTime.now(),
      );
      return null;
    } catch (e) {
      return 'Не удалось сохранить файл: $e';
    }
  }
}
