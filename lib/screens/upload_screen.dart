import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/product.dart';
import '../providers/history_provider.dart';
import '../providers/upload_provider.dart';
import '../services/code_processor.dart';
import '../utils/terminal_address.dart';
import 'widgets.dart';

class UploadScreen extends StatefulWidget {
  const UploadScreen({super.key});

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  bool _dragging = false;

  // ------------------------------ файл ------------------------------

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Файл с кодами ЧЗ',
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );
    final file = result?.files.single;
    if (file?.path == null) return;
    await _loadFile(file!.path!, file.name);
  }

  Future<void> _onDrop(DropDoneDetails details) async {
    setState(() => _dragging = false);
    if (details.files.isEmpty) return;
    final f = details.files.first;
    if (!f.name.toLowerCase().endsWith('.xlsx')) {
      showSnack(context, 'Нужен файл .xlsx', error: true);
      return;
    }
    await _loadFile(f.path, f.name);
  }

  Future<void> _loadFile(String path, String name) async {
    final error = await context.read<UploadProvider>().loadFile(path, name);
    if (!mounted) return;
    if (error != null) showSnack(context, error, error: true);
  }

  // ------------------------------ выгрузка ------------------------------

  Future<void> _upload() async {
    final provider = context.read<UploadProvider>();

    // Сверка товара из файла с выбранным — последний шанс заметить ошибку.
    final mismatch = provider.checkSelectedProductAgainstFile;
    if (mismatch != null) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.report_problem_outlined,
              color: Colors.red, size: 36),
          title: const Text('Товар не совпадает с файлом'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(mismatch),
                const SizedBox(height: 12),
                const Text(
                  'Коды будут привязаны к выбранному товару. Если файл '
                  'и товар не про один и тот же продукт — выгружать нельзя: '
                  'коды попадут не на тот товар, и исправить это будет сложно.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Исправить выбор'),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Всё равно выгрузить'),
            ),
          ],
        ),
      );
      if (proceed != true || !mounted) return;
    }

    final dup = await provider.checkDuplicates();
    if (!mounted) return;

    var exclude = <String>{};
    if (!dup.isEmpty) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (_) => _DuplicatesDialog(
          check: dup,
          total: provider.codes.length,
          terminalKey: provider.terminal!.key,
        ),
      );
      if (proceed != true || !mounted) return;
      exclude = dup.codes;
    }

    final outcome = await provider.upload(exclude: exclude);
    if (!mounted) return;
    if (outcome.success) context.read<HistoryProvider>().load();
  }

  // ------------------------------ UI ------------------------------

  @override
  Widget build(BuildContext context) {
    final p = context.watch<UploadProvider>();

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Выгрузка кодов ЧЗ',
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 16),
        _section('1. Файл с кодами (столбец B)', _buildFileBlock(p)),
        _section('2. Терминал', _TerminalField(provider: p)),
        _section('3. Товар', _ProductField(provider: p)),
        const SizedBox(height: 8),
        SizedBox(
          height: 48,
          child: FilledButton.icon(
            onPressed: p.canUpload ? _upload : null,
            icon: p.isUploading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.send),
            label: Text(p.isUploading
                ? (p.progressText ?? 'Отправка…')
                : 'Выгрузить коды (${p.codes.length})'),
          ),
        ),
        if (p.outcome != null) ...[
          const SizedBox(height: 16),
          ResultBanner(
            success: p.outcome!.success,
            message: p.outcome!.message,
            onClose: p.clearOutcome,
          ),
        ],
      ],
    );
  }

  Widget _section(String title, Widget child) => Card(
        margin: const EdgeInsets.only(bottom: 16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              child,
            ],
          ),
        ),
      );

  Widget _buildFileBlock(UploadProvider p) {
    final scheme = Theme.of(context).colorScheme;
    final parsed = p.parsed;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropTarget(
          onDragEntered: (_) => setState(() => _dragging = true),
          onDragExited: (_) => setState(() => _dragging = false),
          onDragDone: _onDrop,
          child: InkWell(
            onTap: p.isReadingFile || p.isUploading ? null : _pickFile,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              height: 120,
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _dragging ? scheme.primary : scheme.outlineVariant,
                  width: _dragging ? 2 : 1,
                ),
                color: _dragging
                    ? scheme.primaryContainer.withAlpha(100)
                    : scheme.surfaceContainerLow,
              ),
              child: Center(
                child: p.isReadingFile
                    ? const CircularProgressIndicator()
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.upload_file,
                              size: 36, color: scheme.primary),
                          const SizedBox(height: 8),
                          Text(p.fileName ??
                              'Перетащите .xlsx сюда или нажмите, чтобы выбрать'),
                        ],
                      ),
              ),
            ),
          ),
        ),
        if (parsed != null) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              StatChip(
                  icon: Icons.check_circle,
                  color: Colors.green,
                  text: 'Корректных кодов: ${parsed.codes.length}'),
              if (parsed.duplicatesInFile > 0)
                StatChip(
                    icon: Icons.content_copy,
                    color: Colors.orange,
                    text: 'Повторов в файле убрано: ${parsed.duplicatesInFile}'),
              if (parsed.errors.isNotEmpty)
                StatChip(
                    icon: Icons.error,
                    color: Colors.red,
                    text: 'Ошибок формата: ${parsed.errors.length}'),
              // Наименование товара из ячейки F2 файла — слева от кнопки сброса.
              if (parsed.hasProductInfo)
                _ProductFromFileBadge(
                  name: parsed.productNameFromFile!,
                  idFromFile: parsed.productIdFromFile,
                  selected: p.selectedProduct,
                  autoSelected: p.productAutoSelected,
                ),
              ActionChip(
                avatar: const Icon(Icons.close, size: 18),
                label: const Text('Сбросить файл'),
                onPressed: p.isUploading ? null : p.clearFile,
              ),
            ],
          ),
          if (parsed.errors.isNotEmpty)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Строки с ошибками'),
              children: [
                for (final e in parsed.errors.take(200))
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SelectableText(e,
                        style: const TextStyle(color: Colors.red)),
                  ),
              ],
            ),
          if (parsed.codes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Первые коды:', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 4),
            for (final c in parsed.codes.take(5))
              SelectableText('$c   →   ${CodeProcessor.toBase64(c)}',
                  style: monoStyle),
          ],
        ],
      ],
    );
  }
}

/// Плашка с наименованием товара из файла (ячейка F2).
///
/// Нужна, чтобы человек глазами сверил: тот ли товар в файле, что он
/// собирается выгружать. Если выбор не совпал — плашка краснеет
/// и прямо говорит, в чём расхождение.
class _ProductFromFileBadge extends StatelessWidget {
  final String name;
  final String? idFromFile;
  final Product? selected;
  final bool autoSelected;

  const _ProductFromFileBadge({
    required this.name,
    required this.selected,
    required this.autoSelected,
    this.idFromFile,
  });

  /// Совпадает ли выбранный товар с тем, что в файле.
  bool get _matches {
    final chosen = selected;
    if (chosen == null) return false;

    final a = normalizeProductName(name);
    final b = normalizeProductName(chosen.name);
    if (a == b) return true;
    return a.contains(b) || b.contains(a);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final chosen = selected;
    final ok = _matches;

    final Color color;
    final IconData icon;
    final String secondary;

    if (chosen == null) {
      color = Colors.orange;
      icon = Icons.help_outline;
      secondary = 'Товар ещё не выбран';
    } else if (ok) {
      color = Colors.green;
      icon = Icons.verified_outlined;
      secondary = autoSelected
          ? 'Подставлен автоматически: ${chosen.label}'
          : 'Совпадает с выбранным: ${chosen.label}';
    } else {
      color = Colors.red;
      icon = Icons.report_problem_outlined;
      secondary = 'ВНИМАНИЕ: выбран другой товар — ${chosen.label}';
    }

    return Tooltip(
      message: idFromFile == null
          ? 'Наименование из ячейки F2 файла'
          : 'Наименование из ячейки F2 файла\n'
              'ID из 1С (ячейка E2): $idFromFile',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withAlpha(20),
          border: Border.all(color: color.withAlpha(120)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'В файле: $name',
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  secondary,
                  style: TextStyle(
                    color: ok ? scheme.onSurfaceVariant : color,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Адрес терминала: ручной ввод + выпадающий список последних адресов.
class _TerminalField extends StatefulWidget {
  final UploadProvider provider;
  const _TerminalField({required this.provider});

  @override
  State<_TerminalField> createState() => _TerminalFieldState();
}

class _TerminalFieldState extends State<_TerminalField> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.provider.terminalUrl);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _set(String value) {
    _ctrl.text = value;
    widget.provider.setTerminalUrl(value);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.provider;
    final parsed = TerminalAddress.tryParse(p.terminalUrl);
    final showError = p.terminalUrl.trim().isNotEmpty && parsed == null;

    return TextField(
      controller: _ctrl,
      enabled: !p.isUploading,
      onChanged: p.setTerminalUrl,
      decoration: InputDecoration(
        border: const OutlineInputBorder(),
        labelText: 'Адрес терминала',
        hintText: 'http://192.168.1.82:4001/api',
        prefixIcon: const Icon(Icons.router),
        helperText: parsed == null ? null : 'Терминал: ${parsed.key}',
        errorText: showError ? 'Некорректный адрес' : null,
        suffixIcon: PopupMenuButton<String>(
          tooltip: 'Последние адреса',
          icon: const Icon(Icons.arrow_drop_down),
          enabled: p.recentUrls.isNotEmpty && !p.isUploading,
          onSelected: _set,
          itemBuilder: (_) => [
            for (final url in p.recentUrls)
              PopupMenuItem(value: url, child: Text(url)),
          ],
        ),
      ),
    );
  }
}

/// Выбор товара с поиском по ID и наименованию.
class _ProductField extends StatelessWidget {
  final UploadProvider provider;
  const _ProductField({required this.provider});

  @override
  Widget build(BuildContext context) {
    final p = provider;
    if (p.products.isEmpty) {
      return const Text(
        'Справочник товаров пуст. Импортируйте его на вкладке «Настройки».',
        style: TextStyle(color: Colors.orange),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Autocomplete<Product>(
          // Пересоздаём поле при смене выбранного товара извне.
          key: ValueKey('${p.selectedProduct?.id}-${p.showHiddenProducts}'),
          initialValue: TextEditingValue(text: p.selectedProduct?.label ?? ''),
          displayStringForOption: (o) => o.label,
          optionsBuilder: (value) {
            final q = value.text.trim().toLowerCase();
            final list = p.visibleProducts;
            if (q.isEmpty || q == p.selectedProduct?.label.toLowerCase()) {
              return list;
            }
            return list.where((o) =>
                o.id.toString().startsWith(q) ||
                o.name.toLowerCase().contains(q));
          },
          onSelected: p.setProduct,
          fieldViewBuilder: (context, ctrl, focus, onSubmit) => TextField(
            controller: ctrl,
            focusNode: focus,
            enabled: !p.isUploading,
            onSubmitted: (_) => onSubmit(),
            onChanged: (text) {
              if (p.selectedProduct != null &&
                  text != p.selectedProduct!.label) {
                p.setProduct(null);
              }
            },
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: 'Товар (поиск по ID или названию)',
              prefixIcon: const Icon(Icons.inventory_2_outlined),
              suffixIcon: p.selectedProduct == null
                  ? null
                  : const Icon(Icons.check_circle, color: Colors.green),
            ),
          ),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          controlAffinity: ListTileControlAffinity.leading,
          value: p.showHiddenProducts,
          onChanged: (v) => p.setShowHiddenProducts(v ?? false),
          title: const Text(
              'Показывать удалённые и дубликаты (#удалено#, #дубликат#)'),
        ),
      ],
    );
  }
}

/// Предупреждение о кодах, уже загруженных на этот терминал.
class _DuplicatesDialog extends StatelessWidget {
  final DuplicateCheck check;
  final int total;
  final String terminalKey;

  const _DuplicatesDialog({
    required this.check,
    required this.total,
    required this.terminalKey,
  });

  @override
  Widget build(BuildContext context) {
    final fresh = total - check.codes.length;
    return AlertDialog(
      icon: const Icon(Icons.warning_amber, color: Colors.orange, size: 36),
      title: Text('${check.codes.length} из $total кодов уже загружены'),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Терминал $terminalKey, записи со статусом «Загружено»:'),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final g in check.groups)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.inventory),
                      title:
                          Text('Запись №${g.record.id} — ${g.record.productLabel}'),
                      subtitle: Text(
                          '${formatDateTime(g.record.uploadedAt)} · ${g.record.fileName} · '
                          'совпадает кодов: ${g.count}'),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(fresh > 0
                ? 'Будут отправлены только новые коды: $fresh.'
                : 'Новых кодов нет — выгружать нечего.'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: fresh > 0 ? () => Navigator.pop(context, true) : null,
          child: Text('Загрузить только новые ($fresh)'),
        ),
      ],
    );
  }
}
