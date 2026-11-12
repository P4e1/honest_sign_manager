import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sign_manager/services/code_processor.dart';
import 'package:honest_sign_manager/services/excel_service.dart';

void main() {
  group('Столбец C — полный DataMatrix', () {
    test('коды читаются из C, а не из B', () async {
      final r = await ExcelService.readCodes('test/fixtures/codes.xlsx');

      expect(r.codes.length, 100);
      expect(r.errors, isEmpty);

      // Код теперь включает хвост: разделитель GS и код из AI 93.
      expect(r.codes.first, '0104697951542541215Se<Bg\x1D93sRVG');

      // Столбец B (24 символа) больше не используется.
      expect(r.codes.first.length, greaterThan(24));
    });

    test('структура 01+91+92 разбирается по полям', () async {
      final r = await ExcelService.readCodes('test/fixtures/codes_91_92.xlsx');

      expect(r.codes.length, 652);
      expect(r.errors, isEmpty);
      expect(r.structureSummary, {'01+21+91+92': 652});

      final decoded = CodeProcessor.decode(r.codes.first)!;

      expect(decoded.gtin, '04697951542015');
      expect(decoded.serial, '5HMm"G');
      expect(decoded.batch, 'EE12');
      expect(decoded.check!.length, 44);
      expect(decoded.check, endsWith('='));
      expect(decoded.applicationIdentifiers, ['01', '21', '91', '92']);

      // Код идентификации — первые 24 символа, ровно как в столбце B.
      expect(decoded.ki, '0104697951542015215HMm"G');
      expect(decoded.ki.length, 24);
    });

    test('все 652 кода имеют одинаковую структуру', () async {
      final r = await ExcelService.readCodes('test/fixtures/codes_91_92.xlsx');

      expect(r.hasMixedStructures, isFalse,
          reason: 'в этом файле структура должна быть одна');

      for (final code in r.codes) {
        final d = CodeProcessor.decode(code);
        expect(d, isNotNull, reason: 'код не разобрался: $code');
        expect(d!.structure, '01+21+91+92');
        expect(d.batch, 'EE12', reason: 'код серии партии одинаков во всём файле');
        expect(d.gtin, '04697951542015');
      }
    });

    test('код целиком уходит в Base64 вместе с разделителями GS', () {
      final r = CodeProcessor.parse({
        2: '0104697951542015215HMm"G\x1D91EE12\x1D92YIpi52v0jHZseLVtwQA3K+',
      });

      final code = r.codes.single;
      final base64 = CodeProcessor.toBase64(code);

      // Декодирование возвращает тот же код со всеми разделителями.
      expect(CodeProcessor.fromBase64(base64), code);
      expect(CodeProcessor.fromBase64(base64).split(gsSeparator).length, 3);
    });
  });

  group('Старые файлы со структурой 01+93', () {
    test('по-прежнему читаются', () async {
      final r = await ExcelService.readCodes('test/fixtures/kolbaski.xlsx');

      expect(r.codes.length, 500);
      expect(r.errors, isEmpty);
      expect(r.structureSummary, {'01+21+93': 500});
    });

    test('AI 93 не ломает разбор: серия и проверка остаются пустыми', () {
      final d = CodeProcessor.decode('0104697951542503215tZah-\x1D933eFn')!;

      expect(d.gtin, '04697951542503');
      expect(d.serial, '5tZah-');
      expect(d.batch, isNull, reason: 'в старом формате нет AI 91');
      expect(d.check, isNull, reason: 'в старом формате нет AI 92');
      expect(d.applicationIdentifiers, contains('93'));
      expect(d.structure, '01+21+93');
    });
  });

  group('Проверка формата кода', () {
    test('корректный код идентификации проходит', () {
      expect(CodeProcessor.isValidCode('0104697951542541215Se<Bg'), isTrue);
      expect(CodeProcessor.isValidCode('0104697951542015215HMm"G\x1D91EE12'),
          isTrue);
    });

    test('заголовок и обрезки отклоняются', () {
      expect(CodeProcessor.isValidCode('КИ (код идентификации)'), isFalse);
      expect(CodeProcessor.isValidCode('01046979515425'), isFalse);
      expect(CodeProcessor.isValidCode(''), isFalse);
      expect(CodeProcessor.isValidCode('0104697951542541215Se<Bg\x1D'), isTrue,
          reason: 'пустой хвост после GS не должен ломать код');
    });

    test('decode возвращает null на мусоре', () {
      expect(CodeProcessor.decode('мусор'), isNull);
      expect(CodeProcessor.decode(''), isNull);
      expect(CodeProcessor.decode('01046979515425'), isNull);
    });
  });

  group('Дубликаты и ошибки', () {
    test('дубликаты считаются по полному коду с хвостом', () {
      final r = CodeProcessor.parse({
        2: '0104697951542015215HMm"G\x1D91EE12\x1D92AAA',
        3: '0104697951542015215HMm"G\x1D91EE12\x1D92AAA',
        4: '0104697951542015215HMm"G\x1D91EE12\x1D92BBB',
      });

      expect(r.codes.length, 2, reason: 'разные коды проверки — разные коды');
      expect(r.duplicatesInFile, 1);
    });

    test('пустая ячейка попадает в ошибки с номером строки', () {
      final r = CodeProcessor.parse({
        7: '',
        8: '0104697951542015215HMm"G\x1D91EE12',
      });

      expect(r.codes.length, 1);
      expect(r.errors.single, contains('Строка 7'));
      expect(r.errors.single, contains('пустая'));
    });

    test('разные структуры в одном файле отмечаются', () {
      final r = CodeProcessor.parse({
        2: '0104697951542015215HMm"G\x1D91EE12\x1D92AAA',
        3: '0104697951542503215tZah-\x1D933eFn',
      });

      expect(r.hasMixedStructures, isTrue);
      expect(r.structureSummary, {'01+21+91+92': 1, '01+21+93': 1});
    });
  });

  group('Справочник товаров', () {
    test('читается как раньше — правки его не затронули', () async {
      final r = await ExcelService.readProducts('test/fixtures/products.xlsx');

      expect(r.products, isNotEmpty);
      expect(r.products.where((p) => p.isHidden).length, 4);
    });
  });

}
