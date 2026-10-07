import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// "All traffic through VPN" on Windows: the core runs with administrator
/// rights and creates a TUN adapter (wintun, built into Mihomo), so UDP —
/// Discord and game voice, QUIC — and apps that ignore the system proxy go
/// through the VPN too. With the system proxy alone Discord joins a call but
/// its voice (UDP) goes around the VPN and nobody is heard.
///
/// Windows asks for administrator permission (UAC) at each connect. The
/// elevated part is a PowerShell script passed inline (-EncodedCommand, no
/// file a user program could swap):
///   - the core is copied to `%ProgramFiles%\KaGo VPN Core` (only
///     administrators can write there) and must have the pinned SHA-256;
///   - the config is read once, checked against the SHA-256 the app computed
///     after sanitizing it, and written next to the core — a user program
///     cannot change what the elevated core reads;
///   - the core stops when the app writes [stopFile], when the app process
///     ends, or by itself.
/// Without permission the app falls back to the system proxy.
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

  /// The app asks the elevated script to stop the core by creating this.
  static String stopFile(String userDir) => '$userDir\\tun-stop';

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
    required String userDir,
  }) async {
    final stop = File(stopFile(userDir));
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
  static Future<void> requestStop(String userDir) async {
    try {
      await File(stopFile(userDir)).writeAsString('stop', flush: true);
    } catch (_) {
      // The script also stops when the app exits.
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
