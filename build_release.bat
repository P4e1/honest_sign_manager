@echo off
setlocal EnableExtensions
cd /d "%~dp0"

echo ============================================
echo   Honest Sign Manager - build script v3
echo ============================================
echo.

where flutter >nul 2>&1
if errorlevel 1 goto :noflutter

echo [1/6] Clean...
call flutter clean
if errorlevel 1 goto :fail

echo [2/6] Dependencies...
call flutter pub get
if errorlevel 1 goto :fail

echo [3/6] Analyze...
call flutter analyze --no-fatal-infos --no-fatal-warnings
if errorlevel 1 goto :analyzefail

echo [4/6] Tests...
call flutter test --timeout 90s
if errorlevel 1 goto :fail

echo [5/6] Building release. This takes a few minutes, do not interrupt.
call flutter build windows --release
if errorlevel 1 goto :fail

echo [6/6] Preparing portable folder...
if not exist "build\windows\x64\runner\Release\honest_sign_manager.exe" goto :noexe

if exist dist rmdir /s /q dist
mkdir "dist\HonestSignManager"
xcopy /e /i /y /q "build\windows\x64\runner\Release\*" "dist\HonestSignManager\" >nul
if errorlevel 1 goto :fail

echo Packing zip...
powershell -NoProfile -ExecutionPolicy Bypass -Command "if (Test-Path 'dist\HonestSignManager_portable.zip') { Remove-Item -LiteralPath 'dist\HonestSignManager_portable.zip' -Force -ErrorAction SilentlyContinue }; Compress-Archive -Path 'dist\HonestSignManager\*' -DestinationPath 'dist\HonestSignManager_portable.zip' -Force -ErrorAction Stop"
if errorlevel 1 goto :ziperror

echo.
echo ============================================
echo  BUILD OK
echo ============================================
echo  App: dist\HonestSignManager\honest_sign_manager.exe
echo  Zip: dist\HonestSignManager_portable.zip
echo.
echo  Copy the WHOLE HonestSignManager folder:
echo  flutter_windows.dll and the data folder must be next to the exe.
echo.
pause
exit /b 0

:noflutter
echo.
echo [ERROR] Flutter is not in PATH.
echo Open the project folder in VS Code, then run .\build_release.bat
pause
exit /b 1

:analyzefail
echo.
echo [ERROR] The analyzer found real errors in the code.
echo Look for lines containing the word error in the output above.
pause
exit /b 1

:noexe
echo.
echo [ERROR] Build finished but the exe was not found.
echo Expected: build\windows\x64\runner\Release\honest_sign_manager.exe
pause
exit /b 1

:ziperror
echo.
echo [ERROR] The folder was built but the zip could not be created.
echo This is usually a locked file. Close Excel or Explorer showing that folder,
echo delete the dist folder manually, and run the script again.
echo Your app is ready here: dist\HonestSignManager
pause
exit /b 1

:fail
echo.
echo ============================================
echo  ERROR at the step above.
echo  Copy the last lines of the output and send them.
echo ============================================
pause
exit /b 1
