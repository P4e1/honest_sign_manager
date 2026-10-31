// Тесты логики без UI: запуск — `flutter test`.
import 'package:flutter_test/flutter_test.dart';

import 'package:honest_sign_manager/services/code_processor.dart';
import 'package:honest_sign_manager/utils/terminal_address.dart';

void main() {
  group('CodeProcessor', () {
    test('Base64 совпадает с примером из API', () {
      expect(CodeProcessor.toBase64('0104697951542541215Se<Bg'),
          'MDEwNDY5Nzk1MTU0MjU0MTIxNVNlPEJn');
    });

    test('Формат кода', () {
      expect(CodeProcessor.isValidCode('0104697951542541215Se<Bg'), isTrue);
      expect(CodeProcessor.isValidCode('КИ (код идентификации)'), isFalse);
      expect(CodeProcessor.isValidCode('01046979515425'), isFalse);
    });

    test('Дубликаты и ошибки в файле', () {
      final r = CodeProcessor.parse({
        2: '0104697951542541215Se<Bg',
        3: '0104697951542541215Se<Bg',
        4: 'мусор',
        5: '0104697951542541215cYMzf',
      });
      expect(r.codes.length, 2);
      expect(r.duplicatesInFile, 1);
      expect(r.errors.length, 1);
    });
  });

  group('TerminalAddress', () {
    test('Ключ терминала не зависит от /api и слэша', () {
      final a = TerminalAddress.tryParse('http://192.168.1.82:4001/api')!;
      final b = TerminalAddress.tryParse('http://192.168.1.82:4001/')!;
      final c = TerminalAddress.tryParse('192.168.1.82:4001')!;
      expect(a.key, '192.168.1.82:4001');
      expect(b.key, a.key);
      expect(c.key, a.key);
    });

    test('Путь /api сохраняется в URL запроса', () {
      final a = TerminalAddress.tryParse('http://192.168.1.82:4001/api')!;
      expect(a.endpoint('/v1/honest-sign/codes/bulk'),
          'http://192.168.1.82:4001/api/v1/honest-sign/codes/bulk');
    });

    test('Некорректный адрес', () {
      expect(TerminalAddress.tryParse(''), isNull);
      expect(TerminalAddress.tryParse('ftp://1.2.3.4'), isNull);
    });
  });
}
