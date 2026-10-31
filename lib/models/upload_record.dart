/// Статусы записи истории.
class RecordStatus {
  static const loaded = 'Загружено';
  static const deleted = 'Удалён';
}

/// Запись истории = одна выгрузка файла на терминал.
class UploadRecord {
  /// Собственный номер записи (автоинкремент в БД).
  final int? id;
  final String terminalUrl;
  final String terminalKey;
  final int productId;
  final String productName;
  final String fileName;
  final int codesCount;
  final int httpStatus;
  final String status;
  final DateTime uploadedAt;
  final DateTime? deletedAt;

  const UploadRecord({
    this.id,
    required this.terminalUrl,
    required this.terminalKey,
    required this.productId,
    required this.productName,
    required this.fileName,
    required this.codesCount,
    required this.httpStatus,
    required this.status,
    required this.uploadedAt,
    this.deletedAt,
  });

  bool get isLoaded => status == RecordStatus.loaded;
  bool get isDeleted => status == RecordStatus.deleted;

  String get productLabel => '$productId — $productName';

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'terminal_url': terminalUrl,
        'terminal_key': terminalKey,
        'product_id': productId,
        'product_name': productName,
        'file_name': fileName,
        'codes_count': codesCount,
        'http_status': httpStatus,
        'status': status,
        'uploaded_at': uploadedAt.toIso8601String(),
        'deleted_at': deletedAt?.toIso8601String(),
      };

  factory UploadRecord.fromMap(Map<String, Object?> map) => UploadRecord(
        id: map['id'] as int,
        terminalUrl: map['terminal_url'] as String,
        terminalKey: map['terminal_key'] as String,
        productId: map['product_id'] as int,
        productName: map['product_name'] as String,
        fileName: map['file_name'] as String,
        codesCount: map['codes_count'] as int,
        httpStatus: map['http_status'] as int,
        status: map['status'] as String,
        uploadedAt: DateTime.parse(map['uploaded_at'] as String),
        deletedAt: map['deleted_at'] == null
            ? null
            : DateTime.parse(map['deleted_at'] as String),
      );
}
