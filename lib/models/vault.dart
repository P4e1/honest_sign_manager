/// Один код в файле изъятия.
class VaultCode {
  final String raw;
  final String base64;
  final int productId;
  final String productName;

  /// Запись истории, из которой код взят.
  final String storeId;
  final String uploadedAt;

  const VaultCode({
    required this.raw,
    required this.base64,
    required this.productId,
    required this.productName,
    required this.storeId,
    required this.uploadedAt,
  });

  Map<String, Object?> toJson() => {
        'raw': raw,
        'base64': base64,
        'productId': productId,
        'productName': productName,
        'storeId': storeId,
        'uploadedAt': uploadedAt,
      };

  factory VaultCode.fromJson(Map<String, dynamic> json) => VaultCode(
        raw: json['raw'] as String? ?? '',
        base64: json['base64'] as String? ?? '',
        productId: (json['productId'] as num?)?.toInt() ?? 0,
        productName: json['productName'] as String? ?? '',
        storeId: json['storeId'] as String? ?? '',
        uploadedAt: json['uploadedAt'] as String? ?? '',
      );
}

/// Полное содержимое файла изъятия — со всеми кодами.
class VaultFile {
  final String withdrawalId;
  final String terminalKey;
  final String terminalUrl;
  final DateTime createdAt;
  final String author;
  final String machine;
  final String? reason;
  final List<VaultCode> codes;

  const VaultFile({
    required this.withdrawalId,
    required this.terminalKey,
    required this.terminalUrl,
    required this.createdAt,
    required this.author,
    required this.machine,
    required this.reason,
    required this.codes,
  });

  Map<String, Object?> toJson() => {
        'withdrawalId': withdrawalId,
        'terminalKey': terminalKey,
        'terminalUrl': terminalUrl,
        'createdAt': createdAt.toIso8601String(),
        'author': author,
        'machine': machine,
        'reason': reason,
        'codesCount': codes.length,
        'codes': [for (final c in codes) c.toJson()],
      };

  factory VaultFile.fromJson(Map<String, dynamic> json) => VaultFile(
        withdrawalId: json['withdrawalId'] as String? ?? '',
        terminalKey: json['terminalKey'] as String? ?? '',
        terminalUrl: json['terminalUrl'] as String? ?? '',
        createdAt:
            DateTime.tryParse(json['createdAt'] as String? ?? '') ??
                DateTime.now(),
        author: json['author'] as String? ?? '',
        machine: json['machine'] as String? ?? '',
        reason: json['reason'] as String?,
        codes: [
          for (final item in (json['codes'] as List<dynamic>? ?? const []))
            if (item is Map<String, dynamic>) VaultCode.fromJson(item),
        ],
      );
}

/// Запись об изъятии — метаданные, без кодов.
/// Читается из <id>.meta.json, чтобы не парсить файл с 25 000 кодов.
class Withdrawal {
  final String withdrawalId;
  final String terminalKey;
  final String terminalUrl;

  /// Путь к полному файлу с кодами.
  final String filePath;

  final int codesCount;
  final DateTime createdAt;
  final String author;
  final String? reason;
  final DateTime? restoredAt;

  /// Откуда взято: 'Локально' или 'Файловый сервер'.
  final String source;

  const Withdrawal({
    required this.withdrawalId,
    required this.terminalKey,
    required this.terminalUrl,
    required this.filePath,
    required this.codesCount,
    required this.createdAt,
    required this.author,
    this.reason,
    this.restoredAt,
    this.source = 'Локально',
  });

  bool get isRestored => restoredAt != null;

  Withdrawal copyWith({DateTime? restoredAt, String? source}) => Withdrawal(
        withdrawalId: withdrawalId,
        terminalKey: terminalKey,
        terminalUrl: terminalUrl,
        filePath: filePath,
        codesCount: codesCount,
        createdAt: createdAt,
        author: author,
        reason: reason,
        restoredAt: restoredAt ?? this.restoredAt,
        source: source ?? this.source,
      );

  Map<String, Object?> toJson() => {
        'withdrawalId': withdrawalId,
        'terminalKey': terminalKey,
        'terminalUrl': terminalUrl,
        'codesCount': codesCount,
        'createdAt': createdAt.toIso8601String(),
        'author': author,
        'reason': reason,
        'restoredAt': restoredAt?.toIso8601String(),
      };

  factory Withdrawal.fromJson(Map<String, dynamic> json,
          {String filePath = '', String source = 'Локально'}) =>
      Withdrawal(
        withdrawalId: json['withdrawalId'] as String? ?? '',
        terminalKey: json['terminalKey'] as String? ?? '',
        terminalUrl: json['terminalUrl'] as String? ?? '',
        filePath: filePath,
        codesCount: (json['codesCount'] as num?)?.toInt() ?? 0,
        createdAt:
            DateTime.tryParse(json['createdAt'] as String? ?? '') ??
                DateTime.now(),
        author: json['author'] as String? ?? '',
        reason: json['reason'] as String?,
        restoredAt: json['restoredAt'] == null
            ? null
            : DateTime.tryParse(json['restoredAt'] as String),
        source: source,
      );
}
