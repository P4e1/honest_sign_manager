import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/vault.dart';
import '../providers/vault_provider.dart';
import '../utils/terminal_address.dart';
import 'widgets.dart';

/// Панель «Изъять коды» / «Вернуть коды».
///
/// Нужна, когда терминал не даёт править товары, пока на нём есть коды:
/// коды снимаются в файл, справочник правится, коды возвращаются.
class VaultPanel extends StatefulWidget {
  /// Адрес терминала, выбранный в разделе «Остатки».
  final String terminalUrl;

  const VaultPanel({super.key, required this.terminalUrl});

  @override
  State<VaultPanel> createState() => _VaultPanelState();
}

class _VaultPanelState extends State<VaultPanel> {
  final _reasonCtrl = TextEditingController();

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  TerminalAddress? get _terminal => TerminalAddress.tryParse(widget.terminalUrl);

  Future<void> _withdraw() async {
    final terminal = _terminal;
    if (terminal == null) {
      showSnack(context, 'Сначала укажите корректный адрес терминала',
          error: true);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.download_for_offline_outlined,
            size: 36, color: Colors.orange),
        title: Text('Снять все коды с терминала ${terminal.key}?'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Все коды из истории этого терминала будут удалены с него '
                'и сохранены в файл. После этого можно будет изменить '
                'справочник товаров — терминал не будет его блокировать.',
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  border: Border.all(color: Colors.amber),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber, color: Colors.orange),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Пока коды сняты, на терминале их нет — нанесение '
                        'и печать работать не будут. Верните коды сразу '
                        'после правки товаров.',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _reasonCtrl,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Причина (необязательно)',
                  hintText: 'например: правка справочника товаров',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Снять коды'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    await context
        .read<VaultProvider>()
        .withdraw(terminalUrl: widget.terminalUrl, reason: _reasonCtrl.text);
    if (!mounted) return;
    _reasonCtrl.clear();
  }

  Future<void> _restore(Withdrawal withdrawal) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.upload_file, size: 36, color: Colors.green),
        title: const Text('Вернуть коды на терминал?'),
        content: SizedBox(
          width: 480,
          child: Text(
            'Изъятие от ${formatDateTime(withdrawal.createdAt)}\n'
            'Терминал: ${withdrawal.terminalKey}\n'
            'Кодов: ${withdrawal.codesCount}'
            '${withdrawal.reason == null ? '' : '\nПричина: ${withdrawal.reason}'}\n\n'
            'Коды будут загружены заново, сгруппированные по товарам. '
            'Записи в истории вернутся в статус «Загружено».',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Вернуть'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    await context.read<VaultProvider>().restore(withdrawal);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<VaultProvider>();
    final terminal = _terminal;
    final available = p.withdrawals
        .where((w) => !w.isRestored)
        .where((w) => terminal == null || w.terminalKey == terminal.key)
        .toList();

    return Card(
      margin: const EdgeInsets.only(top: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.swap_vert, size: 20),
                const SizedBox(width: 8),
                Text('Изъятие кодов на время правки товаров',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                IconButton(
                  tooltip: 'Обновить список',
                  onPressed: p.isBusy ? null : () => p.load(terminal?.key),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Терминал не даёт изменять товары, пока на нём есть коды. '
              'Снимите коды в файл, отредактируйте справочник, верните коды обратно.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),

            if (p.isBusy) ...[
              LinearProgressIndicator(
                minHeight: 4,
                borderRadius: BorderRadius.circular(2),
              ),
              const SizedBox(height: 8),
              Text(p.progressText ?? 'Выполняется…'),
              const SizedBox(height: 8),
            ],

            Row(
              children: [
                FilledButton.tonalIcon(
                  onPressed: (p.isBusy || terminal == null) ? null : _withdraw,
                  icon: const Icon(Icons.download_for_offline_outlined),
                  label: const Text('Снять все коды в файл'),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: p.isBusy ? null : () => p.load(terminal?.key),
                  icon: const Icon(Icons.folder_open),
                  label: Text('Мои изъятия (${available.length})'),
                ),
              ],
            ),

            if (p.error != null) ...[
              const SizedBox(height: 12),
              ResultBanner(success: false, message: p.error!),
            ],
            if (p.successMessage != null) ...[
              const SizedBox(height: 12),
              ResultBanner(
                success: true,
                message: p.successMessage!,
                onClose: p.clearMessages,
              ),
            ],

            if (available.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Не возвращены на терминал:',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              for (final w in available) _withdrawalTile(w, p),
            ],
          ],
        ),
      ),
    );
  }

  Widget _withdrawalTile(Withdrawal w, VaultProvider p) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.inventory, color: Colors.orange),
        title: Text('Изъятие ${w.withdrawalId} · ${w.codesCount} кодов'),
        subtitle: Text(
          '${formatDateTime(w.createdAt)} · ${w.terminalKey}'
          '${w.reason == null ? '' : ' · ${w.reason}'}'
          '\n${w.source} · файл: ${w.filePath}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        isThreeLine: true,
        trailing: FilledButton.icon(
          onPressed: p.isBusy ? null : () => _restore(w),
          icon: const Icon(Icons.upload_file, size: 18),
          label: const Text('Вернуть'),
        ),
      ),
    );
  }
}
