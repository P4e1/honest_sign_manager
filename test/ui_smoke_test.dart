import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sign_manager/screens/widgets.dart';

void main() {
  testWidgets('ResultBanner рендерится', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: ResultBanner(success: false, message: 'Ошибка 500')),
    ));
    expect(find.text('Ошибка 500'), findsOneWidget);
  });
}
