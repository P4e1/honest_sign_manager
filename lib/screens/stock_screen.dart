import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/labeling_record.dart';
import '../models/product.dart';
import '../providers/stock_provider.dart';
import '../utils/terminal_address.dart';
import 'widgets.dart';

class StockScreen extends StatefulWidget {
  const StockScreen({super.key});

  @override
  State<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends State<StockScreen> {
  Future<void> _load() async {
    await context.read<StockProvider>().load();
  }

  Future<void> _export() async {
    final provider = context.read<StockProvider>();
    final product = provider.selectedProduct;
    if (product == null) return;

    final stamp = DateTime.now();
    final safeName = product.name
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Сохранить отчёт о нанесении',
      fileName: 'Остатки ЧЗ $safeName '
          '${stamp.year}${_two(stamp.month)}${_two(stamp.day)}.xlsx',
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );
    if (path == null || !mounted) return;

    final finalPath = path.toLowerCase().endsWith('.xlsx') ? path : '$path.xlsx';
    final error = await provider.exportToExcel(finalPath);
    if (!mounted) return;

    if (error == null) {
      showSnack(context, 'Отчёт сохранён');
    } else {
      showSnack(context, error, error: true);
    }
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final p = context.watch<StockProvider>();

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            Text('Остатки кодов ЧЗ',
                style: Theme.of(context).textTheme.headlineSmall),
            const Spacer(),
            if (p.loadedAt != null)
              Text('обновлено ${formatDateTime(p.loadedAt!)}',
                  style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        const SizedBox(height: 16),
        _card('1. Товар', _ProductField(provider: p)),
        _card('2. Терминал', _TerminalField(provider: p)),
        _card('3. Период истории', _PeriodField(provider: p)),
        SizedBox(
          height: 48,
          child: FilledButton.icon(
            onPressed: p.canLoad ? _load : null,
            icon: p.isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.inventory_2),
            label: Text(
              p.isLoading ? (p.progressText ?? 'Загрузка…') : 'Узнать остаток',
            ),
          ),
        ),
        if (p.error != null) ...[
          const SizedBox(height: 16),
          ResultBanner(success: false, message: p.error!),
        ],
        if (p.report != null) ...[
          const SizedBox(height: 24),
          _buildReport(context, p),
        ],
      ],
    );
  }

  // ─── Отчёт ──────────────────────────────────────────────────────────────────

  Widget _buildReport(BuildContext context, StockProvider p) {
    final r = p.report!;
    final scheme = Theme.of(context).colorScheme;
    final notPrinted = r.notPrintedCodes;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Результат по товару «${p.selectedProduct!.name}»',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            FilledButton.tonalIcon(
              onPressed: _export,
              icon: const Icon(Icons.file_download_outlined),
              label: const Text('Отчёт в Excel'),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Карточки-показатели
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _StatCard(
              label: 'Свободных кодов',
              value: '${r.freeCount}',
              hint: 'Статус NEW на терминале',
              color: scheme.primary,
              icon: Icons.qr_code_2,
            ),
            _StatCard(
              label: 'Напечатано',
              value: '${r.printed.length}',
              hint: 'Статус Ready',
              color: Colors.green,
              icon: Icons.print,
            ),
            _StatCard(
              label: 'Не напечатано',
              value: '${notPrinted.length}',
              hint: 'Загружено, но без нанесения',
              color: notPrinted.isEmpty ? Colors.grey : Colors.orange,
              icon: Icons.print_disabled,
            ),
            _StatCard(
              label: 'Отменено',
              value: '${r.cancelled.length}',
              hint: 'Статус Cancelled',
              color: Colors.red,
              icon: Icons.cancel_outlined,
            ),
            if (r.locked.isNotEmpty)
              _StatCard(
                label: 'В обработке',
                value: '${r.locked.length}',
                hint: 'Статус Locked',
                color: Colors.blueGrey,
                icon: Icons.hourglass_bottom,
              ),
          ],
        ),
        const SizedBox(height: 16),

        // Пояснение по сходимости
        _discrepancyNote(r),

        if (notPrinted.isNotEmpty) ...[
          const SizedBox(height: 16),
          _notPrintedList(notPrinted),
        ],

        if (r.printed.isNotEmpty) ...[
          const SizedBox(height: 16),
          _printedList(r),
        ],

        if (r.labeling.isEmpty) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'За период «${p.period.label}» терминал не вернул ни одной записи '
              'маркировки по этому товару. Попробуйте выбрать период пошире '
              'или проверьте, что коды действительно наносились.',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ],
    );
  }

  Widget _discrepancyNote(StockReport report) {
    final diff = report.discrepancy;
    if (diff == 0) {
      return const SizedBox.shrink();
    }

    final text = diff > 0
        ? 'На терминале на $diff свободных кодов больше, чем не напечатанных '
            'в нашей истории. Часть кодов загружена не через это приложение '
            'или с другого компьютера.'
        : 'Свободных кодов на ${-diff} меньше, чем незапечатанных в нашей '
            'истории. Возможно, коды израсходованы, напечатаны не полностью '
            'или удалены с терминала вручную.';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        border: Border.all(color: Colors.amber),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: Colors.orange),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }

  Widget _notPrintedList(List<String> codes) {
    return _ExpandableList(
      title: 'Загружены, но не напечатаны (${codes.length})',
      icon: Icons.print_disabled,
      color: Colors.orange,
      codes: codes,
    );
  }

  Widget _printedList(StockReport report) {
    return _ExpandableList(
      title: 'Напечатанные коды (${report.printed.length})',
      icon: Icons.print,
      color: Colors.green,
      codes: report.printedCodes.toList(),
    );
  }

  Widget _card(String title, Widget child) => Card(
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
}

/// Поле выбора товара с поиском по ID и наименованию.
class _ProductField extends StatelessWidget {
  final StockProvider provider;
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

/// Адрес терминала: ручной ввод + список последних.
class _TerminalField extends StatefulWidget {
  final StockProvider provider;
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
      enabled: !p.isLoading,
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
          enabled: p.recentUrls.isNotEmpty && !p.isLoading,
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

/// Выбор периода истории маркировки.
class _PeriodField extends StatelessWidget {
  final StockProvider provider;
  const _PeriodField({required this.provider});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: [
        for (final period in StockPeriod.values)
          ChoiceChip(
            label: Text(period.label),
            selected: provider.period == period,
            onSelected: provider.isLoading
                ? null
                : (_) => provider.setPeriod(period),
          ),
      ],
    );
  }
}

/// Карточка-показатель.
class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String hint;
  final Color color;
  final IconData icon;

  const _StatCard({
    required this.label,
    required this.value,
    required this.hint,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 210,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withAlpha(18),
        border: Border.all(color: color.withAlpha(90)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(label,
                    style: TextStyle(
                        color: color, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(value,
              style: TextStyle(
                  fontSize: 28, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 2),
          Text(hint,
              style: Theme.of(context).textTheme.bodySmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

/// Раскрывающийся список кодов с копированием.
class _ExpandableList extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final List<String> codes;

  const _ExpandableList({
    required this.title,
    required this.icon,
    required this.color,
    required this.codes,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        leading: Icon(icon, color: color),
        title: Text(title),
        children: [
          Container(
            height: 260,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ListView.builder(
              itemCount: codes.length,
              itemBuilder: (_, i) => SelectableText(
                '${(i + 1).toString().padLeft(5)}.  ${codes[i]}',
                style: monoStyle,
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
