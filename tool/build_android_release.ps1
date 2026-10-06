$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $ProjectRoot

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw 'Flutter is not on PATH. Install Flutter stable and Android Studio/SDK first.'
}

& (Join-Path $PSScriptRoot 'build_android_native.ps1')
if ($LASTEXITCODE -ne 0) { throw 'Android native-core build failed.' }
& flutter pub get
if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed.' }
& flutter analyze
if ($LASTEXITCODE -ne 0) { throw 'flutter analyze failed.' }
& flutter test
if ($LASTEXITCODE -ne 0) { throw 'flutter test failed.' }

$hasSigning = $env:KAGO_ANDROID_KEYSTORE -and $env:KAGO_ANDROID_KEYSTORE_PASSWORD -and
    $env:KAGO_ANDROID_KEY_ALIAS -and $env:KAGO_ANDROID_KEY_PASSWORD
if (-not $hasSigning) {
    Write-Warning 'No upload-key environment variables found. Flutter will produce an unsigned release artifact; it cannot be distributed or uploaded until signed with your private upload key.'
}

& flutter build appbundle --release
if ($LASTEXITCODE -ne 0) { throw 'Android App Bundle release build failed.' }
& flutter build apk --release --target-platform android-arm64
if ($LASTEXITCODE -ne 0) { throw 'Android APK release build failed.' }

$Dist = Join-Path $ProjectRoot 'dist/android'
New-Item -ItemType Directory -Force -Path $Dist | Out-Null
Copy-Item -Force (Join-Path $ProjectRoot 'build/app/outputs/bundle/release/app-release.aab') (Join-Path $Dist 'KaGoVPN-Android-release.aab')
Copy-Item -Force (Join-Path $ProjectRoot 'build/app/outputs/flutter-apk/app-release.apk') (Join-Path $Dist 'KaGoVPN-Android-release.apk')
Write-Host "Android release artifacts copied to $Dist"
