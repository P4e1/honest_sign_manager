import 'package:dio/dio.dart';

import '../utils/terminal_address.dart';

/// Результат запроса к терминалу.
class ApiResult {
  final bool ok;

  /// HTTP-код; null — ответа не было (нет связи, таймаут).
  final int? statusCode;
  final dynamic data;
  final String? error;

  const ApiResult({
    required this.ok,
    this.statusCode,
    this.data,
    this.error,
  });
}

/// HTTP-клиент терминала.
class TerminalApi {
  static const uploadPath = '/v1/honest-sign/codes/bulk';
  static const deletePath = '/v1/honest-sign/codes/delete/bulk';

  final Dio _dio;

  TerminalApi(String token)
      : _dio = Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 10),
            sendTimeout: const Duration(seconds: 60),
            receiveTimeout: const Duration(seconds: 120),
            contentType: Headers.jsonContentType,
            responseType: ResponseType.json,
            headers: {'Authorization': 'Bearer ${token.trim()}'},
            // Любой HTTP-код обрабатываем сами, без исключений.
            validateStatus: (_) => true,
          ),
        );

  /// POST /v1/honest-sign/codes/bulk → 201/200 при успехе.
  Future<ApiResult> uploadCodes({
    required TerminalAddress terminal,
    required List<String> base64Codes,
    required int productId,
  }) {
    final body = {
      'bulk': [
        for (final code in base64Codes) {'code': code, 'productId': productId},
      ],
    };
    return _send(() => _dio.post(terminal.endpoint(uploadPath), data: body));
  }

  /// DELETE /v1/honest-sign/codes/delete/bulk → 200 при успехе.
  Future<ApiResult> deleteCodes({
    required TerminalAddress terminal,
    required List<String> base64Codes,
  }) {
    final body = {'codes': base64Codes};
    return _send(() => _dio.delete(terminal.endpoint(deletePath), data: body));
  }

  Future<ApiResult> _send(Future<Response<dynamic>> Function() request) async {
    try {
      final response = await request();
      final code = response.statusCode ?? 0;
      if (code == 200 || code == 201) {
        return ApiResult(ok: true, statusCode: code, data: response.data);
      }
      return ApiResult(
        ok: false,
        statusCode: code,
        data: response.data,
        error: _describeError(code, response.data),
      );
    } on DioException catch (e) {
      return ApiResult(ok: false, error: _describeDioError(e));
    } catch (e) {
      return ApiResult(ok: false, error: 'Непредвиденная ошибка: $e');
    }
  }

  /// Разбор ошибки NestJS:
  /// { statusCode, timestamp, path, error: { name, message, stack } }
  static String _describeError(int code, dynamic data) {
    String? message;
    String? name;

    if (data is Map) {
      final error = data['error'];
      if (error is Map) {
        message = _stringify(error['message']);
        name = error['name']?.toString();
      } else if (error is String && data['message'] == null) {
        message = error;
      }
      message ??= _stringify(data['message']);
    } else if (data is String && data.trim().isNotEmpty) {
      message = data.trim();
    }

    final hint = switch (code) {
      401 => 'Неверный или просроченный токен авторизации',
      403 => 'Доступ запрещён',
      404 => 'Метод не найден — проверьте адрес (нужен ли /api)',
      _ => null,
    };

    final parts = <String>[
      if (hint != null) hint,
      if (message != null && message.isNotEmpty)
        name != null ? '$name: $message' : message,
    ];
    return parts.isEmpty ? 'Ошибка HTTP $code' : parts.join('\n');
  }

  static String? _stringify(dynamic value) {
    if (value == null) return null;
    if (value is List) return value.join('; ');
    return value.toString();
  }

  static String _describeDioError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
        return 'Терминал не отвечает (таймаут подключения). Проверьте IP и порт.';
      case DioExceptionType.sendTimeout:
        return 'Таймаут отправки данных.';
      case DioExceptionType.receiveTimeout:
        return 'Терминал слишком долго обрабатывает запрос (таймаут ответа).';
      case DioExceptionType.connectionError:
        return 'Не удалось подключиться к терминалу. Проверьте IP, порт и сеть.';
      case DioExceptionType.badCertificate:
        return 'Ошибка сертификата HTTPS.';
      case DioExceptionType.cancel:
        return 'Запрос отменён.';
      default:
        return 'Ошибка сети: ${e.message ?? e.error}';
    }
  }
}
