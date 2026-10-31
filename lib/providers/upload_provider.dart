import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/marking_code.dart';
import '../models/product.dart';
import '../models/upload_record.dart';
import '../services/code_processor.dart';
import '../services/database_service.dart';
import '../services/excel_service.dart';
import '../services/settings_service.dart';
import '../services/shared_store.dart';
import '../services/terminal_api.dart';
import '../utils/terminal_address.dart';

/// Дубликаты, найденные в истории для выбранного терминала.
class DuplicateCheck {
  /// Коды файла, которые уже загружены на этот терминал.
  final Set<String> codes;

  /// Записи истории, в которых они лежат, и сколько кодов в каждой.
  final List<DuplicateGroup> groups;

  const DuplicateCheck(this.codes, this.groups);

  bool get isEmpty => codes.isEmpty;
}

class DuplicateGroup {
  final UploadRecord record;
  final int count;
  const DuplicateGroup(this.record, this.count);
}

/// Итог выгрузки для вывода пользователю.
class UploadOutcome {
  final bool success;
  final String message;
  final int? statusCode;
  const UploadOutcome(this.success, this.message, [this.statusCode]);
}

class UploadProvider extends ChangeNotifier {
  final DatabaseService _db;
  final SettingsService _settings;

  UploadProvider(this._db, this._settings);

  // ------------------------------ состояние ------------------------------

  String? fileName;
  CodeParseResult? parsed;
  bool isReadingFile = false;

  String terminalUrl = '';
  List<String> recentUrls = [];

  List<Product> products = [];
  bool showHiddenProducts = false;
  Product? selectedProduct;

  bool isUploading = false;
  String? progressText;
  UploadOutcome? outcome;

  List<String> get codes => parsed?.codes ?? const [];

  TerminalAddress? get terminal => TerminalAddress.tryParse(terminalUrl);

  List<Product> get visibleProducts => showHiddenProducts
      ? products
      : products.where((p) => !p.isHidden).toList();

  bool get canUpload =>
      !isUploading &&
      codes.isNotEmpty &&
      terminal != null &&
      selectedProduct != null;

  // ------------------------------ загрузка данных ------------------------------

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
    notifyListeners();
  }

  // ------------------------------ ввод пользователя ------------------------------

  void setTerminalUrl(String value) {
    if (value == terminalUrl) return;
    terminalUrl = value;
    notifyListeners();
  }

  void setProduct(Product? product) {
    if (product == selectedProduct) return;
    selectedProduct = product;
    notifyListeners();
  }

  void setShowHiddenProducts(bool value) {
    showHiddenProducts = value;
    notifyListeners();
  }

  void clearOutcome() {
    outcome = null;
    notifyListeners();
  }

  void clearFile() {
    fileName = null;
    parsed = null;
    notifyListeners();
  }

  /// Читает файл с кодами. Возвращает текст ошибки или null.
  Future<String?> loadFile(String path, String name) async {
    isReadingFile = true;
    outcome = null;
    notifyListeners();
    try {
      final result = await ExcelService.readCodes(path);
      fileName = name;
      parsed = result;
      return null;
    } catch (e) {
      fileName = null;
      parsed = null;
      return 'Не удалось прочитать файл: ${e is FormatException ? e.message : e}';
    } finally {
      isReadingFile = false;
      notifyListeners();
    }
  }

  // ------------------------------ дубликаты ------------------------------

  /// Проверка по истории: коды файла, уже загруженные на ЭТОТ терминал
  /// и не удалённые.
  Future<DuplicateCheck> checkDuplicates() async {
    final t = terminal;
    if (t == null || codes.isEmpty) return const DuplicateCheck({}, []);

    final hits = await _db.findLoadedDuplicates(t.key, codes);
    if (hits.isEmpty) return const DuplicateCheck({}, []);

    final perRecord = <int, Set<String>>{};
    for (final h in hits) {
      perRecord.putIfAbsent(h.recordId, () => {}).add(h.raw);
    }
    final records = await _db.getRecordsByIds(perRecord.keys);
    final groups = [
      for (final r in records) DuplicateGroup(r, perRecord[r.id]!.length),
    ];
    return DuplicateCheck(hits.map((h) => h.raw).toSet(), groups);
  }

  // ------------------------------ выгрузка ------------------------------

  /// Отправляет коды на терминал пачками. [exclude] — коды-дубликаты,
  /// которые нужно пропустить.
  Future<UploadOutcome> upload({Set<String> exclude = const {}}) async {
    final t = terminal;
    final product = selectedProduct;
    final token = _settings.token;

    if (t == null) return _finish(false, 'Некорректный адрес терминала');
    if (product == null) return _finish(false, 'Не выбран товар');
    if (token.isEmpty) {
      return _finish(false, 'Не задан токен авторизации (вкладка «Настройки»)');
    }

    final toSend = codes.where((c) => !exclude.contains(c)).toList();
    if (toSend.isEmpty) return _finish(false, 'Нет новых кодов для выгрузки');

    isUploading = true;
    outcome = null;
    notifyListeners();

    final api = TerminalApi(token);
    final batches = CodeProcessor.chunk(toSend, _settings.batchSize);
    final rawByBase64 = {for (final c in toSend) CodeProcessor.toBase64(c): c};

    final accepted = <MarkingCode>[];
    int? lastStatus;
    String? error;
    var sent = 0;

    for (var i = 0; i < batches.length; i++) {
      progressText = batches.length > 1
          ? 'Пачка ${i + 1} из ${batches.length}…'
          : 'Отправка ${toSend.length} кодов…';
      notifyListeners();

      final batch = batches[i];
      final b64 = batch.map(CodeProcessor.toBase64).toList();
      final res = await api.uploadCodes(
          terminal: t, base64Codes: b64, productId: product.id);
      lastStatus = res.statusCode;

      if (!res.ok) {
        error = res.statusCode == null
            ? res.error
            : 'Ошибка ${res.statusCode}: ${res.error}';
        break;
      }
      sent += batch.length;
      accepted.addAll(_acceptedFromResponse(res.data, b64, rawByBase64, t.key));
    }

    // Сохраняем в историю всё, что терминал принял (даже при частичном сбое).
    int? recordId;
    String? storeId;
    if (accepted.isNotEmpty) {
      final now = DateTime.now();
      storeId = SharedStore.generateStoreId(now);
      final record = UploadRecord(
        storeId: storeId,
        terminalUrl: t.baseUrl,
        terminalKey: t.key,
        productId: product.id,
        productName: product.name,
        fileName: fileName ?? 'без имени',
        codesCount: accepted.length,
        httpStatus: lastStatus ?? 201,
        status: RecordStatus.loaded,
        uploadedAt: now,
        author: Platform.localHostname,
        pendingRecord: true,
      );
      recordId = await _db.saveUpload(record, accepted);
      await _settings.addRecentUrl(terminalUrl.trim());
      recentUrls = _settings.recentUrls;

      // Пытаемся сразу записать на файловый сервер.
      final storePath = _settings.storePath;
      if (storePath.isNotEmpty) {
        try {
          final store = SharedStore(storePath);
          await store.writeRecord(record, accepted);
          await _db.markRecordSynced(storeId);
        } catch (_) {
          // Шара недоступна — запись в очереди, дойдёт при следующей синхронизации.
        }
      }
    }

    isUploading = false;
    progressText = null;

    if (error != null) {
      final saved = recordId == null
          ? ''
          : '\n\nДо ошибки принято ${accepted.length} кодов — сохранены в историю (запись №$recordId).';
      return _finish(false, '$error$saved', lastStatus);
    }

    final skipped = exclude.isEmpty ? '' : ', пропущено дублей: ${codes.length - toSend.length}';
    final partial = accepted.length < sent
        ? '\nВнимание: терминал вернул ${accepted.length} из $sent отправленных кодов.'
        : '';
    return _finish(
      true,
      'Загружено ${accepted.length} кодов (HTTP $lastStatus$skipped). Запись №$recordId.$partial',
      lastStatus,
    );
  }

  /// Коды, которые терминал вернул в ответе 201. Если ответ не похож на
  /// массив кодов — считаем принятыми все отправленные.
  List<MarkingCode> _acceptedFromResponse(dynamic data, List<String> sentB64,
      Map<String, String> rawByBase64, String terminalKey) {
    final details = <String, Map>{};
    if (data is List) {
      for (final item in data) {
        if (item is Map && item['code'] is String) {
          details[item['code'] as String] = item;
        }
      }
    }
    final acceptedB64 = details.isEmpty
        ? sentB64
        : sentB64.where(details.containsKey).toList();

    return [
      for (final b64 in acceptedB64)
        MarkingCode(
          recordId: 0, // проставится при сохранении
          raw: rawByBase64[b64] ?? CodeProcessor.fromBase64(b64),
          base64: b64,
          terminalKey: terminalKey,
          type: details[b64]?['type']?.toString(),
          status: details[b64]?['status']?.toString(),
          createdAt: details[b64]?['createdAt']?.toString(),
        ),
    ];
  }

  UploadOutcome _finish(bool success, String message, [int? status]) {
    isUploading = false;
    progressText = null;
    outcome = UploadOutcome(success, message, status);
    if (success) {
      // После успешной выгрузки файл сбрасываем, чтобы не отправить повторно.
      fileName = null;
      parsed = null;
    }
    notifyListeners();
    return outcome!;
  }
}
