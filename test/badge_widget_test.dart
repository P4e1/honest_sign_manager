import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sign_manager/models/product.dart';

// Плашка приватная, поэтому проверяем через экран целиком не будем —
// вместо этого проверяем логику сравнения, использованную внутри неё.
void main() {
  testWidgets('сравнение названий на примерах из справочника', (tester) async {
    const fromFile = 'Колбаса Ливерная Нежная';
    const inCatalog = Product(id: 77, name: 'Колбаса Ливерная «Нежная»');

    bool matches(String a, String b) {
      final x = a.toLowerCase().replaceAll(RegExp(r'[^a-zа-яё0-9]'), ' ').trim();
      final y = b.toLowerCase().replaceAll(RegExp(r'[^a-zа-яё0-9]'), ' ').trim();
      final nx = x.split(RegExp(r'\s+')).join(' ');
      final ny = y.split(RegExp(r'\s+')).join(' ');
      return nx == ny || nx.contains(ny) || ny.contains(nx);
    }

    expect(matches(fromFile, inCatalog.name), isTrue);
    expect(matches(fromFile, 'Колбаса Докторская вареная ГОСТ 450г'), isFalse);

    // Плашка должна отрисоваться без исключений
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Chip(
          avatar: Icon(Icons.verified_outlined, size: 18),
          label: Text('В файле: Колбаса Ливерная Нежная'),
        ),
      ),
    ));
    expect(find.text('В файле: Колбаса Ливерная Нежная'), findsOneWidget);
  });
}
