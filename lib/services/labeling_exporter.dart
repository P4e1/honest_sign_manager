import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../models/labeling_record.dart';
import '../models/product.dart';
import '../providers/stock_provider.dart';
import '../utils/terminal_address.dart';
import 'xlsx_writer.dart';

/// Формирование Excel-отчёта о нанесении кодов ЧЗ.
class LabelingExporter {
  static Future<void> writeStockReport({
    required String path,
    required Product product,
    required TerminalAddress terminal,
    required StockReport report,
    required StockPeriod period,
    required DateTime generatedAt,
  }) async {
    final bytes = buildStockReport(
      product: product,
      terminal: terminal,
      report: report,
      period: period,
      generatedAt: generatedAt,
    );
    await File(path).writeAsBytes(bytes, flush: true);
  }

  static Uint8List buildStockReport({
    required Product product,
    required TerminalAddress terminal,
    required StockReport report,
    required StockPeriod period,
    required DateTime generatedAt,
  }) {
    final sheets = <XlsxSheet>[
      _summarySheet(product, terminal, report, period, generatedAt),
      _codesSheet(
        title: 'Напечатаны',
        note: 'Статус Ready — коды нанесены на товар',
        codes: report.printed,
      ),
      _codesSheet(
        title: 'Не напечатаны',
        note: 'Загружены через приложение, но нанесения нет',
        codes: const [],
        rawOnly: report.notPrintedCodes,
      ),
      _codesSheet(
        title: 'Отменены',
        note: 'Статус Cancelled — печать отменена',
        codes: report.cancelled,
      ),
      _codesSheet(
        title: 'В обработке',
        note: 'Статус Locked — запись ещё обрабатывается станцией',
        codes: report.locked,
      ),
    ];
    return XlsxWriter.build(sheets);
  }

  // ─── Лист 1: сводка ─────────────────────────────────────────────────────────

  static XlsxSheet _summarySheet(
    Product product,
    TerminalAddress terminal,
    StockReport report,
    StockPeriod period,
    DateTime generatedAt,
  ) {
    final printed = report.printed.length;
    final cancelled = report.cancelled.length;
    final locked = report.locked.length;
    final notPrinted = report.notPrintedCodes.length;

    final rows = <List<Object?>>[
      ['Отчёт о нанесении кодов Честный Знак'],
      [],
      ['Товар', '${product.id} — ${product.name}'],
      ['Терминал', terminal.key],
      ['Адрес', terminal.baseUrl],
      ['Период', period.label],
      ['Сформирован', _dateTime(generatedAt)],
      [],
      ['Показатель', 'Значение', 'Пояснение'],
      [
        'Свободных кодов (NEW)',
        report.freeCount,
        'Остаток на терминале, доступен для нанесения',
      ],
      ['Напечатано (Ready)', printed, 'Коды реально нанесены'],
      ['Отменено (Cancelled)', cancelled, 'Печать отменена'],
      [
        'В обработке (Locked)',
        locked,
        'Запись ещё обрабатывается станцией',
      ],
      [
        'Загружено через приложение',
        report.uploadedUnique,
        'Всего кодов, выгруженных на этот терминал',
      ],
      [
        'Загружено, но не напечатано',
        notPrinted,
        'Коды есть на терминале, но нанесения нет',
      ],
      [],
      ['Проверка сходимости', 'Значение'],
      [
        'Свободные коды минус незапечатанные',
        report.discrepancy,
        'Если 0 — данные сходятся. Если больше 0, часть свободных кодов '
            'загружена не через это приложение или из другого источника. '
            'Если меньше 0 — коды напечатаны, но остаток уже израсходован.',
      ],
      if (report.unknownProduct > 0)
        [
          'Записей без распознанного товара',
          report.unknownProduct,
          'Терминал не вернул productId — такие записи не попали в отчёт '
              'по этому товару',
        ],
    ];

    return XlsxSheet(
      'Сводка',
      rows,
      columnWidths: [34, 22, 70],
    );
  }

  // ─── Листы с кодами по статусам ─────────────────────────────────────────────

  /// Лист со списком кодов в формате ЧЗ.
  ///
  /// [codes] — записи терминала (для напечатанных/отменённых/в обработке),
  /// [rawOnly] — «голые» коды из нашей истории (для ненапечатанных).
  static XlsxSheet _codesSheet({
    required String title,
    required String note,
    required List<LabelingRecord> codes,
    List<String> rawOnly = const [],
  }) {
    final rows = <List<Object?>>[
      [title],
      [note],
      [],
      [
        '№',
        'Код ЧЗ',
        'Base64',
        'Статус',
        'Напечатан',
        'Создан',
        'Отменён',
        'Партия',
        'Дата производства',
        'Годен до',
        'Вес нетто',
        'Вес брутто',
        'Копий',
        'Принтер',
      ],
    ];

    final sorted = [...codes]
      ..sort((a, b) {
        final da = a.printedAt ?? a.createdAt ?? DateTime(1970);
        final db = b.printedAt ?? b.createdAt ?? DateTime(1970);
        return da.compareTo(db);
      });

    var n = 0;
    for (final r in sorted) {
      n++;
      rows.add([
        n,
        r.codeRaw,
        r.codeBase64,
        r.statusLabel,
        _dateTime(r.printedAt),
        _dateTime(r.createdAt),
        _dateTime(r.cancelledAt),
        r.partNumber,
        r.productionDate,
        r.expirationDate,
        r.netWeight,
        r.grossWeight,
        r.printedCount,
        r.printerIndex,
      ]);
    }

    for (final raw in rawOnly) {
      n++;
      rows.add([
        n,
        raw,
        _toBase64(raw),
        'Загружен, не напечатан',
        '',
        '',
        '',
        '',
        '',
        '',
        '',
        '',
        '',
        '',
      ]);
    }

    if (n == 0) {
      rows.add([
        '',
        'Нет кодов в этом статусе за выбранный период',
        '',
        '',
        '',
        '',
        '',
        '',
        '',
        '',
        '',
        '',
        '',
        '',
      ]);
    }

    return XlsxSheet(
      title,
      rows,
      columnWidths: [6, 30, 44, 24, 20, 20, 20, 10, 18, 12, 11, 12, 8, 9],
      // Первые три строки — заголовок листа и пояснение, а не шапка таблицы.
      headerRow: false,
    );
  }

  // ─── Утилиты ────────────────────────────────────────────────────────────────

  static String _toBase64(String raw) => base64Encode(utf8.encode(raw));

  static String _dateTime(DateTime? value) {
    if (value == null) return '';
    final local = value.toLocal();
    return '${_two(local.day)}.${_two(local.month)}.${local.year} '
        '${_two(local.hour)}:${_two(local.minute)}:${_two(local.second)}';
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
}
