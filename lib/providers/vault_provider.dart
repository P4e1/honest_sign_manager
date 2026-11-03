import 'package:flutter/foundation.dart';

import '../models/vault.dart';
import '../services/database_service.dart';
import '../services/settings_service.dart';
import '../services/vault_service.dart';
import '../utils/terminal_address.dart';

/// Управление изъятием кодов с терминала и возвратом обратно.
class VaultProvider extends ChangeNotifier {
  final DatabaseService _db;
  final SettingsService _settings;

  VaultProvider(this._db, this._settings);

  List<Withdrawal> withdrawals = [];
  bool isLoading = false;
  bool isBusy = false;
  String? progressText;
  String? error;
  String? successMessage;

  /// Изъятие, выбранное для возврата.
  Withdrawal? selected;

  VaultService get _service => VaultService(_db, _settings);

  // ─── Список ─────────────────────────────────────────────────────────────────

  Future<void> load([String? terminalKey]) async {
    isLoading = true;
    notifyListeners();
    try {
      final all = await _service.listWithdrawals();
      withdrawals = terminalKey == null || terminalKey.isEmpty
          ? all
          : all.where((w) => w.terminalKey == terminalKey).toList();
      error = null;
    } catch (e) {
      error = 'Не удалось прочитать список изъятий: $e';
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  void select(Withdrawal? value) {
    selected = value;
    notifyListeners();
  }

  void clearMessages() {
    error = null;
    successMessage = null;
    notifyListeners();
  }

  // ─── Изъятие ────────────────────────────────────────────────────────────────

  Future<VaultResult?> withdraw({
    required String terminalUrl,
    String? reason,
  }) async {
    final terminal = TerminalAddress.tryParse(terminalUrl);
    if (terminal == null) {
      error = 'Некорректный адрес терминала';
      notifyListeners();
      return null;
    }

    isBusy = true;
    error = null;
    successMessage = null;
    progressText = 'Подготовка…';
    notifyListeners();

    try {
      final result = await _service.withdraw(
        terminal: terminal,
        reason: reason,
        onProgress: (done, total) {
          progressText = 'Удаление кодов: $done из $total';
          notifyListeners();
        },
      );

      if (result.ok) {
        successMessage = result.message;
      } else {
        error = result.message;
      }
      await load(terminal.key);
      return result;
    } catch (e) {
      error = 'Ошибка при изъятии: $e';
      return null;
    } finally {
      isBusy = false;
      progressText = null;
      notifyListeners();
    }
  }

  // ─── Возврат ────────────────────────────────────────────────────────────────

  Future<VaultResult?> restore(Withdrawal withdrawal) async {
    isBusy = true;
    error = null;
    successMessage = null;
    progressText = 'Возврат кодов…';
    notifyListeners();

    try {
      final result = await _service.restore(
        withdrawal: withdrawal,
        onProgress: (done, total) {
          progressText = 'Возврат кодов: $done из $total';
          notifyListeners();
        },
      );

      if (result.ok) {
        successMessage = result.message;
        selected = null;
      } else {
        error = result.message;
      }
      await load();
      return result;
    } catch (e) {
      error = 'Ошибка при возврате: $e';
      return null;
    } finally {
      isBusy = false;
      progressText = null;
      notifyListeners();
    }
  }
}
