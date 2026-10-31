# Инструкция по началу работы

## Шаг 1. Распаковка архива

Распакуйте `honest_sign_manager_lib.zip` в папку вашего проекта Flutter. Должна получиться структура:

```
your_project/
├── lib/                     ← содержимое архива
│   ├── main.dart
│   ├── app.dart
│   ├── models/
│   ├── services/
│   ├── providers/
│   └── screens/
├── pubspec.yaml             ← из архива
└── README.md                ← из архива
```

## Шаг 2. Создание проекта Flutter (если его ещё нет)

Если это первый раз:

```bash
flutter create --platforms=windows honest_sign_manager
cd honest_sign_manager
```

## Шаг 3. Замена файлов

1. Скопируйте **весь содержимое папки `lib`** из архива в `lib/` вашего проекта.
2. Замените `pubspec.yaml` на версию из архива.
3. Скопируйте `README.md`.

## Шаг 4. Проверка окружения

```bash
# Убедитесь, что поддержка Windows включена
flutter config --enable-windows-desktop

# Проверьте, что всё на месте
flutter doctor
```

Ожидаемый вывод (для Windows):
```
✓ Flutter (версия N.N.N)
✓ Windows Version
✓ Android Studio
✗ Visual Studio         ← ВНИМАНИЕ: должен быть ✓
✓ VS Code
```

Если Visual Studio не установлена, скачайте и установите с компонентом **"Desktop development with C++"**.

## Шаг 5. Загрузка зависимостей

```bash
flutter pub get
```

## Шаг 6. Запуск приложения

**Режим отладки:**
```bash
flutter run -d windows
```

**Release-версия (exe-файл):**
```bash
flutter build windows --release
```

Exe будет в: `build/windows/runner/Release/honest_sign_manager.exe`

## Первая запустка

1. Перейдите на вкладку **"Настройки"**.
2. Введите токен авторизации терминала.
3. Нажмите **"Сохранить токен"**.
4. Загрузите список товаров через **"Импортировать список товаров"** (файл Excel).

## Возможные проблемы

### "Could not find a version that matches flutter_windows"

Решение: удалите `pubspec.lock` и заново запустите `flutter pub get`.

```bash
rm pubspec.lock
flutter pub get
```

### "Visual Studio is required"

Решение: скачайте Visual Studio 2022 Community и убедитесь, что при установке выбран компонент **"Desktop development with C++"**.

### "sqflite error: Cannot find native library"

Решение: это нормально. SQLite для Windows будет скачан при первом запуске.

## Структура кода

| Папка | Назначение |
|---|---|
| `models/` | Модели данных (Product, UploadRecord, MarkingCode) |
| `services/` | Логика: Excel, обработка кодов, API, БД, настройки |
| `providers/` | Состояние приложения (Riverpod/Provider) |
| `screens/` | UI: выгрузка, история, настройки |

## Главные файлы

- **main.dart** — инициализация, DI, настройка окна
- **app.dart** — навигация, три вкладки
- **upload_provider.dart** — логика выгрузки
- **terminal_api.dart** — HTTP-запросы на терминал
- **database_service.dart** — SQLite, сохранение истории

## Очередь работ (если нужны доработки)

- [ ] Загрузка списка товаров в выпадающее меню на экране выгрузки
- [ ] Кэширование терминала при проверке дублей
- [ ] Импорт кодов из многолистных Excel-файлов
- [ ] Экспорт истории в CSV/Excel
- [ ] Логи всех операций
- [ ] Темы (светлая/тёмная)

## Ссылки

- [Flutter документация](https://docs.flutter.dev/)
- [Provider для управления состоянием](https://pub.dev/packages/provider)
- [Dio для HTTP-запросов](https://pub.dev/packages/dio)
- [SQLite в Flutter](https://pub.dev/packages/sqflite_common_ffi)
