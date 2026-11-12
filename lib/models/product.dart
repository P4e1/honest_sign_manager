/// Товар из справочника (ID + наименование).
class Product {
  final int id;
  final String name;

  /// Служебные позиции: «#удалено#», «###удален###», «#дубликат#».
  /// По умолчанию скрываются из списка выбора.
  final bool isHidden;

  const Product({
    required this.id,
    required this.name,
    this.isHidden = false,
  });

  /// Строка для отображения в списках: «77 — Колбаса Ливерная «Нежная»».
  String get label => '$id — $name';

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'hidden': isHidden ? 1 : 0,
      };

  factory Product.fromMap(Map<String, Object?> map) => Product(
        id: map['id'] as int,
        name: map['name'] as String,
        isHidden: ((map['hidden'] as int?) ?? 0) == 1,
      );

  @override
  bool operator ==(Object other) => other is Product && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => label;
}
