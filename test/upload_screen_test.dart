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

void main() {
  testWidgets('Плашка с товаром из F2 появляется после загрузки файла',
      (tester) async {
    final db = _FakeDb(const [
      Product(id: 83, name: 'Колбаски из печи'),
      Product(id: 77, name: 'Колбаса Ливерная «Нежная»'),
    ]);
    final settings = _FakeSettings();
    final provider = UploadProvider(db, settings);
    await provider.reloadProducts();

    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<UploadProvider>.value(
          value: provider,
          child: const Scaffold(body: UploadScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // До загрузки файла плашки нет
    expect(find.textContaining('В файле:'), findsNothing);

    // Загружаем настоящий файл «Колбаски из печи»
    await provider.loadFile('test/fixtures/kolbaski.xlsx', 'kolbaski.xlsx');
    await tester.pumpAndSettle();

    // Плашка должна быть на экране
    expect(find.textContaining('В файле:'), findsOneWidget,
        reason: 'Плашка с наименованием из F2 не отрисовалась');
    expect(find.textContaining('Колбаски из печи'), findsWidgets);

    // И товар должен подставиться автоматически
    expect(provider.selectedProduct?.id, 83,
        reason: 'Товар не подставился по названию из файла');

    // ignore: avoid_print
    print('F2 = ${provider.parsed?.productNameFromFile}');
    // ignore: avoid_print
    print('выбран товар: ${provider.selectedProduct?.label}');
  });

  testWidgets('Если товар в справочнике есть — выбор подставляется',
      (tester) async {
    final db = _FakeDb(const [Product(id: 83, name: 'Колбаски из печи')]);
    final provider = UploadProvider(db, _FakeSettings());
    await provider.reloadProducts();

    final error = await provider.loadFile('test/fixtures/kolbaski.xlsx', 'x.xlsx');
    expect(error, isNull);
    expect(provider.selectedProduct, isNotNull);
    expect(provider.productAutoSelected, isTrue);

    // Расхождения быть не должно
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
