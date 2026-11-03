import 'dart:convert';

/// Одна запись истории маркировки (напечатанная этикетка).
///
/// Структура ответа терминала нарочно разбирается «мягко»: часть полей
/// (`product`, `plu`, `label`) в документации описана как пустые объекты,
/// поэтому берём то, что реально пришло, и не падаем, если чего-то нет.
class LabelingRecord {
  final String id;

  /// ID товара: из honestSignCodeMeta, иначе из product.
  final int? productId;

  final String productName;

  /// Код в Base64 (как пришёл) и в исходном виде.
  final String codeBase64;
  final String codeRaw;

  /// Locked / Ready / Cancelled.
  final String exportStatus;

  final DateTime? printedAt;
  final DateTime? createdAt;
  final DateTime? cancelledAt;

  final int printedCount;
  final int printerIndex;

  /// Данные партии на момент печати.
  final String productionDate;
  final String expirationDate;
  final String netWeight;
  final String grossWeight;
  final String partNumber;

  const LabelingRecord({
    required this.id,
    required this.productId,
    required this.productName,
    required this.codeBase64,
    required this.codeRaw,
    required this.exportStatus,
    required this.printedAt,
    required this.createdAt,
    required this.cancelledAt,
    required this.printedCount,
    required this.printerIndex,
    required this.productionDate,
    required this.expirationDate,
    required this.netWeight,
    required this.grossWeight,
    required this.partNumber,
  });

  bool get isReady => exportStatus == 'Ready';
  bool get isCancelled => exportStatus == 'Cancelled';
  bool get isLocked => exportStatus == 'Locked';

  /// Напечатано и не отменено — код реально нанесён.
  bool get isPrinted => isReady;

  String get statusLabel => switch (exportStatus) {
        'Ready' => 'Напечатан',
        'Cancelled' => 'Отменён',
        'Locked' => 'Обрабатывается',
        _ => exportStatus,
      };

  static LabelingRecord? fromJson(Map<String, dynamic> json) {
    final meta = _map(json['honestSignCodeMeta']);

    final codeBase64 =
        (json['honestSignCode'] ?? meta?['code'] ?? '').toString();
    if (codeBase64.isEmpty) return null;

    final product = _map(json['product']);

    final productId = _asInt(meta?['productId']) ??
        _asInt(product?['id']) ??
        _asInt(product?['productId']);

    final generated = _map(json['generatedData']) ?? const {};

    return LabelingRecord(
      id: (json['id'] ?? '').toString(),
      productId: productId,
      productName: _productName(product),
      codeBase64: codeBase64,
      codeRaw: _decodeBase64(codeBase64),
      exportStatus: (json['exportStatus'] ?? '').toString(),
      printedAt: _asDate(json['printedAt']),
      createdAt: _asDate(json['createdAt']),
      cancelledAt: _asDate(json['cancelledAt']),
      printedCount: _asInt(json['printedCount']) ?? 1,
      printerIndex: _asInt(json['printerIndex']) ?? 0,
      productionDate: (generated['productionDate'] ?? '').toString(),
      expirationDate: (generated['expirationDate'] ?? '').toString(),
      netWeight: (generated['netWeight'] ?? '').toString(),
      grossWeight: (generated['grossWeight'] ?? '').toString(),
      partNumber: (generated['partNumber'] ?? '').toString(),
    );
  }

  /// Наименование товара лежит в одном из полей — какое придёт, то и берём.
  static String _productName(Map<String, dynamic>? product) {
    if (product == null) return '';
    for (final key in const ['name', 'fullName', 'title', 'productName']) {
      final value = product[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return '';
  }

  static Map<String, dynamic>? _map(dynamic value) =>
      value is Map<String, dynamic> ? value : null;

  static int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static DateTime? _asDate(dynamic value) {
    if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
    return null;
  }

  static String _decodeBase64(String value) {
    try {
      return utf8.decode(base64Decode(value));
    } catch (_) {
      return value;
    }
  }
}

/// Совокупный ответ по товару: остаток, напечатанные и не напечатанные коды.
class StockReport {
  /// Свободные коды в статусе NEW — из GET /codes/{productId}/count.
  final int freeCount;

  /// Все записи маркировки по этому товару (для выбранного периода).
  final List<LabelingRecord> labeling;

  /// Коды, загруженные через наше приложение на этот терминал.
  final List<String> uploadedRawCodes;

  /// Записи, где товар не удалось определить (productId == null).
  final int unknownProduct;

  const StockReport({
    required this.freeCount,
    required this.labeling,
    required this.uploadedRawCodes,
    required this.unknownProduct,
  });

  List<LabelingRecord> get printed =>
      labeling.where((r) => r.isPrinted).toList();

  List<LabelingRecord> get cancelled =>
      labeling.where((r) => r.isCancelled).toList();

  List<LabelingRecord> get locked =>
      labeling.where((r) => r.isLocked).toList();

  Set<String> get printedCodes =>
      {for (final r in printed) r.codeRaw};

  Set<String> get cancelledCodes =>
      {for (final r in cancelled) r.codeRaw};

  Set<String> get lockedCodes =>
      {for (final r in locked) r.codeRaw};

  /// Напечатанные коды, которых нет среди отменённых — гарантированно нанесены.
  Set<String> get effectivePrintedCodes =>
      printedCodes.difference(cancelledCodes);

  /// Загруженные нами коды, которых нет среди напечатанных.
  List<String> get notPrintedCodes {
    final printedSet = printedCodes;
    final seen = <String>{};
    return [
      for (final raw in uploadedRawCodes)
        if (!printedSet.contains(raw) && seen.add(raw)) raw,
    ];
  }

  /// Сколько кодов мы загрузили всего (уникальных).
  int get uploadedUnique => {...uploadedRawCodes}.length;

  /// Расхождение между остатком на терминале и нашей историей.
  ///
  /// Если терминал показывает больше свободных кодов, чем у нас есть
  /// незапечатанных — значит часть кодов загружена не через это приложение.
  int get discrepancy => freeCount - notPrintedCodes.length;
}
