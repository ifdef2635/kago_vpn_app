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
; force: в тихом режиме (обновление из приложения) занятый файл иначе
; означал бы «Прервать» и откат установки.
CloseApplications=force
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

function FindWindowW(lpClassName, lpWindowName: String): HWND;
  external 'FindWindowW@user32.dll stdcall';
function RegisterWindowMessageW(lpString: String): Longint;
  external 'RegisterWindowMessageW@user32.dll stdcall';

// Приложение живёт в трее (закрытие окна его не завершает). Сначала просим
// его выйти, как из меню трея: оно остановит ядро и вернёт системный прокси,
// TUN и часовой пояс. Если не вышло за 12 с — завершаем принудительно.
procedure QuitApp;
var
  Wnd: HWND;
  Waited, Code: Integer;
begin
  Wnd := FindWindowW('FLUTTER_RUNNER_WIN32_WINDOW', 'KaGo VPN');
  if Wnd <> 0 then
  begin
    PostMessage(Wnd, RegisterWindowMessageW('KaGoVPN.Quit'), 0, 0);
    Waited := 0;
    while (Waited < 12000) and (FindWindowW('FLUTTER_RUNNER_WIN32_WINDOW', 'KaGo VPN') <> 0) do
    begin
      Sleep(250);
      Waited := Waited + 250;
    end;
  end;
  // Обновление из приложения: старая версия могла не завершиться (зависнуть
  // при выходе) и держать свои файлы — тогда тихая установка откатывалась.
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/F /IM kago_vpn.exe', '', SW_HIDE,
    ewWaitUntilTerminated, Code);
  if Code = 0 then
    Sleep(800);
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  QuitApp;
  Result := '';
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  Code: Integer;
begin
  if CurUninstallStep = usUninstall then
  begin
    FullCleanup := (not UninstallSilent) and
      (MsgBox(CustomMessage('FullCleanup'), mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDYES);
    QuitApp;
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
  // Режим TUN (MihomoWindowsTun): задача планировщика с правами
  // администратора и ядро в Program Files. Задача запускает ядро без запроса,
  // поэтому убирается при любом удалении; Windows спросит разрешение.
  if (CurUninstallStep = usPostUninstall) and DirExists(ExpandConstant('{commonpf64}\KaGo VPN Core')) then
    ShellExec('runas', ExpandConstant('{cmd}'),
      '/c schtasks /delete /tn "\KaGo VPN\KaGo VPN TUN" /f & rmdir /s /q "' +
      ExpandConstant('{commonpf64}\KaGo VPN Core') + '"',
      '', SW_HIDE, ewWaitUntilTerminated, Code);
end;
