import 'dart:convert';

/// Результат разбора файла с кодами.
class CodeParseResult {
  /// Уникальные корректные коды в исходном виде, в порядке появления в файле.
  final List<String> codes;

  /// Сколько повторов внутри файла было отброшено.
  final int duplicatesInFile;

  /// Ошибки формата: «Строка 15: ...».
  final List<String> errors;

  /// Наименование товара из ячейки F2 (R2C6) — подпись из 1С.
  /// Нужно для сверки глазами: помогает заметить, что выбран не тот товар.
  final String? productNameFromFile;

  /// ID товара из ячейки E2 (R2C5). В выгрузках 1С это внутренний
  /// идентификатор, он не совпадает с ID справочника — только для справки.
  final String? productIdFromFile;

  const CodeParseResult({
    required this.codes,
    required this.duplicatesInFile,
    required this.errors,
    this.productNameFromFile,
    this.productIdFromFile,
  });

  /// Есть что показать пользователю для сверки.
  bool get hasProductInfo =>
      (productNameFromFile != null && productNameFromFile!.isNotEmpty);
}

/// Сравнение названий товаров «по-человечески»: без кавычек, знаков
/// препинания, лишних пробелов и регистра.
///
/// «Колбаса Ливерная «Нежная»» и «Колбаса Ливерная Нежная» дают один ключ.
/// Всё, что не буква и не цифра, считается разделителем.
String normalizeProductName(String value) {
  final buffer = StringBuffer();
  for (final rune in value.toLowerCase().runes) {
    final ch = String.fromCharCode(rune);
    final isLetter = RegExp(r'[a-zа-яё]', caseSensitive: false)
        .hasMatch(ch);
    final isDigit = rune >= 0x30 && rune <= 0x39;
    buffer.write(isLetter || isDigit ? ch : ' ');
  }

  return buffer
      .toString()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .join(' ');
}

class CodeProcessor {
  /// Код ЧЗ: «01» + 14 цифр GTIN + «21» + серийный номер.
  static final _codePattern = RegExp(r'^01\d{14}21.+$', dotAll: true);

  static bool isValidCode(String code) => _codePattern.hasMatch(code);

  /// Кодирование в Base64 через UTF-8 (совпадает с примером из API:
  /// `0104697951542541215Se<Bg` → `MDEwNDY5Nzk1MTU0MjU0MTIxNVNlPEJn`).
  static String toBase64(String code) => base64Encode(utf8.encode(code));

  static String fromBase64(String value) {
    try {
      return utf8.decode(base64Decode(value));
    } catch (_) {
      return value;
    }
  }

  /// [rows] — номер строки Excel → значение ячейки.
  /// Пробелы внутри и по краям НЕ удаляются: они бывают частью серийного номера.
  static CodeParseResult parse(Map<int, String> rows) {
    final codes = <String>[];
    final seen = <String>{};
    final errors = <String>[];
    var duplicates = 0;

    final rowNumbers = rows.keys.toList()..sort();
    for (final rowNum in rowNumbers) {
      final value = rows[rowNum]!.replaceAll('\r', '').replaceAll('\n', '');
      if (value.trim().isEmpty) continue;

      if (!isValidCode(value)) {
        errors.add('Строка $rowNum: неверный формат «$value»');
        continue;
      }
      if (!seen.add(value)) {
        duplicates++;
        continue;
      }
      codes.add(value);
    }

    return CodeParseResult(
      codes: codes,
      duplicatesInFile: duplicates,
      errors: errors,
    );
  }

  /// Разбивает список на пачки по [size] элементов.
  static List<List<T>> chunk<T>(List<T> items, int size) {
    final result = <List<T>>[];
    for (var i = 0; i < items.length; i += size) {
      final end = (i + size < items.length) ? i + size : items.length;
      result.add(items.sublist(i, end));
    }
    return result;
  }
}
