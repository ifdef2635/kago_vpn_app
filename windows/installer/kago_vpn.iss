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

; «Интеллектуальное управление приложениями» (Smart App Control) Windows 11:
; без цифровой подписи приложение не запустится.
russian.SacInstruction=Windows не даст запустить KaGo VPN
russian.SacText=Включено «Интеллектуальное управление приложениями». Оно запускает только программы с цифровой подписью, а у KaGo VPN её пока нет, поэтому после установки приложение не откроется.%n%nЧтобы KaGo VPN работал, эту защиту нужно отключить. Она отключается для всех программ, а на некоторых версиях Windows включить её обратно можно только переустановкой системы.
russian.SacAuto=Отключить автоматически%nWindows попросит разрешение администратора
russian.SacManual=Отключу сам%nОткроются настройки «Безопасность Windows»
russian.SacSkip=Продолжить без отключения%nKaGo VPN не запустится
russian.SacManualHint=В открывшемся окне выберите «Параметры интеллектуального управления приложениями» и переключите защиту в положение «Выкл.».%n%nПосле этого нажмите «ОК».
russian.SacAutoDone=Защита отключена. Если KaGo VPN всё равно не запустится, перезагрузите компьютер.
russian.SacAutoFailed=Отключить автоматически не получилось: разрешение администратора не дано, или Windows не применила изменение.%n%nОтключите защиту вручную или перезагрузите компьютер и запустите установку снова.
russian.SacSkipConfirm=Продолжить установку с включённой защитой?%n%nKaGo VPN не запустится, пока она включена. Отключить её можно позже: «Безопасность Windows» → «Управление приложениями и браузером» → «Параметры интеллектуального управления приложениями».
english.SacInstruction=Windows will not let KaGo VPN start
english.SacText=Smart App Control is on. It only runs programs with a digital signature, and KaGo VPN does not have one yet, so the app will not open after installation.%n%nTo use KaGo VPN, turn this protection off. It is turned off for all programs, and on some Windows versions it can only be turned back on by reinstalling Windows.
english.SacAuto=Turn it off automatically%nWindows will ask for administrator permission
english.SacManual=I will turn it off myself%nOpens Windows Security settings
english.SacSkip=Continue without turning it off%nKaGo VPN will not start
english.SacManualHint=In the window that opens, choose "Smart App Control settings" and switch the protection to "Off".%n%nThen click OK.
english.SacAutoDone=The protection is off. If KaGo VPN still does not start, restart the computer.
english.SacAutoFailed=It could not be turned off automatically: administrator permission was not given, or Windows did not apply the change.%n%nTurn the protection off manually, or restart the computer and run the installer again.
english.SacSkipConfirm=Continue the installation with the protection on?%n%nKaGo VPN will not start while it is on. You can turn it off later: Windows Security > App & browser control > Smart App Control settings.

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

  // Состояние Smart App Control: 0 — выключено, 1 — включено, 2 — оценка
  // (Windows только наблюдает и ничего не блокирует).
  CiPolicyKey = 'SYSTEM\CurrentControlSet\Control\CI\Policy';
  CiPolicyValue = 'VerifiedAndReputablePolicyState';

var
  FullCleanup: Boolean;

function SmartAppControlOn: Boolean;
var
  State: Cardinal;
begin
  Result := RegQueryDWordValue(HKLM64, CiPolicyKey, CiPolicyValue, State) and (State = 1);
end;

// С правами администратора (UAC): записывает «выключено» и применяет
// политику через CiTool без перезагрузки (Windows 11 22H2+). True, если
// защита после этого выключена.
function DisableSmartAppControl: Boolean;
var
  Code: Integer;
begin
  ShellExec('runas', ExpandConstant('{cmd}'),
    '/c reg add "HKLM\' + CiPolicyKey + '" /v ' + CiPolicyValue + ' /t REG_DWORD /d 0 /f' +
    ' & if exist "%SystemRoot%\System32\CiTool.exe" "%SystemRoot%\System32\CiTool.exe" -r',
    '', SW_HIDE, ewWaitUntilTerminated, Code);
  Result := not SmartAppControlOn;
end;

// Без подписи приложение заблокирует «Интеллектуальное управление
// приложениями». Пока защита включена, установщик настойчиво предлагает её
// отключить; продолжить без этого можно только после подтверждения.
// Тихая установка (обновление из приложения) ничего не спрашивает.
procedure CheckSmartAppControl;
var
  Code: Integer;
  Buttons: TArrayOfString;
begin
  if WizardSilent then
    Exit;
  // Не литерал массива: строку, начинающуюся с «[», Inno Setup читает как
  // заголовок секции даже внутри [Code].
  SetArrayLength(Buttons, 3);
  Buttons[0] := CustomMessage('SacAuto');
  Buttons[1] := CustomMessage('SacManual');
  Buttons[2] := CustomMessage('SacSkip');
  while SmartAppControlOn do
  begin
    case TaskDialogMsgBox(CustomMessage('SacInstruction'), CustomMessage('SacText'),
      mbError, MB_YESNOCANCEL, Buttons, IDYES) of
      IDYES:
        if DisableSmartAppControl then
          MsgBox(CustomMessage('SacAutoDone'), mbInformation, MB_OK)
        else
          MsgBox(CustomMessage('SacAutoFailed'), mbError, MB_OK);
      IDNO:
        begin
          ShellExec('open', 'windowsdefender://appbrowser', '', '', SW_SHOWNORMAL,
            ewNoWait, Code);
          MsgBox(CustomMessage('SacManualHint'), mbInformation, MB_OK);
        end;
    else
      if MsgBox(CustomMessage('SacSkipConfirm'), mbConfirmation,
        MB_YESNO or MB_DEFBUTTON2) = IDYES then
        Exit;
    end;
  end;
end;

function InitializeSetup: Boolean;
begin
  CheckSmartAppControl;
  Result := True;
end;

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
