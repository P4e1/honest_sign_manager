import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/upload_provider.dart';
import '../services/database_service.dart';
import '../services/excel_service.dart';
import '../services/settings_service.dart';
import 'widgets.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final SettingsService _settings = context.read<SettingsService>();
  late final _tokenCtrl = TextEditingController(text: _settings.token);
  late final _batchCtrl =
      TextEditingController(text: _settings.batchSize.toString());

  bool _tokenVisible = false;
  bool _importing = false;
  String? _importResult;
  bool _importOk = true;

  @override
  void dispose() {
    _tokenCtrl.dispose();
    _batchCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveToken() async {
    final token = _tokenCtrl.text.trim();
    if (token.isEmpty) {
      showSnack(context, 'Токен не может быть пустым', error: true);
      return;
    }
    await _settings.setToken(token);
    if (mounted) showSnack(context, 'Токен сохранён');
  }

  Future<void> _saveBatch() async {
    final n = int.tryParse(_batchCtrl.text.trim());
    if (n == null || n < 1 || n > 100000) {
      showSnack(context, 'Размер пачки — число от 1 до 100000', error: true);
      return;
    }
    await _settings.setBatchSize(n);
    if (mounted) showSnack(context, 'Размер пачки: $n');
  }

  Future<void> _importProducts() async {
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: 'Справочник товаров (ID, наименование)',
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );
    final path = picked?.files.single.path;
    if (path == null || !mounted) return;

    setState(() {
      _importing = true;
      _importResult = null;
    });

    try {
      final result = await ExcelService.readProducts(path);
      if (result.products.isEmpty) {
        throw const FormatException('В файле не найдено ни одного товара');
      }
      if (!mounted) return;
      await context.read<DatabaseService>().replaceProducts(result.products);
      if (!mounted) return;
      await context.read<UploadProvider>().reloadProducts();

      final hidden = result.products.where((p) => p.isHidden).length;
      final warn = result.errors.isEmpty
          ? ''
          : '\nПропущено строк: ${result.errors.length}\n${result.errors.take(10).join('\n')}';
      _importOk = true;
      _importResult = 'Загружено товаров: ${result.products.length} '
          '(из них скрытых #удалено#/#дубликат#: $hidden)$warn';
    } catch (e) {
      _importOk = false;
      _importResult =
          'Ошибка импорта: ${e is FormatException ? e.message : e}';
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Widget _card(String title, List<Widget> children) => Card(
        margin: const EdgeInsets.only(bottom: 16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              ...children,
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final productsCount = context.watch<UploadProvider>().products.length;
    final dbPath = context.read<DatabaseService>().path;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Настройки', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 16),
        _card('Авторизация (Bearer-токен, общий для всех терминалов)', [
          TextField(
            controller: _tokenCtrl,
            obscureText: !_tokenVisible,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: 'Токен',
              prefixIcon: const Icon(Icons.key),
              suffixIcon: IconButton(
                tooltip: _tokenVisible ? 'Скрыть' : 'Показать',
                icon: Icon(
                    _tokenVisible ? Icons.visibility_off : Icons.visibility),
                onPressed: () =>
                    setState(() => _tokenVisible = !_tokenVisible),
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _saveToken,
            icon: const Icon(Icons.save),
            label: const Text('Сохранить токен'),
          ),
        ]),
        _card('Справочник товаров', [
          Text('Сейчас в справочнике: $productsCount'),
          const SizedBox(height: 4),
          const Text(
              'Файл .xlsx: столбец A — ID, столбец B — наименование, первая строка — заголовок. '
              'Импорт полностью заменяет текущий справочник.',
              style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: _importing ? null : _importProducts,
            icon: _importing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.upload_file),
            label: const Text('Импортировать из Excel'),
          ),
          if (_importResult != null) ...[
            const SizedBox(height: 12),
            ResultBanner(success: _importOk, message: _importResult!),
          ],
        ]),
        _card('Выгрузка', [
          SizedBox(
            width: 320,
            child: TextField(
              controller: _batchCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Кодов в одном запросе',
                prefixIcon: Icon(Icons.format_list_numbered),
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: _saveBatch,
            icon: const Icon(Icons.save),
            label: const Text('Сохранить'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () async {
              await _settings.clearRecentUrls();
              if (!context.mounted) return;
              await context.read<UploadProvider>().init();
              if (context.mounted) showSnack(context, 'Список адресов очищен');
            },
            icon: const Icon(Icons.history_toggle_off),
            label: const Text('Очистить список последних адресов'),
          ),
        ]),
        _card('О данных', [
          SelectableText('База истории: $dbPath'),
        ]),
      ],
    );
  }
}
