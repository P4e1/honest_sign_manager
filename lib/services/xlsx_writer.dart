import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Один лист книги Excel.
class XlsxSheet {
  final String name;
  final List<List<Object?>> rows;
  final List<double> columnWidths;

  /// Первая строка — заголовок (жирным).
  final bool headerRow;

  XlsxSheet(
    this.name,
    this.rows, {
    this.columnWidths = const [],
    this.headerRow = true,
  });
}

/// Минимальный писатель .xlsx.
///
/// Сделан вручную, потому что пакет `excel` тянет зависимости и всё равно
/// не открывает часть файлов из 1С. Здесь нужен только архив: строки
/// пишутся как inline-строки, числа — числами (Excel их складывает).
class XlsxWriter {
  static Uint8List build(List<XlsxSheet> sheets) {
    assert(sheets.isNotEmpty, 'Нужен хотя бы один лист');

    final archive = Archive();

    void add(String name, String xml) {
      final data = Uint8List.fromList(utf8.encode(xml));
      archive.addFile(ArchiveFile(name, data.length, data));
    }

    add('[Content_Types].xml', _contentTypes(sheets.length));
    add('_rels/.rels', _rootRels());
    add('xl/workbook.xml', _workbook(sheets));
    add('xl/_rels/workbook.xml.rels', _workbookRels(sheets.length));
    add('xl/styles.xml', _styles());
    for (var i = 0; i < sheets.length; i++) {
      add('xl/worksheets/sheet${i + 1}.xml', _sheet(sheets[i]));
    }

    final bytes = ZipEncoder().encode(archive);
    return Uint8List.fromList(bytes);
  }

  // ─── Лист ───────────────────────────────────────────────────────────────────

  static String _sheet(XlsxSheet sheet) {
    final buf = StringBuffer()
      ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..write('<worksheet xmlns="http://schemas.openxmlformats.org/'
          'spreadsheetml/2006/main">');

    if (sheet.headerRow && sheet.rows.isNotEmpty) {
      buf.write('<sheetViews><sheetView workbookViewId="0">'
          '<pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" '
          'state="frozen"/></sheetView></sheetViews>');
    }

    if (sheet.columnWidths.isNotEmpty) {
      buf.write('<cols>');
      for (var i = 0; i < sheet.columnWidths.length; i++) {
        buf.write('<col min="${i + 1}" max="${i + 1}" '
            'width="${sheet.columnWidths[i]}" customWidth="1"/>');
      }
      buf.write('</cols>');
    }

    buf.write('<sheetData>');
    for (var r = 0; r < sheet.rows.length; r++) {
      final isHeader = sheet.headerRow && r == 0;
      buf.write('<row r="${r + 1}">');
      final row = sheet.rows[r];
      for (var c = 0; c < row.length; c++) {
        final ref = '${_column(c)}${r + 1}';
        final value = row[c];
        final style = isHeader ? ' s="1"' : '';

        if (value == null) {
          buf.write('<c r="$ref"$style/>');
        } else if (value is num) {
          buf.write('<c r="$ref"$style><v>$value</v></c>');
        } else if (value is bool) {
          buf.write('<c r="$ref"$style t="b"><v>${value ? 1 : 0}</v></c>');
        } else {
          buf.write('<c r="$ref"$style t="inlineStr">'
              '<is><t xml:space="preserve">${_escape(value.toString())}</t></is>'
              '</c>');
        }
      }
      buf.write('</row>');
    }
    buf.write('</sheetData></worksheet>');
    return buf.toString();
  }

  // ─── Служебные части книги ──────────────────────────────────────────────────

  static String _contentTypes(int sheetCount) {
    final buf = StringBuffer()
      ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..write('<Types xmlns="http://schemas.openxmlformats.org/package/2006/'
          'content-types">')
      ..write('<Default Extension="rels" ContentType="application/'
          'vnd.openxmlformats-package.relationships+xml"/>')
      ..write('<Default Extension="xml" ContentType="application/xml"/>')
      ..write('<Override PartName="/xl/workbook.xml" ContentType="application/'
          'vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>')
      ..write('<Override PartName="/xl/styles.xml" ContentType="application/'
          'vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>');
    for (var i = 1; i <= sheetCount; i++) {
      buf.write('<Override PartName="/xl/worksheets/sheet$i.xml" '
          'ContentType="application/vnd.openxmlformats-officedocument.'
          'spreadsheetml.worksheet+xml"/>');
    }
    buf.write('</Types>');
    return buf.toString();
  }

  static String _rootRels() =>
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/'
      'relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/'
      'officeDocument/2006/relationships/officeDocument" '
      'Target="xl/workbook.xml"/></Relationships>';

  static String _workbook(List<XlsxSheet> sheets) {
    final buf = StringBuffer()
      ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..write('<workbook xmlns="http://schemas.openxmlformats.org/'
          'spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/'
          'officeDocument/2006/relationships"><sheets>');
    for (var i = 0; i < sheets.length; i++) {
      buf.write('<sheet name="${_escape(_sheetName(sheets[i].name))}" '
          'sheetId="${i + 1}" r:id="rId${i + 1}"/>');
    }
    buf.write('</sheets></workbook>');
    return buf.toString();
  }

  static String _workbookRels(int sheetCount) {
    final buf = StringBuffer()
      ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..write('<Relationships xmlns="http://schemas.openxmlformats.org/'
          'package/2006/relationships">');
    for (var i = 1; i <= sheetCount; i++) {
      buf.write('<Relationship Id="rId$i" Type="http://schemas.openxmlformats'
          '.org/officeDocument/2006/relationships/worksheet" '
          'Target="worksheets/sheet$i.xml"/>');
    }
    buf.write('<Relationship Id="rId${sheetCount + 1}" '
        'Type="http://schemas.openxmlformats.org/officeDocument/2006/'
        'relationships/styles" Target="styles.xml"/>');
    buf.write('</Relationships>');
    return buf.toString();
  }

  static String _styles() =>
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/'
      '2006/main">'
      '<fonts count="2">'
      '<font><sz val="11"/><name val="Calibri"/></font>'
      '<font><b/><sz val="11"/><name val="Calibri"/></font>'
      '</fonts>'
      '<fills count="2"><fill><patternFill patternType="none"/></fill>'
      '<fill><patternFill patternType="gray125"/></fill></fills>'
      '<borders count="1"><border/></borders>'
      '<cellStyleXfs count="1"><xf/></cellStyleXfs>'
      '<cellXfs count="2">'
      '<xf fontId="0" applyFont="1"/>'
      '<xf fontId="1" applyFont="1" applyAlignment="1">'
      '<alignment vertical="center"/></xf>'
      '</cellXfs>'
      '<cellStyles count="1">'
      '<cellStyle name="Normal" xfId="0" builtinId="0"/>'
      '</cellStyles>'
      '<dxfs count="0"/>'
      '</styleSheet>';

  // ─── Утилиты ────────────────────────────────────────────────────────────────

  /// Имя листа: Excel запрещает : \ / ? * [ ] и длину больше 31 символа.
  static String _sheetName(String name) {
    var clean = name.replaceAll(RegExp(r'[:\\/?*\[\]]'), ' ').trim();
    if (clean.isEmpty) clean = 'Лист';
    return clean.length > 31 ? clean.substring(0, 31) : clean;
  }

  static String _column(int index) {
    var n = index + 1;
    final chars = <String>[];
    while (n > 0) {
      final rem = (n - 1) % 26;
      chars.insert(0, String.fromCharCode(65 + rem));
      n = (n - 1) ~/ 26;
    }
    return chars.join();
  }

  /// Экранирование под XML + удаление управляющих символов,
  /// которые Excel считает недопустимыми.
  static String _escape(String text) {
    final buf = StringBuffer();
    for (final rune in text.runes) {
      if (rune < 0x20 && rune != 0x09 && rune != 0x0A && rune != 0x0D) {
        continue;
      }
      switch (rune) {
        case 0x26:
          buf.write('&amp;');
        case 0x3C:
          buf.write('&lt;');
        case 0x3E:
          buf.write('&gt;');
        case 0x22:
          buf.write('&quot;');
        case 0x27:
          buf.write('&apos;');
        default:
          buf.writeCharCode(rune);
      }
    }
    return buf.toString();
  }
}
