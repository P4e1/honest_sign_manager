import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// Лёгкий читатель .xlsx: возвращает ячейки первого листа как текст.
///
/// Свой читатель вместо пакета `excel`, потому что:
///  * файлы, выгруженные из 1С, пакет `excel` часто не открывает;
///  * нужно гарантированно получать значения как строки (без потери
///    ведущих нулей и без «1128210582.0»);
///  * нужно корректно раскрывать экранирование `_x001D_` (символ GS).
class XlsxReader {
  /// Результат: номер строки (с 1) → (индекс столбца с 0 → текст).
  static Map<int, Map<int, String>> readFirstSheet(List<int> bytes) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw const FormatException(
          'Файл не является книгой Excel (.xlsx). Формат .xls не поддерживается — '
          'пересохраните файл в .xlsx');
    }

    final sharedStrings = _readSharedStrings(archive);
    final sheetPath = _firstSheetPath(archive);
    final sheetXml = _readXml(archive, sheetPath);
    if (sheetXml == null) {
      throw const FormatException('В книге не найден ни один лист');
    }

    final result = <int, Map<int, String>>{};
    var implicitRow = 0;

    for (final row in _elements(sheetXml, 'row')) {
      implicitRow++;
      final rowNum = int.tryParse(row.getAttribute('r') ?? '') ?? implicitRow;
      implicitRow = rowNum;

      final cells = <int, String>{};
      var implicitCol = -1;

      for (final c in row.childElements.where((e) => e.name.local == 'c')) {
        implicitCol++;
        final ref = c.getAttribute('r');
        final col = ref != null ? _columnIndex(ref) : implicitCol;
        implicitCol = col;

        final value = _cellText(c, sharedStrings);
        if (value != null && value.isNotEmpty) cells[col] = value;
      }
      if (cells.isNotEmpty) result[rowNum] = cells;
    }
    return result;
  }

  /// Индекс столбца по букве: A → 0, B → 1, ...
  static int columnIndexOf(String letters) => _columnIndex('${letters}1');

  // ---------------------------------------------------------------------------

  static String? _cellText(XmlElement c, List<String> sharedStrings) {
    final type = c.getAttribute('t');

    if (type == 'inlineStr') {
      final isEl = _firstChild(c, 'is');
      return isEl == null ? null : _decode(_richText(isEl));
    }

    final v = _firstChild(c, 'v');
    if (v == null) return null;
    final raw = v.innerText;

    switch (type) {
      case 's':
        final idx = int.tryParse(raw);
        if (idx == null || idx < 0 || idx >= sharedStrings.length) return null;
        return sharedStrings[idx];
      case 'str':
        return _decode(raw);
      case 'b':
        return raw == '1' ? 'TRUE' : 'FALSE';
      default:
        return _formatNumber(raw);
    }
  }

  /// «77.0» → «77», чтобы ID товара из числовой ячейки читался корректно.
  static String _formatNumber(String raw) {
    final n = num.tryParse(raw);
    if (n == null) return raw;
    if (n is double && n == n.truncateToDouble() && n.abs() < 1e15) {
      return n.toInt().toString();
    }
    return raw;
  }

  static List<String> _readSharedStrings(Archive archive) {
    final doc = _readXml(archive, 'xl/sharedStrings.xml');
    if (doc == null) return const [];
    return _elements(doc, 'si').map((si) => _decode(_richText(si))).toList();
  }

  /// Текст ячейки = все <t>, кроме фонетических подсказок <rPh>.
  static String _richText(XmlElement el) {
    final buf = StringBuffer();
    for (final t in el.descendants.whereType<XmlElement>()) {
      if (t.name.local != 't') continue;
      final parent = t.parentElement;
      if (parent != null && parent.name.local == 'rPh') continue;
      buf.write(t.innerText);
    }
    return buf.toString();
  }

  /// Excel экранирует управляющие символы как `_xHHHH_` (GS → `_x001D_`).
  static final _escape = RegExp(r'_x([0-9A-Fa-f]{4})_');

  static String _decode(String s) {
    if (!s.contains('_x')) return s;
    return s.replaceAllMapped(_escape, (m) {
      final code = int.parse(m.group(1)!, radix: 16);
      return String.fromCharCode(code);
    });
  }

  static String _firstSheetPath(Archive archive) {
    const fallback = 'xl/worksheets/sheet1.xml';
    final workbook = _readXml(archive, 'xl/workbook.xml');
    final rels = _readXml(archive, 'xl/_rels/workbook.xml.rels');
    if (workbook == null || rels == null) return fallback;

    final sheet = _elements(workbook, 'sheet').firstOrNull;
    if (sheet == null) return fallback;

    final rId = sheet.attributes
        .where((a) => a.name.local == 'id')
        .map((a) => a.value)
        .firstOrNull;
    if (rId == null) return fallback;

    final rel = _elements(rels, 'Relationship')
        .where((r) => r.getAttribute('Id') == rId)
        .firstOrNull;
    final target = rel?.getAttribute('Target');
    if (target == null) return fallback;

    return target.startsWith('/') ? target.substring(1) : 'xl/$target';
  }

  static XmlDocument? _readXml(Archive archive, String path) {
    final file = archive.files
        .where((f) => f.isFile && f.name.toLowerCase() == path.toLowerCase())
        .firstOrNull;
    if (file == null) return null;

    final bytes = file.content as List<int>;
    var text = utf8.decode(bytes, allowMalformed: true);
    if (text.startsWith('\uFEFF')) text = text.substring(1);
    return XmlDocument.parse(text);
  }

  static Iterable<XmlElement> _elements(XmlNode root, String localName) =>
      root.descendants
          .whereType<XmlElement>()
          .where((e) => e.name.local == localName);

  static XmlElement? _firstChild(XmlElement el, String localName) =>
      el.childElements.where((e) => e.name.local == localName).firstOrNull;

  static int _columnIndex(String ref) {
    var result = 0;
    for (final unit in ref.toUpperCase().codeUnits) {
      if (unit < 65 || unit > 90) break; // только буквы A–Z
      result = result * 26 + (unit - 64);
    }
    return result - 1;
  }
}
