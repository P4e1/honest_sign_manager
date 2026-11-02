import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sign_manager/models/labeling_record.dart';
import 'package:honest_sign_manager/models/product.dart';
import 'package:honest_sign_manager/providers/stock_provider.dart';
import 'package:honest_sign_manager/services/labeling_exporter.dart';
import 'package:honest_sign_manager/utils/terminal_address.dart';

void main() {
  test('Excel-отчёт формируется', () {
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
        uploadedRawCodes: ['0104697951542541215Se<Bg', '0104697951542541215cYMzf'],
        unknownProduct: 2,
      ),
      period: StockPeriod.month,
      generatedAt: DateTime(2026, 11, 2, 12, 0, 0),
    );

    expect(bytes.length, greaterThan(1000));
    File('/tmp/report_test.xlsx').writeAsBytesSync(bytes);
  });
}
