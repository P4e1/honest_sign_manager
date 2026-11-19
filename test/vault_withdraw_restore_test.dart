// Пакеты platform_interface — транзитивные зависимости path_provider; нужны
// только чтобы подменить каталог данных в тесте.
// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sign_manager/models/marking_code.dart';
import 'package:honest_sign_manager/models/upload_record.dart';
import 'package:honest_sign_manager/models/vault.dart';
import 'package:honest_sign_manager/services/code_processor.dart';
import 'package:honest_sign_manager/services/database_service.dart';
import 'package:honest_sign_manager/services/settings_service.dart';
import 'package:honest_sign_manager/services/vault_service.dart';
import 'package:honest_sign_manager/utils/terminal_address.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

const _productId = 77;
const _gs = '\x1D';

String _code(int i) =>
    '0104697951542015215${i.toString().padLeft(5, '0')}${_gs}91EE12${_gs}92CHECK$i=';

String _b64(String raw) => base64Encode(utf8.encode(raw));

String _kiOf(String raw) => raw.split(_gs).first;

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final String dir;
  _FakePathProvider(this.dir);

  @override
  Future<String?> getApplicationSupportPath() async => dir;
}

class _FakeSettings extends SettingsService {
  final int batch;
  _FakeSettings({this.batch = 1000});

  @override
  Future<void> init() async {}

  @override
  String get token => 'test-token';

  @override
  String get storePath => '';

  @override
  int get batchSize => batch;
}

/// Поддельный терминал.
///
/// Свободные коды лежат списком, а не множеством: так видно, если один и тот
/// же код оказался загружен дважды. Напечатанные коды хранятся отдельно и
/// отдаются через историю печати. Терминал, как и настоящий, принимает любой
/// загружаемый код — именно поэтому возврат напечатанных кодов их «оживляет».
class FakeTerminal {
  final HttpServer _server;

  final List<String> free = [];
  final List<String> printedRaw = [];

  /// Напечатанные коды, которые ещё лежат на терминале (по КИ).
  final Set<String> printedPresent = {};

  int deleteCalls = 0;
  int uploadCalls = 0;
  final deletedKi = <String>[];

  bool failHistory = false;

  /// Номер POST-запроса загрузки, который вернёт 500 (с единицы).
  int? failUploadOnCall;

  /// Отдавать в истории только код идентификации, без хвоста.
  bool historyWithoutTail = false;

  /// Значение createdAtAfter из последнего запроса истории.
  String? lastHistoryCreatedAtAfter;

  FakeTerminal._(this._server) {
    _server.listen(_handle);
  }

  static Future<FakeTerminal> start() async =>
      FakeTerminal._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  String get url => 'http://127.0.0.1:${_server.port}/api';

  Future<void> _handle(HttpRequest request) async {
    final path = request.uri.path;
    final body = await utf8.decoder.bind(request).join();

    Future<void> reply(int status, Object? json) async {
      request.response
        ..statusCode = status
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(json));
      await request.response.close();
    }

    if (request.method == 'GET' && path.endsWith('/labeling-history')) {
      lastHistoryCreatedAtAfter =
          request.uri.queryParameters['createdAtAfter'];
      if (failHistory) return reply(500, {'error': 'history down'});
      final skip = int.parse(request.uri.queryParameters['skip'] ?? '0');
      final take = int.parse(request.uri.queryParameters['take'] ?? '1000');
      final page = printedRaw.skip(skip).take(take).toList();
      return reply(200, [
        for (var i = 0; i < page.length; i++)
          {
            'id': 'h${skip + i}',
            'honestSignCode':
                _b64(historyWithoutTail ? _kiOf(page[i]) : page[i]),
            'honestSignCodeMeta': {'productId': _productId},
            'exportStatus': 'Ready',
          },
      ]);
    }

    if (request.method == 'DELETE' && path.endsWith('/codes/delete/bulk')) {
      deleteCalls++;
      final codes = (jsonDecode(body)['codes'] as List).cast<String>();
      for (final b64 in codes) {
        final ki = _kiOf(utf8.decode(base64Decode(b64)));
        deletedKi.add(ki);
        final index = free.indexOf(ki);
        if (index >= 0) free.removeAt(index);
        printedPresent.remove(ki);
      }
      return reply(200, {});
    }

    if (request.method == 'POST' && path.endsWith('/codes/bulk')) {
      uploadCalls++;
      if (failUploadOnCall == uploadCalls) return reply(500, {'error': 'x'});
      final bulk = (jsonDecode(body)['bulk'] as List).cast<Map>();
      for (final item in bulk) {
        final raw = utf8.decode(base64Decode(item['code'] as String));
        free.add(_kiOf(raw));
      }
      return reply(201, {});
    }

    return reply(404, {'error': 'unknown $path'});
  }

  Future<void> stop() => _server.close(force: true);

  /// Коды, которые одновременно напечатаны и свободны, плюс повторы среди
  /// свободных. Любое значение больше нуля — это дубликат маркировки.
  int get duplicates {
    final printedKi = printedRaw.map(_kiOf).toSet();
    final aliveAgain = free.where(printedKi.contains).length;
    final repeated = free.length - free.toSet().length;
    return aliveAgain + repeated;
  }
}

void main() {
  late Directory tmp;
  late DatabaseService db;
  late FakeTerminal terminal;
  late TerminalAddress address;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('vault_test_');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    db = DatabaseService();
    await db.init();
    terminal = await FakeTerminal.start();
    address = TerminalAddress.tryParse(terminal.url)!;
  });

  tearDown(() async {
    await terminal.stop();
    await db.close();
  });

  /// В приложении числятся [total] кодов, из них [printed] первых уже
  /// напечатаны на терминале. На терминале свободны остальные.
  Future<List<String>> seed({
    required int total,
    required int printed,
    String storeId = '20261110-100000-aaaa',
  }) async {
    final raws = [for (var i = 0; i < total; i++) _code(i)];

    await db.saveUpload(
      UploadRecord(
        storeId: storeId,
        terminalUrl: terminal.url,
        terminalKey: address.key,
        productId: _productId,
        productName: 'Колбаса',
        fileName: 'codes.xlsx',
        codesCount: total,
        httpStatus: 201,
        status: RecordStatus.loaded,
        uploadedAt: DateTime(2026, 11, 10, 10),
      ),
      [
        for (final raw in raws)
          MarkingCode(
            recordId: 0,
            raw: raw,
            base64: _b64(raw),
            terminalKey: address.key,
          ),
      ],
    );

    terminal.printedRaw.addAll(raws.take(printed));
    terminal.printedPresent.addAll(raws.take(printed).map(_kiOf));
    terminal.free.addAll(raws.skip(printed).map(_kiOf));
    return raws;
  }

  test('сценарий из отчёта: 1000 в истории, 20 напечатаны — возвращается 980',
      () async {
    await seed(total: 1000, printed: 20);
    expect(terminal.free.length, 980);

    final service = VaultService(db, _FakeSettings());

    final out = await service.withdraw(terminal: address);
    expect(out.ok, isTrue, reason: out.message);
    expect(terminal.free, isEmpty, reason: 'свободные коды сняты');
    expect(terminal.deletedKi.length, 1000,
        reason: 'напечатанные коды тоже снимаются, иначе товары не изменить');
    expect(terminal.printedPresent, isEmpty);
    expect(out.message, contains('20'), reason: 'пользователь видит, что 20 не тронуты');

    final vault = await service.loadVault(out.withdrawal!);
    expect(vault!.codes.length, 980);

    final back = await service.restore(withdrawal: out.withdrawal!);
    expect(back.ok, isTrue, reason: back.message);

    expect(terminal.free.length, 980,
        reason: 'на терминале должно быть ровно столько же, сколько было');
    expect(terminal.duplicates, 0,
        reason: 'ни один напечатанный код не должен ожить');
  });

  test('история печати без хвоста кода тоже сопоставляется по КИ', () async {
    await seed(total: 100, printed: 10);
    terminal.historyWithoutTail = true;

    final service = VaultService(db, _FakeSettings());
    final out = await service.withdraw(terminal: address);

    expect(out.ok, isTrue, reason: out.message);
    expect((await service.loadVault(out.withdrawal!))!.codes.length, 90);
  });

  test('история печати запрашивается не раньше первой выгрузки', () async {
    await seed(total: 50, printed: 5);

    final service = VaultService(db, _FakeSettings());
    final out = await service.withdraw(terminal: address);

    expect(out.ok, isTrue, reason: out.message);
    expect(terminal.lastHistoryCreatedAtAfter, isNotNull,
        reason: 'без границы терминал отдаёт всю историю и зависает');
    final since = DateTime.parse(terminal.lastHistoryCreatedAtAfter!);
    expect(since.isBefore(DateTime(2026, 11, 10, 10)), isTrue);
    expect(since.isAfter(DateTime(2026, 11, 8)), isTrue);
  });

  test('статус изъятия показывает время каждой страницы истории', () async {
    await seed(total: 50, printed: 5);
    final statuses = <String>[];

    final service = VaultService(db, _FakeSettings());
    final out = await service.withdraw(
      terminal: address,
      onStatus: statuses.add,
    );

    expect(out.ok, isTrue, reason: out.message);
    expect(statuses.any((s) => s.contains('стр. 1') && s.endsWith('мс')),
        isTrue, reason: statuses.join('\n'));
    expect(statuses.any((s) => s.startsWith('Из базы прочитано кодов: 50')),
        isTrue, reason: statuses.join('\n'));
  });

  test('история печати недоступна — изъятие не начинается', () async {
    await seed(total: 50, printed: 5);
    terminal.failHistory = true;

    final service = VaultService(db, _FakeSettings());
    final out = await service.withdraw(terminal: address);

    expect(out.ok, isFalse);
    expect(out.message, contains('ни один код не тронут'));
    expect(terminal.deleteCalls, 0, reason: 'ничего не должно быть удалено');
    expect(terminal.free.length, 45);
    expect(await service.listWithdrawals(), isEmpty,
        reason: 'файл изъятия не создаётся');
  });

  test('старый файл изъятия с напечатанными кодами не оживляет их', () async {
    // Файл, созданный до исправления: в нём все 1000 кодов, в том числе
    // 20 уже напечатанных.
    final raws = await seed(total: 1000, printed: 20);
    final service = VaultService(db, _FakeSettings());

    final legacy = VaultFile(
      withdrawalId: '20261111-090000-beef',
      terminalKey: address.key,
      terminalUrl: terminal.url,
      createdAt: DateTime(2026, 11, 11, 9),
      author: 'test',
      machine: 'pc',
      reason: null,
      codes: [
        for (final raw in raws)
          VaultCode(
            raw: raw,
            base64: _b64(raw),
            productId: _productId,
            productName: 'Колбаса',
            storeId: '20261110-100000-aaaa',
            uploadedAt: '',
          ),
      ],
    );
    final vaultDir = Directory('${tmp.path}/vault')..createSync(recursive: true);
    final file = File('${vaultDir.path}/${legacy.withdrawalId}.json')
      ..writeAsStringSync(jsonEncode(legacy.toJson()));

    terminal.free.clear(); // как после изъятия
    final withdrawal = Withdrawal.fromJson(legacy.toJson(), filePath: file.path);

    final back = await service.restore(withdrawal: withdrawal);

    expect(back.ok, isTrue, reason: back.message);
    expect(terminal.free.length, 980);
    expect(terminal.duplicates, 0);
    expect(back.message, contains('уже напечатаны'));
  });

  test('обрыв возврата и повтор не загружают принятые коды второй раз',
      () async {
    await seed(total: 250, printed: 0);
    final service = VaultService(db, _FakeSettings(batch: 100));

    final out = await service.withdraw(terminal: address);
    expect(out.ok, isTrue, reason: out.message);
    expect(terminal.free, isEmpty);

    // Первая пачка проходит, вторая падает.
    terminal.failUploadOnCall = 2;
    final failed = await service.restore(withdrawal: out.withdrawal!);
    expect(failed.ok, isFalse);
    expect(terminal.free.length, 100);

    // Повтор: терминал снова доступен.
    terminal.failUploadOnCall = null;
    final retried = await service.restore(withdrawal: out.withdrawal!);

    expect(retried.ok, isTrue, reason: retried.message);
    expect(terminal.free.length, 250,
        reason: 'ровно 250: первые 100 повторно не загружаются');
    expect(terminal.duplicates, 0);
  });

  test('повтор одного кода в истории выгрузок не попадает в файл дважды',
      () async {
    final raws = await seed(total: 30, printed: 0);

    // Вторая выгрузка того же файла: те же коды в другой записи.
    await db.saveUpload(
      UploadRecord(
        storeId: '20261110-110000-bbbb',
        terminalUrl: terminal.url,
        terminalKey: address.key,
        productId: _productId,
        productName: 'Колбаса',
        fileName: 'codes.xlsx',
        codesCount: 5,
        httpStatus: 201,
        status: RecordStatus.loaded,
        uploadedAt: DateTime(2026, 11, 10, 11),
      ),
      [
        for (final raw in raws.take(5))
          MarkingCode(
            recordId: 0,
            raw: raw,
            base64: _b64(raw),
            terminalKey: address.key,
          ),
      ],
    );

    final service = VaultService(db, _FakeSettings());
    final out = await service.withdraw(terminal: address);

    expect(out.ok, isTrue, reason: out.message);
    final vault = (await service.loadVault(out.withdrawal!))!;
    expect(vault.codes.length, 30);
    expect(
      vault.codes.map((c) => CodeProcessor.kiOf(c.raw)).toSet().length,
      30,
    );
  });

  test('если все коды напечатаны — они удаляются, файл изъятия не создаётся',
      () async {
    await seed(total: 20, printed: 20);

    final service = VaultService(db, _FakeSettings());
    final out = await service.withdraw(terminal: address);

    expect(out.ok, isTrue, reason: out.message);
    expect(terminal.printedPresent, isEmpty);
    expect(await service.listWithdrawals(), isEmpty);
  });

  test('напечатанные коды, оставшиеся после прошлого изъятия, удаляются',
      () async {
    await seed(total: 100, printed: 10);
    await db.markWithdrawn({'20261110-100000-aaaa'});
    terminal.free.clear();

    final service = VaultService(db, _FakeSettings());
    final out = await service.withdraw(terminal: address);

    expect(out.ok, isTrue, reason: out.message);
    expect(terminal.printedPresent, isEmpty,
        reason: 'иначе терминал не даст изменить товары');
    expect(terminal.deletedKi.length, 10);
    expect(await service.listWithdrawals(), isEmpty);
  });

  test('в следующем цикле удалённые напечатанные коды не удаляются снова',
      () async {
    await seed(total: 100, printed: 10);
    final service = VaultService(db, _FakeSettings());

    final first = await service.withdraw(terminal: address);
    expect(first.ok, isTrue, reason: first.message);
    final back = await service.restore(withdrawal: first.withdrawal!);
    expect(back.ok, isTrue, reason: back.message);
    expect(terminal.free.length, 90);

    terminal.deletedKi.clear();
    final second = await service.withdraw(terminal: address);

    expect(second.ok, isTrue, reason: second.message);
    expect(terminal.deletedKi.length, 90);
    expect(terminal.duplicates, 0);
  });
}
