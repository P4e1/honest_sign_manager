import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sign_manager/services/excel_service.dart';

void main() {
  group('Коды из файла выгрузки 1С', () {
    test('читаются из столбца C вместе с серией и кодом проверки', () async {
      final r = await ExcelService.readCodes('test/fixtures/codes.xlsx');

      // ignore: avoid_print
      print('codes=${r.codes.length} dup=${r.duplicatesInFile} '
          'err=${r.errors} структуры=${r.structureSummary}');

      expect(r.codes.length, 100);
      expect(r.errors, isEmpty);

      // Из C приходит полная строка DataMatrix: КИ + GS + код из AI 93.
      expect(r.codes.first, '0104697951542541215Se<Bg\x1D93sRVG');
      // Первая часть содержит два AI: 01 (GTIN) и 21 (серийный номер).
      expect(r.structureSummary, {'01+21+93': 100});
    });

    test('подпись товара из F2 по-прежнему читается', () async {
      final r = await ExcelService.readCodes('test/fixtures/codes.xlsx');
      expect(r.productNameFromFile, isNotNull);
    });
  });

  test('Справочник товаров', () async {
    final r = await ExcelService.readProducts('test/fixtures/products.xlsx');
    final hidden = r.products.where((p) => p.isHidden).map((p) => p.id).toList()
      ..sort();
    // ignore: avoid_print
    print('products=${r.products.length} hidden=$hidden errors=${r.errors}');
    expect(r.products.firstWhere((p) => p.id == 77).name,
        'Колбаса Ливерная «Нежная»');
    expect(r.products.any((p) => p.id == 999924), isTrue);
  });
}
