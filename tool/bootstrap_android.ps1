$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $projectRoot

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
  throw 'Flutter SDK не найден в PATH.'
}

$androidRoot = Join-Path $projectRoot 'android'
$appRoot = Join-Path $androidRoot 'app'
$customRoot = Join-Path $appRoot 'src/main/kotlin/net/usekago/vpn'
$customFiles = @('MainActivity.kt', 'MihomoNativeCore.kt', 'KaGoVpnService.kt')
$gradleKts = Join-Path $appRoot 'build.gradle.kts'
$gradleGroovy = Join-Path $appRoot 'build.gradle'
$hasRunner = (Test-Path $gradleKts) -or (Test-Path $gradleGroovy)

if (-not $hasRunner) {
  $stash = Join-Path $env:TEMP "kago-android-native-$PID"
  New-Item -ItemType Directory -Force -Path $stash | Out-Null
  foreach ($file in $customFiles) {
    $source = Join-Path $customRoot $file
    if (Test-Path $source) { Copy-Item $source (Join-Path $stash $file) -Force }
  }
  try {
    & flutter create --platforms=android --org net.usekago .
    if ($LASTEXITCODE -ne 0) { throw "flutter create завершился с кодом $LASTEXITCODE" }
  } finally {
    New-Item -ItemType Directory -Force -Path $customRoot | Out-Null
    foreach ($file in $customFiles) {
      $saved = Join-Path $stash $file
      if (Test-Path $saved) { Copy-Item $saved (Join-Path $customRoot $file) -Force }
    }
    Remove-Item $stash -Recurse -Force -ErrorAction SilentlyContinue
  }
}

if (Test-Path $gradleKts) {
  $gradleText = Get-Content $gradleKts -Raw
  $gradleText = [regex]::Replace($gradleText, '(?m)^(\s*namespace\s*=\s*)"[^"]+"', '$1"net.usekago.vpn"')
  $gradleText = [regex]::Replace($gradleText, '(?m)^(\s*applicationId\s*=\s*)"[^"]+"', '$1"net.usekago.vpn"')
  $gradleText = [regex]::Replace($gradleText, '(?m)^\s*signingConfig\s*=\s*signingConfigs\.getByName\("debug"\)\s*\r?\n', '')
  Set-Content -Path $gradleKts -Value $gradleText -NoNewline -Encoding utf8
} elseif (Test-Path $gradleGroovy) {
  $gradleText = Get-Content $gradleGroovy -Raw
  $gradleText = [regex]::Replace($gradleText, '(?m)^\s*namespace\s+["'']([^"'']+)["'']', '    namespace "net.usekago.vpn"')
  $gradleText = [regex]::Replace($gradleText, '(?m)^\s*applicationId\s+["'']([^"'']+)["'']', '        applicationId "net.usekago.vpn"')
  $gradleText = [regex]::Replace($gradleText, '(?m)^\s*signingConfig\s+signingConfigs\.debug\s*\r?\n', '')
  Set-Content -Path $gradleGroovy -Value $gradleText -NoNewline -Encoding utf8
}

$generatedActivityRoots = @(
  (Join-Path $appRoot 'src/main/kotlin/net/usekago/kago_vpn'),
  (Join-Path $appRoot 'src/main/kotlin/com/example/kago_vpn')
)
foreach ($generatedRoot in $generatedActivityRoots) {
  if (Test-Path $generatedRoot) { Remove-Item $generatedRoot -Recurse -Force }
}

$manifestPath = Join-Path $appRoot 'src/main/AndroidManifest.xml'
$document = New-Object System.Xml.XmlDocument
$document.PreserveWhitespace = $true
$document.Load($manifestPath)
$androidNs = 'http://schemas.android.com/apk/res/android'
$namespaces = New-Object System.Xml.XmlNamespaceManager($document.NameTable)
$namespaces.AddNamespace('android', $androidNs)

foreach ($permission in @(
  'android.permission.INTERNET',
  'android.permission.FOREGROUND_SERVICE',
  'android.permission.FOREGROUND_SERVICE_SYSTEM_EXEMPTED',
  'android.permission.POST_NOTIFICATIONS'
)) {
  $existing = $document.SelectSingleNode("/manifest/uses-permission[@android:name='$permission']", $namespaces)
  if ($null -eq $existing) {
    $node = $document.CreateElement('uses-permission')
    $node.SetAttribute('name', $androidNs, $permission)
    $applicationNode = $document.SelectSingleNode('/manifest/application')
    if ($null -eq $applicationNode) { throw 'В AndroidManifest не найден application node.' }
    [void]$document.DocumentElement.InsertBefore($node, $applicationNode)
  }
}

$application = $document.SelectSingleNode('/manifest/application')
if ($null -eq $application) { throw 'В AndroidManifest не найден application node.' }
$application.SetAttribute('label', $androidNs, 'KaGo VPN')
$application.SetAttribute('icon', $androidNs, '@mipmap/ic_launcher')
$application.SetAttribute('networkSecurityConfig', $androidNs, '@xml/network_security_config')
$application.SetAttribute('allowBackup', $androidNs, 'false')
$application.SetAttribute('name', $androidNs, '${applicationName}')

$mainActivity = $document.SelectSingleNode("/manifest/application/activity[intent-filter/action[@android:name='android.intent.action.MAIN']]", $namespaces)
if ($null -eq $mainActivity) { throw 'В AndroidManifest не найден launcher Activity.' }
$mainActivity.SetAttribute('name', $androidNs, 'net.usekago.vpn.MainActivity')

$service = $document.SelectSingleNode("/manifest/application/service[@android:name='net.usekago.vpn.KaGoVpnService']", $namespaces)
if ($null -eq $service) {
  $service = $document.CreateElement('service')
  $service.SetAttribute('name', $androidNs, 'net.usekago.vpn.KaGoVpnService')
  $service.SetAttribute('permission', $androidNs, 'android.permission.BIND_VPN_SERVICE')
  $service.SetAttribute('exported', $androidNs, 'true')
  $service.SetAttribute('foregroundServiceType', $androidNs, 'systemExempted')
  $service.SetAttribute('stopWithTask', $androidNs, 'false')
  $filter = $document.CreateElement('intent-filter')
  $action = $document.CreateElement('action')
  $action.SetAttribute('name', $androidNs, 'android.net.VpnService')
  [void]$filter.AppendChild($action)
  [void]$service.AppendChild($filter)
  [void]$application.AppendChild($service)
}
$document.Save($manifestPath)

& flutter pub get
if ($LASTEXITCODE -ne 0) { throw "flutter pub get завершился с кодом $LASTEXITCODE" }
Write-Host 'Android Gradle runner готов. Для release задайте production signing config; native Go/JNI .so и device tests ещё обязательны.' -ForegroundColor Green
