import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sign_manager/services/excel_service.dart';

void main() {
  test('Коды из примера', () async {
    final r = await ExcelService.readCodes('test/fixtures/codes.xlsx');
    // ignore: avoid_print
    print('codes=${r.codes.length} dup=${r.duplicatesInFile} err=${r.errors}');
    expect(r.codes.length, 100);
    expect(r.codes.first, '0104697951542541215Se<Bg');
    expect(r.errors, isEmpty);
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
