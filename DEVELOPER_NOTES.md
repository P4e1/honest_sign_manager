# Заметки разработчика

## Архитектура

### Слои

```
UI (screens/)
    ↓
State Management (providers/)
    ↓
Services (services/)
    ↓
Models (models/)
```

**Поток данных:**

1. **UI** вызывает методы `Provider`.
2. **Provider** использует `Services` для получения данных.
3. **Services** работают с `DatabaseService` и `TerminalApi`.
4. Результат сохраняется в БД и выводится в UI.

### Состояние (Provider)

- **UploadProvider** — состояние экрана выгрузки: коды, ошибки, статус загрузки.
- **HistoryProvider** — состояние экрана истории: фильтры, поиск, удаление.

Оба используют `ChangeNotifier` и `notifyListeners()` для обновления UI.

### База данных (SQLite)

**Таблицы:**

```sql
products
  id INTEGER PRIMARY KEY
  name TEXT
  isDeleted INTEGER

upload_records
  id TEXT PRIMARY KEY (UUID)
  terminalUrl TEXT
  terminalKey TEXT (IP:порт)
  productId INTEGER
  productName TEXT
  fileName TEXT
  codesCount INTEGER
  httpStatus INTEGER
  status TEXT ('Загружено' | 'Удалён')
  uploadedAt TEXT (ISO 8601)
  deletedAt TEXT
  responseCodes TEXT (разделены ||)

codes
  recordId TEXT (FOREIGN KEY)
  raw TEXT
  base64 TEXT
  terminalKey TEXT
  type TEXT
  status TEXT
  createdAt TEXT
```

**Индексы:** для быстрого поиска дублей на терминале.

## Ключевые моменты

### Обработка кодов

1. Excel читается целиком в память: `openpyxl` → столбец B → список строк.
2. Коды валидируются: `01` + 14 цифр + `21` + серийный номер.
3. Внутри файла ищутся дубликаты: если код повторяется, второй исключается.
4. Оставшиеся коды кодируются в Base64 (UTF-8): `0104...5Se<Bg` → `MDEw...Bg=`.
5. Перед отправкой на терминал ищутся дубликаты в БД (по паре `termin_key + raw`).
6. Если дубликаты на терминале, показывается диалог: загрузить новые, загрузить все, отмена.

### API-взаимодействие

```dart
// Загрузка
POST /v1/honest-sign/codes/bulk
Authorization: Bearer <TOKEN>
{
  "bulk": [
    {"code": "MDEw...", "productId": 77}
  ]
}
→ 201 с массивом кодов

// Удаление
DELETE /v1/honest-sign/codes/delete/bulk
Authorization: Bearer <TOKEN>
{
  "codes": ["MDEw...", "MDEw..."]
}
→ 200 OK
```

### Токен

- Один для всех терминалов.
- Хранится в `SharedPreferences` (локально, в стиле реестра Windows).
- Видимость управляется переключателем глаза на экране настроек.
- Передаётся в каждом запросе заголовком `Authorization: Bearer <TOKEN>`.

### История и дубликаты

- Дубликаты проверяются **на том же терминале** (по IP:порту).
- История хранит **всю информацию**: адрес, товар, дату, коды, статус ответа.
- При удалении запись остаётся в истории со статусом "Удалён".
- Если загрузить те же коды на другой терминал, дубликат не сработает.

## Тестирование

### Unit-тесты (будущее)

```dart
test('Валидация кода', () {
  expect(CodeProcessor.isValidCodeFormat('0104697951542541215Se<Bg'), true);
  expect(CodeProcessor.isValidCodeFormat('invalid'), false);
});

test('Извлечение ключа терминала', () {
  expect(
    CodeProcessor.extractTerminalKey('http://192.168.1.82:4001/api'),
    '192.168.1.82:4001',
  );
});
```

### Интеграционные тесты

1. **Чтение Excel:** загрузить тестовый файл, проверить, что коды прочитаны.
2. **Обработка кодов:** валидация, дубликаты внутри файла.
3. **Проверка дублей:** загрузить, затем снова загрузить → диалог.
4. **API:** мок терминала или staging-окружение.
5. **БД:** вставка, чтение, поиск, фильтры.

### Ручное тестирование

1. Скачать тестовый Excel с кодами.
2. Выбрать файл и товар.
3. Ввести IP:порт терминала.
4. Нажать "Выгрузить" → проверить ответ.
5. Перейти в историю → проверить запись.
6. Загрузить то же заново → должен быть диалог о дубликатах.
7. Выбрать "Загрузить только новые" → должны загрузиться только новые.
8. В истории нажать "Удалить с терминала" → проверить изменение статуса.

## Развёртывание

### Сборка exe

```bash
flutter build windows --release --dart-define=flutter.buildMode=release
```

Выходной файл: `build/windows/runner/Release/honest_sign_manager.exe` (~100 МБ).

### Распространение

Можно упаковать с MSI-инсталлером через `msix_plus`, но сейчас это выходит за рамки задачи.

## Возможные расширения

1. **Поддержка macOS/Linux:** замена `window_manager` на кроссплатформенное решение.
2. **Экспорт истории:** CSV, Excel, JSON.
3. **Уведомления:** SystemTray, Desktop notifications.
4. **Логирование:** файл лога всех операций.
5. **Проверка подключения:** pingу терминала перед загрузкой.
6. **Импорт кодов из разных источников:** не только Excel, но и CSV, прямой ввод.
7. **Резервная копия БД:** ручная или автоматическая.

## Полезные команды

```bash
# Проверить зависимости
flutter doctor -v

# Очистить кэш
flutter clean

# Пересобрать native-часть
flutter pub get --no-example

# Запустить с логами
flutter run -d windows -v

# Профилирование
flutter run -d windows --profile

# Анализ кода
flutter analyze

# Форматирование
flutter format lib/
```

## Паттерны, использованные в коде

1. **Provider** — для управления состоянием UI.
2. **Factory Constructor** — для парсинга JSON в модели.
3. **Singleton** (quasi) — `DatabaseService`, `SettingsService`.
4. **Dependency Injection** — через `MultiProvider` в `main.dart`.
5. **Repository** — `DatabaseService` как репозиторий.

## Документирование кода

Все публичные методы должны иметь документирующие комментарии:

```dart
/// Проверяет формат кода ЧЗ.
/// 
/// Возвращает true, если код соответствует формату:
/// 01 + 14 цифр GTIN + 21 + серийный номер.
static bool isValidCodeFormat(String code) {
  // ...
}
```

## Версионирование

Текущая версия: **1.0.0+1** (в `pubspec.yaml`).

**Формат:** `MAJOR.MINOR.PATCH+BUILD`

- **MAJOR:** новые фичи (например, поддержка Linux).
- **MINOR:** расширение функциональности (например, экспорт в CSV).
- **PATCH:** исправления багов.
- **BUILD:** number для incremental builds.
