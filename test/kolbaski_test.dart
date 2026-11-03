import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sign_manager/services/excel_service.dart';
import 'package:honest_sign_manager/services/xlsx_reader.dart';

void main() {
  test('Файл «Колбаски из печи» — F2 читается', () async {
    final path = 'test/fixtures/kolbaski.xlsx';

    // Сначала сырой читатель: что он видит в строке 2
    final bytes = await File(path).readAsBytes();
    final sheet = XlsxReader.readFirstSheet(bytes);
    // ignore: avoid_print
    print('строка 2: ${sheet[2]}');

    final result = await ExcelService.readCodes(path);
    // ignore: avoid_print
    print('кодов: ${result.codes.length}');
    // ignore: avoid_print
    print('F2 = ${result.productNameFromFile}');
    // ignore: avoid_print
    print('E2 = ${result.productIdFromFile}');

    expect(result.codes.length, 500);
    expect(result.productNameFromFile, 'Колбаски из печи');
    expect(result.productIdFromFile, '1127734512');
  });
}
