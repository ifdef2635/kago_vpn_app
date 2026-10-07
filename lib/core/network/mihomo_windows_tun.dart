import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'mihomo_windows_core_updater.dart';

/// "All traffic through VPN" on Windows: the core runs with administrator
/// rights and creates a TUN adapter (wintun, built into Mihomo), so UDP —
/// Discord and game voice, QUIC — and apps that ignore the system proxy go
/// through the VPN too. With the system proxy alone Discord joins a call but
/// its voice (UDP) goes around the VPN and nobody is heard.
///
/// Administrator permission is asked **once** ([install]): the core and a
/// small service script ([serviceScript]) go to `%ProgramFiles%\KaGo VPN Core`
/// (only administrators can write there) and a Task Scheduler task with the
/// highest privileges runs that script. Later connects start the task without
/// a prompt ([runService]). Any user program can start that task, so the
/// script trusts nothing it reads from the user's folder (`%APPDATA%\KaGo\tun`):
///   - it runs only the core with the pinned SHA-256;
///   - it refuses a config that names a listener or a file outside the core's
///     home, sets the clock, uses YAML tags or escapes that could hide such a
///     key (the same rules as the macOS `kago-tun` wrapper), lets other
///     machines in (`allow-lan`) or puts the controller anywhere but loopback;
///   - it copies the config next to the core, so it cannot change while read.
/// The core stops when the app creates the `stop` file, when the app process
/// ends, or by itself.
///
/// A Windows user without administrator rights gets the UAC prompt (with an
/// administrator's password) at each connect instead ([launch]). Without
/// permission the app falls back to the system proxy.
abstract final class MihomoWindowsTun {
  static const tunKey = 'kago.windows.tun';

  static Future<bool> enabled() async {
    try {
      return (await SharedPreferences.getInstance()).getBool(tunKey) ?? true;
    } catch (_) {
      return true;
    }
  }

  static Future<void> setEnabled(bool value) async =>
      (await SharedPreferences.getInstance()).setBool(tunKey, value);

  static String get _programFiles =>
      Platform.environment['ProgramW6432'] ??
      Platform.environment['ProgramFiles'] ??
      r'C:\Program Files';

  /// Root-only (administrators) home of the elevated core.
  static String get coreHome => '$_programFiles\\KaGo VPN Core';
  static String get logFile => '$coreHome\\run\\core.log';

  /// Where the app hands the elevated script its config, its process id and
  /// the stop request.
  static String get exchangeDir =>
      '${Platform.environment['APPDATA'] ?? ''}\\KaGo\\tun';
  static String get stopFile => '$exchangeDir\\stop';

  static const taskPath = r'\KaGo VPN\';
  static const taskName = 'KaGo VPN TUN';
  static String get serviceFile => '$coreHome\\kago-tun.ps1';

  /// TUN settings for the Windows core (in place).
  static void enableTun(Map<String, dynamic> config) {
    final value = config['tun'];
    final tun = value is Map<String, dynamic> ? value : <String, dynamic>{};
    tun['enable'] = true;
    // gVisor (built into the Windows core): no Windows Firewall prompt, as
    // the "system" stack would need for its local listener.
    tun['stack'] = 'gvisor';
    tun['auto-route'] = true;
    tun['auto-detect-interface'] = true;
    // Windows sends DNS on every adapter: only the TUN may answer.
    tun['strict-route'] = true;
    tun['dns-hijack'] = const <String>['any:53'];
    config['tun'] = tun;
  }

  static String sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

  static String _quote(String value) => "'${value.replaceAll("'", "''")}'";

  /// The elevated PowerShell script (Windows PowerShell 5.1).
  static String script({
    required String coreSource,
    required String coreSha256,
    required String configSource,
    required String configSha256,
    required String stopFile,
    required int parentPid,
  }) =>
      '''
\$ErrorActionPreference = 'Stop'
\$src = ${_quote(coreSource)}
\$coreHash = ${_quote(coreSha256.toLowerCase())}
\$cfgSrc = ${_quote(configSource)}
\$cfgHash = ${_quote(configSha256.toLowerCase())}
\$stop = ${_quote(stopFile)}
\$parent = $parentPid
\$root = Join-Path \$env:ProgramFiles 'KaGo VPN Core'
\$run = Join-Path \$root 'run'
\$exe = Join-Path \$root 'mihomo.exe'
function Get-Sha256([string]\$path) { (Get-FileHash -Algorithm SHA256 -LiteralPath \$path).Hash.ToLowerInvariant() }
New-Item -ItemType Directory -Force -Path \$run | Out-Null
Get-Process -ErrorAction SilentlyContinue | Where-Object { \$_.Path -eq \$exe } | Stop-Process -Force -ErrorAction SilentlyContinue
if (-not (Test-Path -LiteralPath \$exe) -or (Get-Sha256 \$exe) -ne \$coreHash) {
  Copy-Item -LiteralPath \$src -Destination "\$exe.new" -Force
  if ((Get-Sha256 "\$exe.new") -ne \$coreHash) { Remove-Item -LiteralPath "\$exe.new" -Force; exit 3 }
  Move-Item -LiteralPath "\$exe.new" -Destination \$exe -Force
}
\$bytes = [IO.File]::ReadAllBytes(\$cfgSrc)
\$sha = [Security.Cryptography.SHA256]::Create()
\$got = ([BitConverter]::ToString(\$sha.ComputeHash(\$bytes))).Replace('-', '').ToLowerInvariant()
if (\$got -ne \$cfgHash) { exit 4 }
\$cfg = Join-Path \$run 'config.yaml'
[IO.File]::WriteAllBytes(\$cfg, \$bytes)
\$log = Join-Path \$run 'core.log'
\$p = Start-Process -FilePath \$exe -ArgumentList @('-d', ('"' + \$run + '"'), '-f', ('"' + \$cfg + '"')) -NoNewWindow -PassThru -RedirectStandardOutput \$log -RedirectStandardError "\$log.err"
try {
  while (-not \$p.HasExited) {
    if (Test-Path -LiteralPath \$stop) { break }
    if (-not (Get-Process -Id \$parent -ErrorAction SilentlyContinue)) { break }
    Start-Sleep -Milliseconds 300
  }
} finally {
  if (-not \$p.HasExited) { Stop-Process -Id \$p.Id -Force -ErrorAction SilentlyContinue }
}
''';

  /// Arguments for a non-elevated powershell.exe that asks Windows to run
  /// [script] as administrator. Exit code 0: started; 1223: the user said no.
  static List<String> launcherArguments(String script) {
    final encoded = base64.encode(_utf16le(script));
    return <String>[
      '-NoProfile',
      '-NonInteractive',
      '-ExecutionPolicy',
      'Bypass',
      '-Command',
      "try { Start-Process -FilePath 'powershell.exe' -Verb RunAs "
          "-WindowStyle Hidden -ArgumentList '-NoProfile','-NonInteractive',"
          "'-ExecutionPolicy','Bypass','-WindowStyle','Hidden',"
          "'-EncodedCommand','$encoded'; exit 0 } catch { exit 1223 }",
    ];
  }

  static List<int> _utf16le(String text) {
    final out = <int>[];
    for (final unit in text.codeUnits) {
      out
        ..add(unit & 0xff)
        ..add(unit >> 8);
    }
    return out;
  }

  static String get _powershell {
    final root = Platform.environment['SystemRoot'] ?? r'C:\Windows';
    return '$root\\System32\\WindowsPowerShell\\v1.0\\powershell.exe';
  }

  /// Starts the elevated core. True if Windows started it, false if the
  /// user declined the permission.
  static Future<bool> launch({
    required String coreExecutable,
    required String coreSha256,
    required File config,
  }) async {
    await Directory(exchangeDir).create(recursive: true);
    final stop = File(stopFile);
    if (await stop.exists()) await stop.delete();
    final text = script(
      coreSource: coreExecutable,
      coreSha256: coreSha256,
      configSource: config.path,
      configSha256: sha256Hex(await config.readAsBytes()),
      stopFile: stop.path,
      parentPid: pid,
    );
    final result = await Process.run(_powershell, launcherArguments(text));
    return result.exitCode == 0;
  }

  /// Asks the elevated script to stop the core.
  static Future<void> requestStop() async {
    try {
      await File(stopFile).writeAsString('stop', flush: true);
    } catch (_) {
      // The script also stops when the app exits.
    }
  }

  /// Keys and constructs the elevated core must never get from a config
  /// (as in `macos/helper/kago_tun.c`, plus `tunnels`).
  static const forbidden = <String>[
    'external-controller-unix',
    'external-controller-pipe',
    'external-controller-tls',
    'external-ui',
    'external-doh-server',
    'write-to-system',
    'listeners',
    'tunnels',
    '!!',
    '!<',
    '%tag',
    'tag:yaml.org',
  ];

  /// PowerShell `Test-KagoConfig $text`: '' if the elevated core may get
  /// this config, otherwise why not.
  static String configCheckFunction() {
    final words = forbidden.map((word) => "'$word'").join(',');
    return '''
function Test-KagoConfig([string]\$text) {
  if (\$text.IndexOf([char]0) -ge 0) { return 'NUL' }
  foreach (\$m in [regex]::Matches(\$text, '\\\\(.)', 'Singleline')) {
    if ('\\"/nrtbf'.IndexOf([char]\$m.Groups[1].Value[0]) -lt 0) { return 'escape' }
  }
  foreach (\$word in @($words)) {
    if (\$text.IndexOf(\$word, [StringComparison]::OrdinalIgnoreCase) -ge 0) { return \$word }
  }
  if ([regex]::Matches(\$text, '"external-controller"\\s*:').Count -ne 1 -or -not [regex]::IsMatch(\$text, '"external-controller"\\s*:\\s*"(127\\.0\\.0\\.1|localhost|\\[::1\\]):[0-9]{1,5}"')) { return 'controller' }
  if ([regex]::IsMatch(\$text, '"allow-lan"\\s*:\\s*true')) { return 'allow-lan' }
  return ''
}
''';
  }

  /// The service script the scheduled task runs (ASCII, no parameters: it
  /// reads only `%APPDATA%\KaGo\tun`). The pinned core hash is built in, so
  /// a new core version means a new script and one new permission prompt.
  static String serviceScript(
      {String coreSha256 = MihomoPinnedCore.exeSha256Hex}) {
    return '''
\$ErrorActionPreference = 'Stop'
\$coreHash = '${coreSha256.toLowerCase()}'
\$root = Join-Path \$env:ProgramFiles 'KaGo VPN Core'
\$run = Join-Path \$root 'run'
\$exe = Join-Path \$root 'mihomo.exe'
\$dir = Join-Path \$env:APPDATA 'KaGo\\tun'
\$cfgSrc = Join-Path \$dir 'config.json'
\$pidFile = Join-Path \$dir 'pid'
\$stop = Join-Path \$dir 'stop'
New-Item -ItemType Directory -Force -Path \$run | Out-Null
\$status = Join-Path \$run 'service.log'
function Exit-Refused([string]\$why) { Set-Content -LiteralPath \$status -Value \$why -Encoding ASCII; exit 2 }
Set-Content -LiteralPath \$status -Value 'starting' -Encoding ASCII
if ((Get-FileHash -Algorithm SHA256 -LiteralPath \$exe).Hash.ToLowerInvariant() -ne \$coreHash) { Exit-Refused 'core hash mismatch' }
foreach (\$path in @(\$cfgSrc, \$pidFile)) {
  \$item = Get-Item -LiteralPath \$path -Force
  if (\$item.Attributes -band [IO.FileAttributes]::ReparsePoint) { Exit-Refused 'link refused' }
  if (\$item.Length -gt 16MB) { Exit-Refused 'file too large' }
}
${configCheckFunction()}\$parent = [int]([IO.File]::ReadAllText(\$pidFile).Trim())
\$bytes = [IO.File]::ReadAllBytes(\$cfgSrc)
\$text = [Text.Encoding]::UTF8.GetString(\$bytes)
\$refused = Test-KagoConfig \$text
if (\$refused) { Exit-Refused ('config refused: ' + \$refused) }
Get-Process -ErrorAction SilentlyContinue | Where-Object { \$_.Path -eq \$exe } | Stop-Process -Force -ErrorAction SilentlyContinue
\$cfg = Join-Path \$run 'config.yaml'
[IO.File]::WriteAllBytes(\$cfg, \$bytes)
\$log = Join-Path \$run 'core.log'
\$p = Start-Process -FilePath \$exe -ArgumentList @('-d', ('"' + \$run + '"'), '-f', ('"' + \$cfg + '"')) -NoNewWindow -PassThru -RedirectStandardOutput \$log -RedirectStandardError "\$log.err"
Set-Content -LiteralPath \$status -Value 'running' -Encoding ASCII
try {
  while (-not \$p.HasExited) {
    if (Test-Path -LiteralPath \$stop) { break }
    if (-not (Get-Process -Id \$parent -ErrorAction SilentlyContinue)) { break }
    Start-Sleep -Milliseconds 300
  }
} finally {
  if (-not \$p.HasExited) { Stop-Process -Id \$p.Id -Force -ErrorAction SilentlyContinue }
  Set-Content -LiteralPath \$status -Value 'stopped' -Encoding ASCII
}
''';
  }

  /// The one-time elevated setup: core and [serviceScript] into Program
  /// Files, and the scheduled task for [account] (DOMAIN\\user) with the
  /// highest privileges.
  static String setupScript({
    required String coreSource,
    required String coreSha256,
    required String account,
    required String service,
  }) =>
      '''
\$ErrorActionPreference = 'Stop'
\$src = ${_quote(coreSource)}
\$coreHash = ${_quote(coreSha256.toLowerCase())}
\$user = ${_quote(account)}
\$service = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('${base64.encode(utf8.encode(service))}'))
\$root = Join-Path \$env:ProgramFiles 'KaGo VPN Core'
\$run = Join-Path \$root 'run'
\$exe = Join-Path \$root 'mihomo.exe'
function Get-Sha256([string]\$path) { (Get-FileHash -Algorithm SHA256 -LiteralPath \$path).Hash.ToLowerInvariant() }
New-Item -ItemType Directory -Force -Path \$run | Out-Null
Get-Process -ErrorAction SilentlyContinue | Where-Object { \$_.Path -eq \$exe } | Stop-Process -Force -ErrorAction SilentlyContinue
if (-not (Test-Path -LiteralPath \$exe) -or (Get-Sha256 \$exe) -ne \$coreHash) {
  Copy-Item -LiteralPath \$src -Destination "\$exe.new" -Force
  if ((Get-Sha256 "\$exe.new") -ne \$coreHash) { Remove-Item -LiteralPath "\$exe.new" -Force; exit 3 }
  Move-Item -LiteralPath "\$exe.new" -Destination \$exe -Force
}
\$ps1 = Join-Path \$root 'kago-tun.ps1'
[IO.File]::WriteAllText(\$ps1, \$service, (New-Object Text.UTF8Encoding \$false))
\$shell = Join-Path \$env:SystemRoot 'System32\\WindowsPowerShell\\v1.0\\powershell.exe'
\$action = New-ScheduledTaskAction -Execute \$shell -Argument ('-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + \$ps1 + '"')
\$principal = New-ScheduledTaskPrincipal -UserId \$user -LogonType Interactive -RunLevel Highest
\$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances Queue
Register-ScheduledTask -TaskName '$taskName' -TaskPath '$taskPath' -Action \$action -Principal \$principal -Settings \$settings -Force | Out-Null
exit 0
''';

  /// Like [launcherArguments], but waits for the elevated script and returns
  /// its exit code (1223: the user said no).
  static List<String> waitingLauncherArguments(String script) {
    final encoded = base64.encode(_utf16le(script));
    return <String>[
      '-NoProfile',
      '-NonInteractive',
      '-ExecutionPolicy',
      'Bypass',
      '-Command',
      "try { \$p = Start-Process -FilePath 'powershell.exe' -Verb RunAs "
          "-WindowStyle Hidden -Wait -PassThru -ArgumentList '-NoProfile',"
          "'-NonInteractive','-ExecutionPolicy','Bypass','-WindowStyle','Hidden',"
          "'-EncodedCommand','$encoded'; exit \$p.ExitCode } catch { exit 1223 }",
    ];
  }

  /// The Windows user is an administrator (UAC can elevate without another
  /// account's password). Only then a highest-privileges task runs elevated.
  static Future<bool> isAdministrator() async {
    try {
      final result = await Process.run('whoami', const <String>['/groups']);
      return result.exitCode == 0 &&
          '${result.stdout}'.contains('S-1-5-32-544');
    } catch (_) {
      return false;
    }
  }

  /// The task and the current service script are installed.
  static Future<bool> isInstalled() async {
    try {
      final file = File(serviceFile);
      // The task itself is checked by starting it: runService fails
      // without it, and the app then installs again.
      return await file.exists() &&
          await file.readAsString() == serviceScript();
    } catch (_) {
      return false;
    }
  }

  /// Exit code of [install] when the user declined the prompt.
  static const declined = 1223;

  /// The one-time permission prompt: 0 when the task is ready, [declined],
  /// or another code when the setup failed.
  static Future<int> install({required String coreExecutable}) async {
    final domain = Platform.environment['USERDOMAIN'] ?? '';
    final user = Platform.environment['USERNAME'] ?? '';
    if (user.isEmpty) return 1;
    final text = setupScript(
      coreSource: coreExecutable,
      coreSha256: MihomoPinnedCore.exeSha256Hex,
      account: domain.isEmpty ? user : '$domain\\$user',
      service: serviceScript(),
    );
    final result =
        await Process.run(_powershell, waitingLauncherArguments(text));
    if (result.exitCode != 0) return result.exitCode;
    return await isInstalled() ? 0 : 1;
  }

  /// Hands [config] to the service and starts the task (no prompt).
  static Future<bool> runService(File config) async {
    final dir = Directory(exchangeDir);
    await dir.create(recursive: true);
    final stop = File(stopFile);
    if (await stop.exists()) await stop.delete();
    await File('${dir.path}\\pid').writeAsString('$pid', flush: true);
    await config.copy('${dir.path}\\config.json');
    final result = await Process.run(
        'schtasks', <String>['/run', '/tn', '$taskPath$taskName']);
    return result.exitCode == 0;
  }

  /// Waits (up to [timeout]) until the service script has finished, so the
  /// next start is not queued behind a script that is still exiting.
  static Future<void> awaitServiceStopped(
      {Duration timeout = const Duration(seconds: 3)}) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final status = await serviceStatus();
      if (status != 'running' && status != 'starting') return;
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
  }

  /// Why the service did not start the core (`run\\service.log`), if it says.
  static Future<String> serviceStatus() async {
    try {
      return (await File('$coreHome\\run\\service.log').readAsString()).trim();
    } catch (_) {
      return '';
    }
  }

  /// The last lines the elevated core wrote (for error messages).
  static Future<String> logTail({int lines = 12}) async {
    try {
      final text = await File(logFile).readAsLines();
      return text
          .skip(text.length > lines ? text.length - lines : 0)
          .join('\n');
    } catch (_) {
      return '';
    }
  }
}
