import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sign_manager/models/labeling_record.dart';
import 'package:honest_sign_manager/models/product.dart';
import 'package:honest_sign_manager/providers/stock_provider.dart';
import 'package:honest_sign_manager/services/labeling_exporter.dart';
import 'package:honest_sign_manager/utils/terminal_address.dart';

/// Тест держим целиком в памяти.
///
/// Раньше здесь был writeAsBytesSync в системный temp — и на Windows этот
/// тест заметно тормозил: антивирус проверяет каждый созданный файл.
/// Проверять «файл записался» смысла нет, а вот «байты — это корректный
/// xlsx с нужными листами» проверить можно и без диска.
void main() {
  test('Excel-отчёт формируется и является корректным xlsx', () {
    final record = LabelingRecord.fromJson({
      'id': 'rec-1',
      'exportStatus': 'Ready',
      'honestSignCode': 'MDEwNDY5Nzk1MTU0MjE1U2U8Qmc=',
      'honestSignCodeMeta': {'productId': 77, 'code': 'MDEwNDY5'},
      'product': {'name': 'Колбаса Ливерная «Нежная»'},
      'generatedData': {
        'productionDate': '01.11.2026',
        'expirationDate': '01.12.2026',
        'netWeight': '1.500',
        'grossWeight': '1.520',
        'partNumber': '001',
      },
      'printedCount': 1,
      'printedAt': '2026-11-01T10:00:00.000Z',
    });

    expect(record, isNotNull);
    expect(record!.productId, 77);

    final bytes = LabelingExporter.buildStockReport(
      product: const Product(id: 77, name: 'Колбаса Ливерная «Нежная»'),
      terminal: TerminalAddress.tryParse('http://192.168.1.82:4001/api')!,
      report: StockReport(
        freeCount: 500,
        labeling: [record],
        uploadedRawCodes: [
          '0104697951542541215Se<Bg',
          '0104697952541215cYMzf',
        ],
        unknownProduct: 2,
      ),
      period: StockPeriod.month,
      generatedAt: DateTime(2026, 11, 2, 12, 0, 0),
    );

    expect(bytes.length, greaterThan(1000));

    // Байты должны распаковываться как ZIP — иначе Excel файл не откроет.
    final archive = ZipDecoder().decodeBytes(bytes);
    final names = archive.files.map((f) => f.name).toSet();

    // Обязательные части книги
    expect(names, contains('[Content_Types].xml'));
    expect(names, contains('xl/workbook.xml'));
    expect(names, contains('xl/styles.xml'));
    expect(names, contains('xl/worksheets/sheet1.xml'));

    // Все пять листов на месте
    for (var i = 1; i <= 5; i++) {
      expect(names, contains('xl/worksheets/sheet$i.xml'),
          reason: 'Нет листа sheet$i.xml');
    }

    // В книге пять записей <sheet>
    final workbook = utf8.decode(
      archive.files.firstWhere((f) => f.name == 'xl/workbook.xml').content
          as List<int>,
    );
    expect('<sheet '.allMatches(workbook).length, 5);

    // Названия листов — по статусам
    for (final title in const [
      'Сводка',
      'Напечатаны',
      'Не напечатаны',
      'Отменены',
      'В обработке',
    ]) {
      expect(workbook, contains(title), reason: 'Нет листа «$title»');
    }

    // Код ЧЗ попал в лист «Напечатаны» в читаемом виде
    final sheet2 = utf8.decode(
      archive.files.firstWhere((f) => f.name == 'xl/worksheets/sheet2.xml')
          .content as List<int>,
    );
    expect(sheet2, contains('010469795154215Se&lt;Bg'),
        reason: 'Код ЧЗ не найден на листе «Напечатаны»');
    expect(sheet2, contains('Напечатан'));
  });
}
