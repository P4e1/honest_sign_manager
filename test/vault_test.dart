import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sign_manager/models/vault.dart';

void main() {
  group('VaultFile', () {
    test('сериализация и чтение без потерь', () {
      final original = VaultFile(
        withdrawalId: '20261102-120000-abcd',
        terminalKey: '192.168.1.82:4001',
        terminalUrl: 'http://192.168.1.82:4001/api',
        createdAt: DateTime(2026, 11, 2, 12, 0, 0),
        author: 'pchelincev',
        machine: 'PC-01',
        reason: 'правка товаров',
        codes: [
          for (var i = 0; i < 3; i++)
            VaultCode(
              raw: '0104697951542541215Se<B$i',
              base64: base64Encode(
                  utf8.encode('0104697951542541215Se<B$i')),
              productId: 77,
              productName: 'Колбаса Ливерная «Нежная»',
              storeId: '20261031-102400-000$i',
              uploadedAt: '2026-10-31T10:24:00.777607',
            ),
        ],
      );

      final json = jsonDecode(jsonEncode(original.toJson()));
      final restored =
          VaultFile.fromJson(json as Map<String, dynamic>);

      expect(restored.withdrawalId, original.withdrawalId);
      expect(restored.codes.length, 3);
      expect(restored.codes.first.raw, '0104697951542541215Se<B0');
      expect(restored.codes.first.productId, 77);
      expect(restored.reason, 'правка товаров');
    });

    test('кириллица и спецсимволы в названии товара не ломаются', () {
      final file = VaultFile(
        withdrawalId: 'x',
        terminalKey: 'k',
        terminalUrl: 'u',
        createdAt: DateTime(2026),
        author: '',
        machine: '',
        reason: null,
        codes: [
          const VaultCode(
            raw: 'r',
            base64: 'b',
            productId: 1,
            productName: 'Сало «Пьяное» & Ко',
            storeId: 's',
            uploadedAt: '',
          ),
        ],
      );
      final back = VaultFile.fromJson(
          jsonDecode(jsonEncode(file.toJson())) as Map<String, dynamic>);
      expect(back.codes.single.productName, 'Сало «Пьяное» & Ко');
    });
  });

  group('Withdrawal', () {
    test('отметка о возврате сохраняется', () {
      final w = Withdrawal(
        withdrawalId: '20261102-120000-abcd',
        terminalKey: '192.168.1.82:4001',
        terminalUrl: 'http://192.168.1.82:4001',
        filePath: '/tmp/x.json',
        codesCount: 1500,
        createdAt: DateTime(2026, 11, 2, 12),
        author: 'pchelincev',
        reason: 'правка',
      );

      expect(w.isRestored, isFalse);
      final restored = w.copyWith(restoredAt: DateTime(2026, 11, 2, 13));
      expect(restored.isRestored, isTrue);
      expect(restored.codesCount, 1500);
      expect(restored.reason, 'правка');
    });
  });

  test('файл изъятия пишется и читается с диска', () async {
    final dir = Directory.systemTemp.createTempSync('vault_test');
    final file = File('${dir.path}/x.json');

    final vault = VaultFile(
      withdrawalId: '20261102-120000-abcd',
      terminalKey: '192.168.1.82:4001',
      terminalUrl: 'http://192.168.1.82:4001/api',
      createdAt: DateTime(2026, 11, 2, 12),
      author: 'pchelincev',
      machine: 'PC-01',
      reason: null,
      codes: [
        for (var i = 0; i < 500; i++)
          VaultCode(
            raw: '0104697951542541215${i.toString().padLeft(4, '0')}',
            base64: 'B64-$i',
            productId: 77,
            productName: 'Товар',
            storeId: 'rec-$i',
            uploadedAt: '2026-10-31T10:24:00',
          ),
      ],
    );

    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(vault.toJson()),
      encoding: utf8,
      flush: true,
    );

    expect(await file.exists(), isTrue);
    expect(await file.length(), greaterThan(1000));

    final back = VaultFile.fromJson(
        jsonDecode(await file.readAsString(encoding: utf8))
            as Map<String, dynamic>);
    expect(back.codes.length, 500);
    expect(back.codes.last.base64, 'B64-499');

    dir.deleteSync(recursive: true);
  });
}
