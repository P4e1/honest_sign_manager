/// Один код маркировки внутри записи истории.
class MarkingCode {
  final int? id;
  final int recordId;

  /// Код в исходном виде (как в Excel).
  final String raw;

  /// Код в Base64 — именно в таком виде он хранится на терминале.
  final String base64;

  /// Ключ терминала «IP:порт».
  final String terminalKey;

  /// Поля из ответа терминала (могут отсутствовать).
  final String? type;
  final String? status;
  final String? createdAt;

  const MarkingCode({
    this.id,
    required this.recordId,
    required this.raw,
    required this.base64,
    required this.terminalKey,
    this.type,
    this.status,
    this.createdAt,
  });

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'record_id': recordId,
        'raw': raw,
        'base64': base64,
        'terminal_key': terminalKey,
        'type': type,
        'status': status,
        'created_at': createdAt,
      };

  factory MarkingCode.fromMap(Map<String, Object?> map) => MarkingCode(
        id: map['id'] as int?,
        recordId: map['record_id'] as int,
        raw: map['raw'] as String,
        base64: map['base64'] as String,
        terminalKey: map['terminal_key'] as String,
        type: map['type'] as String?,
        status: map['status'] as String?,
        createdAt: map['created_at'] as String?,
      );
}
