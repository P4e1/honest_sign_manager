import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/marking_code.dart';
import '../models/upload_record.dart';
import '../providers/history_provider.dart';
import 'widgets.dart';

/// Карточка записи истории: параметры выгрузки и список кодов.
/// Возвращает 'delete', если пользователь нажал «Удалить с терминала».
class RecordDetailsDialog extends StatefulWidget {
  final UploadRecord record;
  const RecordDetailsDialog({super.key, required this.record});

  @override
  State<RecordDetailsDialog> createState() => _RecordDetailsDialogState();
}

class _RecordDetailsDialogState extends State<RecordDetailsDialog> {
  late final Future<List<MarkingCode>> _codes =
      context.read<HistoryProvider>().codesOf(widget.record);
  bool _showBase64 = false;

  Future<void> _copy(List<MarkingCode> codes) async {
    final text =
        codes.map((c) => _showBase64 ? c.base64 : c.raw).join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) showSnack(context, 'Скопировано кодов: ${codes.length}');
  }

  Widget _info(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 140,
              child: Text(label,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            Expanded(child: SelectableText(value)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final r = widget.record;
    return AlertDialog(
      title: Row(
        children: [
          Text('Запись №${r.id}'),
          const SizedBox(width: 12),
          StatusBadge(
            loaded: r.isLoaded,
            withdrawn: r.isWithdrawn,
            text: r.status,
          ),
        ],
      ),
      content: SizedBox(
        width: 760,
        height: 520,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _info('Дата выгрузки', formatDateTime(r.uploadedAt)),
            if (r.deletedAt != null)
              _info('Дата удаления', formatDateTime(r.deletedAt!)),
            _info('Терминал', '${r.terminalKey}   (${r.terminalUrl})'),
            _info('Товар', r.productLabel),
            _info('Файл', r.fileName),
            _info('Ответ терминала', 'HTTP ${r.httpStatus}'),
            _info('Кодов', '${r.codesCount}'),
            const Divider(height: 24),
            Expanded(child: _codesList()),
          ],
        ),
      ),
      actions: [
        if (r.isLoaded)
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, 'delete'),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Удалить с терминала'),
          ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Закрыть'),
        ),
      ],
    );
  }

  Widget _codesList() {
    return FutureBuilder<List<MarkingCode>>(
      future: _codes,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Text('Ошибка чтения кодов: ${snap.error}',
              style: const TextStyle(color: Colors.red));
        }
        final codes = snap.data ?? const <MarkingCode>[];
        if (codes.isEmpty) return const Text('Кодов нет');

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('Коды (${codes.length})',
                    style: Theme.of(context).textTheme.titleSmall),
                const Spacer(),
                const Text('Base64'),
                Switch(
                  value: _showBase64,
                  onChanged: (v) => setState(() => _showBase64 = v),
                ),
                TextButton.icon(
                  onPressed: () => _copy(codes),
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('Копировать все'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: codes.length,
                  itemBuilder: (_, i) {
                    final c = codes[i];
                    return SelectableText(
                      '${(i + 1).toString().padLeft(5)}.  '
                      '${_showBase64 ? c.base64 : c.raw}',
                      style: monoStyle,
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
