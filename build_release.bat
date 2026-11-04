@echo off
setlocal EnableExtensions
chcp 65001 >nul
cd /d "%~dp0"

echo ============================================
echo   Сборка Honest Sign Manager (Windows exe)
echo ============================================
echo.

where flutter >nul 2>&1
if errorlevel 1 (
    echo [ОШИБКА] Flutter не найден в PATH.
    echo Откройте этот файл через "Открыть с помощью ^> Visual Studio Code" нельзя,
    echo запускайте из терминала VS Code командой:  .\build_release.bat
    pause
    exit /b 1
)

echo [1/6] Очистка...
call flutter clean
if errorlevel 1 goto :fail

echo [2/6] Зависимости...
call flutter pub get
if errorlevel 1 goto :fail

echo [3/6] Проверка кода...
rem --no-fatal-infos / --no-fatal-warnings: замечания стиля (const, deprecated)
rem не должны останавливать сборку. Останавливают только настоящие ошибки.
call flutter analyze --no-fatal-infos --no-fatal-warnings
if errorlevel 1 goto :analyze_fail

echo [4/6] Тесты...
rem --concurrency: файлы идут параллельно, весь прогон ~15 секунд.
rem --timeout 60s: если какой-то тест зависнет, он упадёт через минуту,
rem а не будет держать сборку вечно.
call flutter test --concurrency=4 --timeout 60s
if errorlevel 1 goto :fail

echo [5/6] Сборка release (это займёт несколько минут)...
call flutter build windows --release
if errorlevel 1 goto :fail

echo [6/6] Подготовка папки для переноса...
set "OUT=build\windows\x64\runner\Release"
set "DIST=dist\HonestSignManager"
if not exist "%OUT%\honest_sign_manager.exe" (
    echo [ОШИБКА] Не найден %OUT%\honest_sign_manager.exe
    goto :fail
)
if exist dist rmdir /s /q dist
mkdir "%DIST%"
xcopy /e /i /y /q "%OUT%\*" "%DIST%\" >nul
if errorlevel 1 goto :fail

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "Compress-Archive -Path '%DIST%\*' -DestinationPath 'dist\HonestSignManager_portable.zip' -Force"
if errorlevel 1 goto :fail

echo.
echo ============================================
echo  ГОТОВО
echo ============================================
echo  Приложение:  dist\HonestSignManager\honest_sign_manager.exe
echo  Архив:       dist\HonestSignManager_portable.zip
echo.
echo  ВАЖНО: переносить нужно ВСЮ папку HonestSignManager целиком
echo  (рядом с exe лежат flutter_windows.dll и data\), иначе не запустится.
echo.
echo  Установщик: откройте installer.iss в Inno Setup 6 и нажмите Build ^> Compile.
echo.
pause
exit /b 0

:analyze_fail
echo.
echo ============================================
echo  ОШИБКА: анализатор нашёл ОШИБКИ в коде.
echo  Смотрите строки со словом "error" в выводе выше.
echo ============================================
pause
exit /b 1

:fail
echo.
echo ============================================
echo  ОШИБКА на шаге выше.
echo  Скопируйте последние строки вывода и пришлите их.
echo ============================================
pause
exit /b 1
