/// Статусы записи истории.
class RecordStatus {
  static const loaded = 'Загружено';
  static const deleted = 'Удалён';

  /// Коды сняты с терминала во временный файл (изъятие).
  /// Запись остаётся в истории, коды можно вернуть.
  static const withdrawn = 'Изъят';
}

/// Запись истории = одна выгрузка файла на терминал.
class UploadRecord {
  final int? id;

  /// Глобальный уникальный ID для файлового хранилища.
  /// Формат: 20261026-081500-4f2a
  final String storeId;

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

  /// Кто выгрузил: «пользователь@компьютер».
  final String author;

  /// Запись ещё не записана на файловый сервер (лежит только в локальном кеше).
  final bool pendingRecord;

  /// Отметка об удалении ещё не записана на файловый сервер.
  final bool pendingTombstone;

  const UploadRecord({
    this.id,
    required this.storeId,
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
    this.author = '',
    this.pendingRecord = false,
    this.pendingTombstone = false,
  });

  /// Есть изменения, которые ещё не попали на файловый сервер.
  bool get isPending => pendingRecord || pendingTombstone;

  bool get isLoaded => status == RecordStatus.loaded;
  bool get isDeleted => status == RecordStatus.deleted;
  bool get isWithdrawn => status == RecordStatus.withdrawn;

  /// Коды записи лежат в файле изъятия, а не на терминале.
  bool get isOffTerminal => isWithdrawn || isDeleted;

  String get productLabel => '$productId — $productName';

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'store_id': storeId,
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
        'author': author,
        'pending_record': pendingRecord ? 1 : 0,
        'pending_tombstone': pendingTombstone ? 1 : 0,
      };

  factory UploadRecord.fromMap(Map<String, Object?> map) => UploadRecord(
        id: map['id'] as int?,
        storeId: map['store_id'] as String,
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
        author: (map['author'] as String?) ?? '',
        pendingRecord: ((map['pending_record'] as int?) ?? 0) == 1,
        pendingTombstone: ((map['pending_tombstone'] as int?) ?? 0) == 1,
      );
}
