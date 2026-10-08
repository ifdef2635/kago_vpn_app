# Проверка трея Windows на собранном приложении (windows-release.yml, сборки
# веток): закрытие окна не завершает приложение, второй запуск показывает
# первое окно, а сообщение KaGoVPN.Quit (меню трея / установщик) завершает его
# без системного прокси, оставленного включённым.
param([string]$Exe = 'build\windows\x64\runner\Release\kago_vpn.exe')
$ErrorActionPreference = 'Stop'

Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class KagoWin {
  [DllImport("user32.dll", CharSet = CharSet.Unicode)]
  public static extern IntPtr FindWindow(string cls, string title);
  [DllImport("user32.dll")]
  public static extern bool PostMessage(IntPtr hwnd, uint msg, IntPtr w, IntPtr l);
  [DllImport("user32.dll")]
  public static extern bool IsWindowVisible(IntPtr hwnd);
  [DllImport("user32.dll")]
  public static extern bool IsIconic(IntPtr hwnd);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)]
  public static extern uint RegisterWindowMessage(string name);
}
'@

function Find-Kago { [KagoWin]::FindWindow('FLUTTER_RUNNER_WIN32_WINDOW', 'KaGo VPN') }
function Wait-Until([scriptblock]$Condition, [int]$Seconds, [string]$What) {
  $deadline = (Get-Date).AddSeconds($Seconds)
  while ((Get-Date) -lt $deadline) {
    if (& $Condition) { return }
    Start-Sleep -Milliseconds 250
  }
  throw "Не дождались: $What"
}
function Shown($hwnd) { [KagoWin]::IsWindowVisible($hwnd) -and -not [KagoWin]::IsIconic($hwnd) }

$exePath = (Resolve-Path $Exe).Path
Get-Process kago_vpn -ErrorAction SilentlyContinue | Stop-Process -Force
$app = Start-Process $exePath -PassThru
try {
  Wait-Until { (Find-Kago) -ne [IntPtr]::Zero } 60 'окно приложения'
  $hwnd = Find-Kago
  Wait-Until { Shown $hwnd } 60 'первый кадр (окно видно)'
  Start-Sleep -Seconds 3

  # 1. Закрытие окна (крестик / Alt+F4) прячет его в трей, приложение живо.
  [void][KagoWin]::PostMessage($hwnd, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)
  Start-Sleep -Seconds 3
  if ($app.HasExited) { throw 'WM_CLOSE завершил приложение' }
  if (Shown $hwnd) { throw 'WM_CLOSE не спрятал окно' }
  Write-Host 'OK: закрытие окна прячет его, приложение работает'

  # 2. Второй запуск не создаёт копию, а показывает первое окно.
  $second = Start-Process $exePath -PassThru
  if (-not $second.WaitForExit(15000)) { throw 'второй запуск не завершился' }
  Wait-Until { Shown $hwnd } 10 'окно после второго запуска'
  $count = @(Get-Process kago_vpn -ErrorAction SilentlyContinue).Count
  if ($count -ne 1) { throw "запущено копий: $count" }
  Write-Host 'OK: второй запуск показывает уже открытое окно'

  # 3. «Выход» (как из меню трея или из установщика) завершает приложение.
  $quit = [KagoWin]::RegisterWindowMessage('KaGoVPN.Quit')
  [void][KagoWin]::PostMessage($hwnd, $quit, [IntPtr]::Zero, [IntPtr]::Zero)
  if (-not $app.WaitForExit(15000)) { throw '«Выход» не завершил приложение за 15 с' }
  Write-Host "OK: «Выход» завершает приложение (код $($app.ExitCode))"

  $settings = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
  if ($settings.ProxyEnable -eq 1 -and "$($settings.ProxyServer)" -like '*127.0.0.1:7890*') {
    throw 'после выхода остался системный прокси KaGo'
  }
  Write-Host 'OK: системный прокси KaGo не оставлен'
} finally {
  Get-Process kago_vpn -ErrorAction SilentlyContinue | Stop-Process -Force
}
