import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Общие мелкие виджеты и форматирование.

const monoStyle = TextStyle(fontFamily: 'Consolas', fontSize: 12);

final _dateTimeFormat = DateFormat('dd.MM.yyyy HH:mm:ss');
final _dateFormat = DateFormat('dd.MM.yyyy');

String formatDateTime(DateTime dt) => _dateTimeFormat.format(dt);
String formatDate(DateTime dt) => _dateFormat.format(dt);

void showSnack(BuildContext context, String text, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(text),
      backgroundColor: error ? Colors.red.shade700 : null,
      duration: Duration(seconds: error ? 6 : 3),
    ),
  );
}

/// Плашка с результатом операции (зелёная / красная).
class ResultBanner extends StatelessWidget {
  final bool success;
  final String message;
  final VoidCallback? onClose;

  const ResultBanner({
    super.key,
    required this.success,
    required this.message,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final color = success ? Colors.green : Colors.red;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.shade50,
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(success ? Icons.check_circle : Icons.error, color: color),
          const SizedBox(width: 12),
          Expanded(child: SelectableText(message)),
          if (onClose != null)
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Закрыть',
              onPressed: onClose,
            ),
        ],
      ),
    );
  }
}

/// Маленькая плашка со статистикой.
class StatChip extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;

  const StatChip({
    super.key,
    required this.icon,
    required this.color,
    required this.text,
  });

  @override
  Widget build(BuildContext context) => Chip(
        avatar: Icon(icon, color: color, size: 18),
        label: Text(text),
      );
}

/// Цветной бейдж статуса записи.
///
/// Цвета: загружено — зелёный, изъято — оранжевый, удалено — серый.
class StatusBadge extends StatelessWidget {
  final bool loaded;
  final bool withdrawn;
  final String text;

  const StatusBadge({
    super.key,
    required this.loaded,
    required this.text,
    this.withdrawn = false,
  });

  @override
  Widget build(BuildContext context) {
    final MaterialColor color = loaded
        ? Colors.green
        : withdrawn
            ? Colors.orange
            : Colors.grey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text,
          style: TextStyle(color: color.shade900, fontWeight: FontWeight.w600)),
    );
  }
}
