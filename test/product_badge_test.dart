import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sign_manager/services/code_processor.dart';
import 'package:honest_sign_manager/services/excel_service.dart';

void main() {
  group('normalizeProductName', () {
    test('кавычки и регистр не мешают сравнению', () {
      expect(
        normalizeProductName('Колбаса Ливерная «Нежная»'),
        normalizeProductName('Колбаса Ливерная Нежная'),
      );
      expect(
        normalizeProductName('КОЛБАСА ЛИВЕРНАЯ НЕЖНАЯ'),
        normalizeProductName('колбаса ливерная нежная'),
      );
    });

    test('разные товары не склеиваются', () {
      expect(
        normalizeProductName('Колбаса Ливерная «Нежная»'),
        isNot(normalizeProductName('Колбаса Докторская вареная ГОСТ 450г')),
      );
    });

    test('лишние пробелы и знаки препинания убираются', () {
      expect(
        normalizeProductName('  Сало   соленое,  по-Белорусски (лопаточное) '),
        normalizeProductName('Сало соленое по Белорусски лопаточное'),
      );
    });

    test('цифры сохраняются — они различают товары', () {
      expect(
        normalizeProductName('Шпик по-Белорусски (2-4)'),
        isNot(normalizeProductName('Шпик по-Белорусски (6+)')),
      );
      expect(
        normalizeProductName('Шпик по-Белорусски (2-4)'),
        normalizeProductName('Шпик по Белорусски 2 4'),
      );
    });
  });

  group('Чтение названия товара из файла', () {
    test('F2 и E2 читаются из настоящего файла 1С', () async {
      final result = await ExcelService.readCodes('test/fixtures/codes.xlsx');

      // В файле 100 кодов
      expect(result.codes.length, 100);

      // R2C6 — наименование товара
      expect(result.productNameFromFile, 'Колбаса Ливерная Нежная');

      // R2C5 — внутренний ID из 1С (не ID справочника)
      expect(result.productIdFromFile, '1128210582');

      expect(result.hasProductInfo, isTrue);
    });

    test('название из файла совпадает со справочником после нормализации',
        () async {
      final result = await ExcelService.readCodes('test/fixtures/codes.xlsx');
      // В справочнике товар записан с кавычками
      const fromCatalog = 'Колбаса Ливерная «Нежная»';

      expect(
        normalizeProductName(result.productNameFromFile!),
        normalizeProductName(fromCatalog),
      );
    });
  });
}
