import 'package:shared_preferences/shared_preferences.dart';

/// Локальные настройки приложения.
class SettingsService {
  static const _kToken = 'token';
  static const _kRecentUrls = 'recent_terminal_urls';
  static const _kBatchSize = 'batch_size';
  static const _kStorePath = 'store_path';

  static const defaultStorePath =
      r'\\192.168.2.11\obmen\Работа\HonestSignManager для весовых терминалов';
  static const maxRecentUrls = 10;
  static const defaultBatchSize = 1000;

  late final SharedPreferences _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // ─── Токен ───────────────────────────────────────────────────────────────────

  String get token => _prefs.getString(_kToken) ?? '';
  Future<void> setToken(String value) =>
      _prefs.setString(_kToken, value.trim());

  // ─── Последние адреса ────────────────────────────────────────────────────────

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

  // ─── Размер пачки ────────────────────────────────────────────────────────────

  int get batchSize => _prefs.getInt(_kBatchSize) ?? defaultBatchSize;
  Future<void> setBatchSize(int value) => _prefs.setInt(_kBatchSize, value);

  // ─── Путь к файловому серверу ────────────────────────────────────────────────

  String get storePath => _prefs.getString(_kStorePath) ?? defaultStorePath;
  Future<void> setStorePath(String value) =>
      _prefs.setString(_kStorePath, value.trim());
}
