; Установщик KaGo VPN для Windows x64 (Inno Setup 6).
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
