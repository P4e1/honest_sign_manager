import 'dart:convert';

/// Разделитель GS (ASCII 0x1D) — граница между полями DataMatrix.
const gsSeparator = '\x1D';

/// Разобранный код маркировки из столбца C.
///
/// Столбец C содержит готовую строку DataMatrix: поля разделены символом GS,
/// каждое начинается с идентификатора применения (AI).
///
/// Типичный вид:
/// ```
/// 01 04697951542015 21 5HMm"G ␝ 91 EE12 ␝ 92 YIpi52v0jHZseLVtwQA3K+...
/// └───── код идентификации ─────┘   └ партия ┘  └── код проверки ──┘
/// ```
///
/// Столбец B при этом содержит только первые 24 символа — код идентификации
/// без кода серии и кода проверки. Такой усечённый код терминал не принимает.
class DataMatrixCode {
  /// Код целиком, как пришёл из файла, вместе с разделителями GS.
  final String raw;

  /// Код идентификации: `01` + GTIN(14) + `21` + серийный номер.
  final String ki;

  /// GTIN из 14 цифр.
  final String gtin;

  /// Серийный номер изделия (AI 21).
  final String serial;

  /// Код серии партии (AI 91). Может отсутствовать в старых выгрузках.
  final String? batch;

  /// Код проверки (AI 92). Может отсутствовать в старых выгрузках.
  final String? check;

  /// Все идентификаторы применения по порядку: `01`, `91`, `92`.
  final List<String> applicationIdentifiers;

  const DataMatrixCode({
    required this.raw,
    required this.ki,
    required this.gtin,
    required this.serial,
    required this.applicationIdentifiers,
    this.batch,
    this.check,
  });

  /// Человекочитаемое описание структуры для интерфейса и отчётов.
  String describe() {
    final parts = <String>[
      'GTIN $gtin',
      'серийный $serial',
      if (batch != null) 'партия $batch',
      if (check != null) 'проверка ${check!.length} симв.',
    ];
    return parts.join(' · ');
  }

  /// Набор идентификаторов применения: `01+91+92`.
  String get structure => applicationIdentifiers.join('+');

  @override
  String toString() => '$structure: ${describe()}';
}

/// Результат разбора файла с кодами.
class CodeParseResult {
  /// Уникальные корректные коды в исходном виде, в порядке появления в файле.
  final List<String> codes;

  /// Сколько повторов внутри файла было отброшено.
  final int duplicatesInFile;

  /// Ошибки формата: «Строка 15: ...».
  final List<String> errors;

  /// Сколько кодов пришлось на каждую структуру: `{'01+91+92': 652}`.
  ///
  /// Нужно, чтобы заметить файл со смешанными форматами: если структур
  /// больше одной, часть кодов может не содержать кода проверки.
  final Map<String, int> structureSummary;

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
    this.structureSummary = const {},
    this.productNameFromFile,
    this.productIdFromFile,
  });

  /// Есть что показать пользователю для сверки.
  bool get hasProductInfo =>
      (productNameFromFile != null && productNameFromFile!.isNotEmpty);

  /// В файле встретились коды разной структуры.
  bool get hasMixedStructures => structureSummary.length > 1;
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
  /// Код идентификации: «01» + 14 цифр GTIN + «21» + серийный номер.
  ///
  /// Проверяем только первую часть — до первого разделителя GS.
  /// Остальные поля (91, 92) не разбираем жёстко: в старых выгрузках 1С
  /// вместо них стоит 93, и такие файлы должны продолжать читаться.
  static final _kiPattern = RegExp(r'^01\d{14}21.+$', dotAll: true);

  /// Проверяет код маркировки.
  ///
  /// Требуется только корректный код идентификации — первая часть строки
  /// до разделителя GS. Наличие и состав остальных полей не проверяется:
  /// терминал сам решает, полный это DataMatrix или нет.
  static bool isValidCode(String code) {
    if (code.isEmpty) return false;
    final ki = code.split(gsSeparator).first;
    return _kiPattern.hasMatch(ki);
  }

  /// Разбирает код на составные части.
  ///
  /// Возвращает null, если код не похож на маркировку Честного Знака.
  static DataMatrixCode? decode(String raw) {
    if (raw.isEmpty) return null;

    final parts = raw.split(gsSeparator);
    final ki = parts.first;

    if (!_kiPattern.hasMatch(ki)) return null;

    final gtin = ki.substring(2, 16);
    final serial = ki.substring(18);

    String? batch;
    String? check;
    final ais = <String>['01', '21'];

    for (final part in parts.skip(1)) {
      if (part.length < 2) continue;
      final ai = part.substring(0, 2);
      final value = part.substring(2);
      ais.add(ai);

      switch (ai) {
        case '91':
          batch = value;
        case '92':
          check = value;
        // Всё остальное (например, 93 в старых выгрузках) сохраняем
        // в списке AI, но отдельным полем не выделяем.
      }
    }

    return DataMatrixCode(
      raw: raw,
      ki: ki,
      gtin: gtin,
      serial: serial,
      batch: batch,
      check: check,
      applicationIdentifiers: ais,
    );
  }

  /// Кодирование в Base64 через UTF-8 (совпадает с примером из API:
  /// `0104697951542541215Se<Bg` → `MDEwNDY5Nzk1MTU0MjU0MTIxNVNlPEJn`).
  ///
  /// Кодируется вся строка целиком, вместе с разделителями GS —
  /// иначе терминал получит обрезанный код.
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
    final summary = <String, int>{};
    var duplicates = 0;

    final rowNumbers = rows.keys.toList()..sort();
    for (final rowNum in rowNumbers) {
      final value =
          rows[rowNum]!.replaceAll('\r', '').replaceAll('\n', '').trim();
      if (value.isEmpty) {
        errors.add('Строка $rowNum: пустая ячейка в столбце с кодами');
        continue;
      }

      final decoded = decode(value);
      if (decoded == null) {
        errors.add('Строка $rowNum: неверный формат «${_shorten(value)}»');
        continue;
      }

      if (!seen.add(value)) {
        duplicates++;
        continue;
      }

      codes.add(value);
      summary[decoded.structure] = (summary[decoded.structure] ?? 0) + 1;
    }

    return CodeParseResult(
      codes: codes,
      duplicatesInFile: duplicates,
      errors: errors,
      structureSummary: summary,
    );
  }

  /// Обрезает длинный код для сообщения об ошибке.
  static String _shorten(String value, [int max = 40]) {
    if (value.length <= max) return value;
    return '${value.substring(0, max)}…';
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
