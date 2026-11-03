import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/upload_record.dart';
import '../providers/history_provider.dart';
import '../services/sync_service.dart';
import 'record_details_dialog.dart';
import 'widgets.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDates(HistoryProvider h) async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 1),
      initialDateRange: h.dateRange,
    );
    if (range != null) h.setDateRange(range);
  }

  Future<void> _showDetails(UploadRecord r) async {
    final action = await showDialog<String>(
      context: context,
      builder: (_) => RecordDetailsDialog(record: r),
    );
    if (action == 'delete' && mounted) await _delete(r);
  }

  Future<void> _delete(UploadRecord r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Удалить запись №${r.id} с терминала?'),
        content: Text(
            '${r.codesCount} кодов будут удалены с терминала ${r.terminalKey}.\n'
            'Товар: ${r.productLabel}\n\n'
            'Запись останется в истории со статусом «${RecordStatus.deleted}».'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final error = await context.read<HistoryProvider>().deleteFromTerminal(r);
    if (!mounted) return;
    if (error == null) {
      showSnack(context, 'Запись №${r.id}: коды удалены с терминала');
    } else {
      showSnack(context, error, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = context.watch<HistoryProvider>();
    final records = h.records;
    if (_searchCtrl.text != h.search) _searchCtrl.text = h.search;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('История выгрузок',
                  style: Theme.of(context).textTheme.headlineSmall),
              const Spacer(),
              IconButton(
                tooltip: 'Обновить',
                onPressed: h.load,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildFilters(h),
          const SizedBox(height: 8),
          Row(
            children: [
              Text('Найдено записей: ${records.length}',
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(width: 16),
              _buildSyncStatus(h),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: h.isLoading && records.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : records.isEmpty
                    ? const Center(child: Text('Записей нет'))
                    : Card(child: _buildTable(h, records)),
          ),
        ],
      ),
    );
  }

  /// Строка состояния синхронизации с файловым сервером.
  Widget _buildSyncStatus(HistoryProvider h) {
    final sync = h.lastSync;
    final at = h.lastSyncAt;

    final (IconData icon, Color color, String text) = switch (sync) {
      null => (Icons.cloud_queue, Colors.grey, 'Синхронизация не выполнялась'),
      SyncResult(storeError: final String e) =>
        (Icons.cloud_off, Colors.orange, 'Нет связи с файловым сервером'),
      _ when sync.hasChanges =>
        (Icons.cloud_done, Colors.green, sync.summary),
      _ => (Icons.cloud_done, Colors.green, 'Данные актуальны'),
    };

    final time = at == null ? '' : ' · ${formatDateTime(at)}';
    final hint = sync?.storeError;

    return Tooltip(
      message: hint ?? 'История на файловом сервере',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          Text('$text$time',
              style: TextStyle(fontSize: 12, color: color)),
        ],
      ),
    );
  }

  Widget _buildFilters(HistoryProvider h) {
    final products = h.productsInHistory;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 320,
          child: TextField(
            controller: _searchCtrl,
            onChanged: h.setSearch,
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.search),
              labelText: 'Поиск: товар, ID, терминал, файл, №',
            ),
          ),
        ),
        SizedBox(
          width: 220,
          child: DropdownButtonFormField<String?>(
            value: h.terminalKey,
            isExpanded: true,
            decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                labelText: 'Терминал'),
            items: [
              const DropdownMenuItem(value: null, child: Text('Все')),
              for (final k in h.terminalKeys)
                DropdownMenuItem(value: k, child: Text(k)),
            ],
            onChanged: h.setTerminalKey,
          ),
        ),
        SizedBox(
          width: 320,
          child: DropdownButtonFormField<int?>(
            value: products.containsKey(h.productId) ? h.productId : null,
            isExpanded: true,
            decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                labelText: 'Товар'),
            items: [
              const DropdownMenuItem(value: null, child: Text('Все')),
              for (final e in products.entries)
                DropdownMenuItem(
                  value: e.key,
                  child: Text('${e.key} — ${e.value}',
                      overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: h.setProductId,
          ),
        ),
        SizedBox(
          width: 170,
          child: DropdownButtonFormField<String?>(
            value: h.status,
            isExpanded: true,
            decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                labelText: 'Статус'),
            items: const [
              DropdownMenuItem(value: null, child: Text('Все')),
              DropdownMenuItem(
                  value: RecordStatus.loaded, child: Text(RecordStatus.loaded)),
              DropdownMenuItem(
                  value: RecordStatus.withdrawn,
                  child: Text(RecordStatus.withdrawn)),
              DropdownMenuItem(
                  value: RecordStatus.deleted,
                  child: Text(RecordStatus.deleted)),
            ],
            onChanged: h.setStatus,
          ),
        ),
        OutlinedButton.icon(
          onPressed: () => _pickDates(h),
          icon: const Icon(Icons.date_range),
          label: Text(h.dateRange == null
              ? 'Период'
              : '${formatDate(h.dateRange!.start)} – ${formatDate(h.dateRange!.end)}'),
        ),
        if (h.hasFilters)
          TextButton.icon(
            onPressed: () {
              _searchCtrl.clear();
              h.clearFilters();
            },
            icon: const Icon(Icons.filter_alt_off),
            label: const Text('Сбросить фильтры'),
          ),
      ],
    );
  }

  Widget _buildTable(HistoryProvider h, List<UploadRecord> records) {
    return SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          showCheckboxColumn: false,
          columns: const [
            DataColumn(label: Text('№'), numeric: true),
            DataColumn(label: Text('Дата')),
            DataColumn(label: Text('Терминал')),
            DataColumn(label: Text('ID'), numeric: true),
            DataColumn(label: Text('Товар')),
            DataColumn(label: Text('Файл')),
            DataColumn(label: Text('Кодов'), numeric: true),
            DataColumn(label: Text('HTTP')),
            DataColumn(label: Text('Статус')),
            DataColumn(label: Text('')),
          ],
          rows: [
            for (final r in records)
              DataRow(
                onSelectChanged: (_) => _showDetails(r),
                cells: [
                  DataCell(Text('${r.id}')),
                  DataCell(Text(formatDateTime(r.uploadedAt))),
                  DataCell(Text(r.terminalKey)),
                  DataCell(Text('${r.productId}')),
                  DataCell(ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 280),
                    child: Text(r.productName, overflow: TextOverflow.ellipsis),
                  )),
                  DataCell(ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 200),
                    child: Text(r.fileName, overflow: TextOverflow.ellipsis),
                  )),
                  DataCell(Text('${r.codesCount}')),
                  DataCell(Text('${r.httpStatus}')),
                  DataCell(_statusBadge(r)),
                  DataCell(_rowActions(h, r)),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _statusBadge(UploadRecord r) => StatusBadge(
        loaded: r.isLoaded,
        withdrawn: r.isWithdrawn,
        text: r.status,
      );

  Widget _rowActions(HistoryProvider h, UploadRecord r) {
    if (h.deletingId == r.id) {
      return const SizedBox(
          width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2));
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Коды записи',
          icon: const Icon(Icons.list_alt),
          onPressed: () => _showDetails(r),
        ),
        if (r.isLoaded)
          IconButton(
            tooltip: 'Удалить с терминала',
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            onPressed: h.deletingId == null ? () => _delete(r) : null,
          ),
      ],
    );
  }
}
