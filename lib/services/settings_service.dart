import 'package:shared_preferences/shared_preferences.dart';

/// Локальные настройки: токен, последние адреса, размер пачки.
class SettingsService {
  static const _kToken = 'token';
  static const _kRecentUrls = 'recent_terminal_urls';
  static const _kBatchSize = 'batch_size';

  static const maxRecentUrls = 10;
  static const defaultBatchSize = 1000;

  late final SharedPreferences _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // Токен — один для всех терминалов.
  String get token => _prefs.getString(_kToken) ?? '';
  Future<void> setToken(String value) =>
      _prefs.setString(_kToken, value.trim());

  // Последние адреса терминалов (самый свежий — первый).
  List<String> get recentUrls => _prefs.getStringList(_kRecentUrls) ?? [];

  Future<void> addRecentUrl(String url) async {
    final list = recentUrls..remove(url);
    list.insert(0, url);
    if (list.length > maxRecentUrls) list.removeRange(maxRecentUrls, list.length);
    await _prefs.setStringList(_kRecentUrls, list);
  }

  Future<void> removeRecentUrl(String url) async {
    final list = recentUrls..remove(url);
    await _prefs.setStringList(_kRecentUrls, list);
  }

  Future<void> clearRecentUrls() => _prefs.remove(_kRecentUrls);

  // Максимум кодов в одном запросе.
  int get batchSize => _prefs.getInt(_kBatchSize) ?? defaultBatchSize;
  Future<void> setBatchSize(int value) => _prefs.setInt(_kBatchSize, value);
}
