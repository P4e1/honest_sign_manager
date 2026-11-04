import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:honest_sign_manager/models/product.dart';
import 'package:honest_sign_manager/providers/upload_provider.dart';
import 'package:honest_sign_manager/screens/upload_screen.dart';
import 'package:honest_sign_manager/services/database_service.dart';
import 'package:honest_sign_manager/services/settings_service.dart';

/// Заглушки: экран не должен лезть в настоящую БД и настройки.
class _FakeDb extends DatabaseService {
  final List<Product> _products;
  _FakeDb(this._products);

  @override
  Future<List<Product>> getProducts() async => _products;

  @override
  Future<void> replaceProducts(List<Product> products) async {}
}

class _FakeSettings extends SettingsService {
  @override
  Future<void> init() async {}

  @override
  String get token => 'test-token';

  @override
  List<String> get recentUrls => const [];

  @override
  String get storePath => '';

  @override
  int get batchSize => 1000;

  @override
  Future<void> addRecentUrl(String url) async {}
}

/// Отдаёт несколько кадров вручную.
///
/// `pumpAndSettle` здесь нельзя: у Autocomplete и DropTarget есть
/// незатухающие анимации, и ожидание «пока всё успокоится» не кончается.
Future<void> _frames(WidgetTester tester, [int count = 4]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('Плашка с товаром из F2 появляется после загрузки файла',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final db = _FakeDb(const [
      Product(id: 83, name: 'Колбаски из печи'),
      Product(id: 77, name: 'Колбаса Ливерная «Нежная»'),
    ]);
    final provider = UploadProvider(db, _FakeSettings());
    await provider.reloadProducts();

    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<UploadProvider>.value(
          value: provider,
          child: const Scaffold(body: UploadScreen()),
        ),
      ),
    );
    await _frames(tester);

    expect(find.textContaining('В файле:'), findsNothing);

    // Чтение файла — настоящий ввод-вывод. В testWidgets время заморожено,
    // поэтому такой await выполняется только внутри runAsync,
    // иначе тест зависает навсегда.
    final error = await tester.runAsync(
      () => provider.loadFile('test/fixtures/kolbaski.xlsx', 'kolbaski.xlsx'),
    );
    expect(error, isNull, reason: 'Файл должен читаться');

    await _frames(tester);

    expect(find.textContaining('В файле:'), findsOneWidget,
        reason: 'Плашка с наименованием из F2 не отрисовалась');
    expect(find.textContaining('Колбаски из печи'), findsWidgets);
    expect(find.text('Сбросить файл'), findsOneWidget);

    // Товар подставился автоматически по названию из файла
    expect(provider.selectedProduct?.id, 83,
        reason: 'Товар не подставился по названию из файла');
  });

  test('Товар подставляется, когда он есть в справочнике', () async {
    final db = _FakeDb(const [Product(id: 83, name: 'Колбаски из печи')]);
    final provider = UploadProvider(db, _FakeSettings());
    await provider.reloadProducts();

    final error =
        await provider.loadFile('test/fixtures/kolbaski.xlsx', 'x.xlsx');
    expect(error, isNull);
    expect(provider.selectedProduct, isNotNull);
    expect(provider.productAutoSelected, isTrue);

    // Расхождения между файлом и выбором быть не должно
    expect(provider.checkSelectedProductAgainstFile, isNull);
  });

  test('Без товара в справочнике плашка всё равно покажет название', () async {
    final db = _FakeDb(const [Product(id: 1, name: 'Совсем другой товар')]);
    final provider = UploadProvider(db, _FakeSettings());
    await provider.reloadProducts();

    await provider.loadFile('test/fixtures/kolbaski.xlsx', 'x.xlsx');

    expect(provider.selectedProduct, isNull);
    expect(provider.parsed?.hasProductInfo, isTrue);
    expect(provider.parsed?.productNameFromFile, 'Колбаски из печи');
  });

  test('Файл существует для теста', () {
    expect(File('test/fixtures/kolbaski.xlsx').existsSync(), isTrue);
  });
}
