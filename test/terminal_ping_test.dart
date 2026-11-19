import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:honest_sign_manager/services/terminal_api.dart';
import 'package:honest_sign_manager/utils/terminal_address.dart';

void main() {
  test('терминал, который отвечает HTTP, считается в сети', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((r) async {
      r.response.statusCode = 404;
      await r.response.close();
    });
    addTearDown(() => server.close(force: true));

    final address = TerminalAddress.tryParse(
        'http://127.0.0.1:${server.port}/api')!;
    final res = await TerminalApi.ping(address);

    expect(res.ok, isTrue);
    expect(res.statusCode, 404);
  });

  test('порт без ответа — терминал не в сети', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final port = server.port;
    await server.close(force: true);

    final address = TerminalAddress.tryParse('http://127.0.0.1:$port/api')!;
    final res = await TerminalApi.ping(address);

    expect(res.ok, isFalse);
    expect(res.error, isNotNull);
  });
}
