; Установщик KaGo VPN для Windows x64 (Inno Setup 6).
; Файл в UTF-8 с BOM: иначе Inno Setup прочитает русские сообщения как ANSI.
; Сборка: iscc /DAppVersion=0.1.0 /DSourceDir=<папка Release> /DOutputDir=<папка> kago_vpn.iss
; Ставится для текущего пользователя (без прав администратора), как и ядро
; Mihomo в %APPDATA%\KaGo.

#ifndef AppVersion
  #define AppVersion "0.1.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\build\windows\x64\runner\Release"
#endif
#ifndef OutputDir
  #define OutputDir "..\..\dist"
#endif

[Setup]
AppId={{EC35115A-DDD4-4911-BE0A-D12EA7B530DD}
AppName=KaGo VPN
AppVersion={#AppVersion}
AppPublisher=KaGo VPN
AppPublisherURL=https://usekago.net
AppSupportURL=https://t.me/KaGoHelp
DefaultDirName={localappdata}\Programs\KaGo VPN
DefaultGroupName=KaGo VPN
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#OutputDir}
OutputBaseFilename=KaGoVPN-Windows-x64-Setup-{#AppVersion}
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\kago_vpn.exe
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
; Не ставить поверх работающего приложения: оно держит ядро и системный прокси.
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\KaGo VPN"; Filename: "{app}\kago_vpn.exe"
Name: "{group}\{cm:UninstallProgram,KaGo VPN}"; Filename: "{uninstallexe}"
Name: "{userdesktop}\KaGo VPN"; Filename: "{app}\kago_vpn.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\kago_vpn.exe"; Description: "{cm:LaunchProgram,KaGo VPN}"; Flags: nowait postinstall skipifsilent
; Обновление из приложения запускает установщик с /SILENT: после установки
; KaGo VPN открывается сам.
Filename: "{app}\kago_vpn.exe"; Flags: nowait; Check: WizardSilent

[CustomMessages]
russian.FullCleanup=Удалить также все данные KaGo VPN?%n%nБудут удалены ядро Mihomo, подписка, вход в аккаунт и настройки — полная очистка.%nНажмите «Нет», чтобы сохранить их для повторной установки.
english.FullCleanup=Also remove all KaGo VPN data?%n%nThe Mihomo core, subscription, sign-in and settings will be deleted (full cleanup).%nChoose "No" to keep them for a reinstall.

[UninstallDelete]
; Данные встроенного WebView2 (вход через Telegram) лежат рядом с exe.
Type: filesandordirs; Name: "{app}\kago_vpn.exe.WebView2"

[Code]
const
  ProxyKey = 'Software\Microsoft\Windows\CurrentVersion\Internet Settings';
  // MihomoWindowsSystemProxy.proxyServer
  KagoProxy = 'http=127.0.0.1:7890;https=127.0.0.1:7890;socks=127.0.0.1:7890';
  // Ключ шифрования flutter_secure_storage (подписка, вход) в диспетчере учётных данных.
  StorageCredential = 'key_kago_vpn_VGhpcyBpcyB0aGUgcHJlZml4IGZv_';

var
  FullCleanup: Boolean;

// Ядро Mihomo из %APPDATA%\KaGo, если оно осталось работать без приложения.
procedure StopCore;
var
  Code: Integer;
begin
  Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
    '-NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "' +
    '$d = [Environment]::GetFolderPath(''ApplicationData'') + ''\KaGo\''; ' +
    'Get-Process | Where-Object { $_.Path -and $_.Path.StartsWith($d, [StringComparison]::OrdinalIgnoreCase) } | Stop-Process -Force"',
    '', SW_HIDE, ewWaitUntilTerminated, Code);
end;

// Системный прокси KaGo без работающего ядра оставил бы компьютер без интернета.
procedure RestoreProxy;
var
  Server: String;
begin
  if RegQueryStringValue(HKCU, ProxyKey, 'ProxyServer', Server) and (Server = KagoProxy) then
  begin
    RegWriteDWordValue(HKCU, ProxyKey, 'ProxyEnable', 0);
    RegWriteStringValue(HKCU, ProxyKey, 'ProxyServer', '');
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  Code: Integer;
begin
  if CurUninstallStep = usUninstall then
  begin
    FullCleanup := (not UninstallSilent) and
      (MsgBox(CustomMessage('FullCleanup'), mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDYES);
    StopCore;
    RestoreProxy;
  end;
  if (CurUninstallStep = usPostUninstall) and FullCleanup then
  begin
    DelTree(ExpandConstant('{userappdata}\KaGo'), True, True, True);
    DelTree(ExpandConstant('{userappdata}\KaGo VPN'), True, True, True);
    DelTree(ExpandConstant('{app}'), True, True, True);
    Exec(ExpandConstant('{sys}\cmdkey.exe'), '/delete:' + StorageCredential, '',
      SW_HIDE, ewWaitUntilTerminated, Code);
  end;
end;
