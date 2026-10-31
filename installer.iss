; Установщик для Windows.
; 1) Сначала выполните build_release.bat  (появится dist\HonestSignManager)
; 2) Откройте этот файл в Inno Setup 6 (https://jrsoftware.org/isinfo.php)
; 3) Нажмите Build > Compile  ->  получится dist\HonestSignManager_Setup_1.0.0.exe

[Setup]
AppId={{6F1B2C7E-8D4A-4E2B-9C1F-5A3D7E9B0C42}
AppName=Коды ЧЗ — выгрузка на терминал
AppVersion=1.0.0
AppVerName=Коды ЧЗ 1.0.0
AppPublisher=SYNTX
DefaultDirName={autopf}\HonestSignManager
DefaultGroupName=Коды ЧЗ
DisableProgramGroupPage=yes
OutputDir=dist
OutputBaseFilename=HonestSignManager_Setup_1.0.0
SetupIconFile=windows\runner\resources\app_icon.ico
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\honest_sign_manager.exe
MinVersion=10.0

[Languages]
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"

[Tasks]
Name: "desktopicon"; Description: "Создать значок на рабочем столе"; GroupDescription: "Дополнительно:"

[Files]
Source: "dist\HonestSignManager\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{group}\Коды ЧЗ"; Filename: "{app}\honest_sign_manager.exe"
Name: "{group}\Удалить Коды ЧЗ"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Коды ЧЗ"; Filename: "{app}\honest_sign_manager.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\honest_sign_manager.exe"; Description: "Запустить Коды ЧЗ"; Flags: nowait postinstall skipifsilent
