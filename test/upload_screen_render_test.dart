import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:honest_sign_manager/providers/history_provider.dart';
import 'package:honest_sign_manager/providers/stock_provider.dart';
import 'package:honest_sign_manager/providers/upload_provider.dart';
import 'package:honest_sign_manager/providers/vault_provider.dart';
import 'package:honest_sign_manager/screens/upload_screen.dart';
import 'package:honest_sign_manager/services/database_service.dart';
import 'package:honest_sign_manager/services/settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    // path_provider в тестах недоступен — подменяем канал.
    final tempDir = Directory.systemTemp.createTempSync('app_support');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tempDir.path,
    );
  });

  testWidgets('название товара из F2 видно на экране выгрузки',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final db = DatabaseService();
    await db.init();
    final settings = SettingsService();
    await settings.init();

    final upload = UploadProvider(db, settings);
    await upload.init();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<DatabaseService>.value(value: db),
          Provider<SettingsService>.value(value: settings),
          ChangeNotifierProvider<UploadProvider>.value(value: upload),
          ChangeNotifierProvider(create: (_) => HistoryProvider(db, settings)),
          ChangeNotifierProvider(create: (_) => StockProvider(db, settings)),
          ChangeNotifierProvider(create: (_) => VaultProvider(db, settings)),
        ],
        child: const MaterialApp(home: Scaffold(body: UploadScreen())),
      ),
    );
    await tester.pumpAndSettle();

    // Загружаем настоящий файл 1С
    await upload.loadFile('test/fixtures/kolbaski.xlsx', 'kolbaski.xlsx');
    await tester.pumpAndSettle();

    // Плашка должна быть на экране
    expect(find.textContaining('Колбаски из печи'), findsWidgets);
    expect(find.textContaining('В файле:'), findsOneWidget);

    // Кнопка сброса на месте
    expect(find.text('Сбросить файл'), findsOneWidget);
  });
}
