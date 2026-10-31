import 'dart:io';

import '../models/product.dart';
import 'code_processor.dart';
import 'xlsx_reader.dart';

/// Чтение файлов Excel: коды маркировки и справочник товаров.
class ExcelService {
  /// Столбец с кодами (по договорённости — B, КИ без криптохвоста).
  static const codesColumn = 'B';

  /// Первая строка — заголовок.
  static const headerRows = 1;

  static Future<CodeParseResult> readCodes(String path) async {
    final bytes = await File(path).readAsBytes();
    final sheet = XlsxReader.readFirstSheet(bytes);
    final col = XlsxReader.columnIndexOf(codesColumn);

    final values = <int, String>{};
    sheet.forEach((rowNum, cells) {
      if (rowNum <= headerRows) return;
      final v = cells[col];
      if (v != null) values[rowNum] = v;
    });
    return CodeProcessor.parse(values);
  }

  /// Справочник: столбец A — ID (1…99999999), столбец B — наименование.
  /// Позиции с «#» в начале названия помечаются как скрытые.
  static Future<ProductImportResult> readProducts(String path) async {
    final bytes = await File(path).readAsBytes();
    final sheet = XlsxReader.readFirstSheet(bytes);

    final products = <int, Product>{};
    final errors = <String>[];

    final rowNumbers = sheet.keys.toList()..sort();
    for (final rowNum in rowNumbers) {
      if (rowNum <= headerRows) continue;
      final cells = sheet[rowNum]!;
      final idText = cells[0]?.trim() ?? '';
      final name = cells[1]?.trim() ?? '';
      if (idText.isEmpty && name.isEmpty) continue;

      final id = int.tryParse(idText) ?? double.tryParse(idText)?.toInt();
      if (id == null || id < 1 || id > 99999999) {
        errors.add('Строка $rowNum: некорректный ID «$idText»');
        continue;
      }
      if (name.isEmpty) {
        errors.add('Строка $rowNum: пустое наименование (ID $id)');
        continue;
      }
      products[id] = Product(id: id, name: name, isHidden: name.startsWith('#'));
    }

    return ProductImportResult(products.values.toList(), errors);
  }
}

class ProductImportResult {
  final List<Product> products;
  final List<String> errors;
  const ProductImportResult(this.products, this.errors);
}
