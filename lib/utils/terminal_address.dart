/// Разбор и нормализация адреса терминала.
///
/// Примеры ввода:
///   http://192.168.1.82:4001/api
///   http://192.168.1.82:4001
///   192.168.1.82:4001
class TerminalAddress {
  /// Базовый адрес для запросов, без завершающего «/».
  final String baseUrl;

  /// Ключ терминала «IP:порт» — по нему проверяются дубликаты.
  final String key;

  const TerminalAddress._(this.baseUrl, this.key);

  /// Возвращает null, если адрес некорректен.
  static TerminalAddress? tryParse(String input) {
    var text = input.trim();
    if (text.isEmpty) return null;
    if (!text.contains('://')) text = 'http://$text';
    while (text.endsWith('/')) {
      text = text.substring(0, text.length - 1);
    }

    final uri = Uri.tryParse(text);
    if (uri == null) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    if (uri.host.isEmpty) return null;

    final port = uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80);
    return TerminalAddress._(text, '${uri.host}:$port');
  }

  /// Полный URL метода: базовый адрес (включая /api, если указан) + путь.
  String endpoint(String path) => '$baseUrl$path';
}
