import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sign_manager/providers/upload_provider.dart';
import 'package:honest_sign_manager/services/database_service.dart';
import 'package:honest_sign_manager/services/settings_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('сквозной путь: файл → парсер → провайдер', () async {
    final dir = Directory.systemTemp.createTempSync('upload_test');
    final db = DatabaseService();
    // Подменяем каталог приложения, чтобы не писать в реальный профиль.
    TestWidgetsFlutterBinding.ensureInitialized();
    await db.init();

    final settings = SettingsService();
    await settings.init();

    final provider = UploadProvider(db, settings);

    final error =
        await provider.loadFile('test/fixtures/kolbaski.xlsx', 'kolbaski.xlsx');

    expect(error, isNull, reason: 'файл должен читаться');
    expect(provider.parsed, isNotNull);
    expect(provider.parsed!.codes.length, 500);

    // Главная проверка: название доходит до провайдера, а значит и до UI.
    expect(provider.parsed!.productNameFromFile, 'Колбаски из печи');
    expect(provider.parsed!.hasProductInfo, isTrue);

    dir.deleteSync(recursive: true);
  });
}
