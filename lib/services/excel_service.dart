import 'dart:io';

import '../models/product.dart';
import 'code_processor.dart';
import 'xlsx_reader.dart';

/// Чтение файлов Excel: коды маркировки и справочник товаров.
class ExcelService {
  /// Столбец с кодами маркировки.
  ///
  /// Это C, а не B. В выгрузках 1С столбец B — только код идентификации
  /// (`01`+GTIN+`21`+серийный, 24 символа). В столбце C лежит полная строка
  /// DataMatrix: тот же код идентификации, затем через разделитель GS
  /// код серии партии (AI 91) и код проверки (AI 92).
  /// Терминал принимает только полный вариант из C.
  static const codesColumn = 'C';

  /// Столбец с кодом идентификации — нужен только для диагностики,
  /// когда в C пусто: так понятно, что файл не той выгрузки.
  static const kiColumn = 'B';

  /// Первая строка — заголовок.
  static const headerRows = 1;

  /// Ячейка с наименованием товара: F2 (столбец 5, строка 2).
  static const productNameCell = (column: 5, row: 2);

  /// Ячейка с ID товара из 1С: E2 (столбец 4, строка 2).
  static const productIdCell = (column: 4, row: 2);

  /// Читает коды из столбца C и подпись товара из F2.
  static Future<CodeParseResult> readCodes(String path) async {
    final bytes = await File(path).readAsBytes();
    final sheet = XlsxReader.readFirstSheet(bytes);

    final codesCol = XlsxReader.columnIndexOf(codesColumn);
    final kiCol = XlsxReader.columnIndexOf(kiColumn);

    final values = <int, String>{};
    final missingColumnC = <int>[];
    var hasKiButNoCode = 0;

    sheet.forEach((rowNum, cells) {
      if (rowNum <= headerRows) return;

      final code = cells[codesCol]?.trim();
      final ki = cells[kiCol]?.trim() ?? '';

      if (code == null || code.isEmpty) {
        // Строка заполнена по столбцу B, но C пуст — это почти наверняка
        // файл, где кодов с криптохвостом нет вовсе.
        if (ki.isNotEmpty) {
          hasKiButNoCode++;
          missingColumnC.add(rowNum);
        }
        return;
      }

      values[rowNum] = code;
    });

    final parsed = CodeProcessor.parse(values);

    final errors = <String>[...parsed.errors];

    // Если ни одного кода в C не нашлось, а в B они есть — файл не подходит:
    // объясняем это одной понятной строкой вместо сотни «пустая ячейка».
    if (parsed.codes.isEmpty && hasKiButNoCode > 0) {
      errors
        ..clear()
        ..add('В столбце C нет кодов, хотя столбец B заполнен '
            '($hasKiButNoCode строк). Похоже, это выгрузка без кодов '
            'DataMatrix — нужен файл, где в столбце C есть серия партии '
            'и код проверки.');
    } else if (missingColumnC.isNotEmpty) {
      // Часть строк заполнена только по B. Показываем первые, чтобы
      // не заваливать пользователя сотней одинаковых сообщений.
      const shown = 10;
      for (final rowNum in missingColumnC.take(shown)) {
        errors.add('Строка $rowNum: пустой столбец C '
            '(в B есть код идентификации, но нет серии и кода проверки)');
      }
      if (missingColumnC.length > shown) {
        errors.add('…и ещё ${missingColumnC.length - shown} строк '
            'с пустым столбцом C');
      }
    }

    return CodeParseResult(
      codes: parsed.codes,
      duplicatesInFile: parsed.duplicatesInFile,
      errors: errors,
      structureSummary: parsed.structureSummary,
      productNameFromFile:
          _cellText(sheet, productNameCell.column, productNameCell.row),
      productIdFromFile:
          _cellText(sheet, productIdCell.column, productIdCell.row),
    );
  }

  /// Текст ячейки по индексу столбца (с нуля) и номеру строки (с единицы).
  static String? _cellText(
      Map<int, Map<int, String>> sheet, int column, int row) {
    final value = sheet[row]?[column]?.trim();
    if (value == null || value.isEmpty) return null;
    return value;
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
