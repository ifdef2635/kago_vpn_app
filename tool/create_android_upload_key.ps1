$ErrorActionPreference = 'Stop'
if (-not (Get-Command keytool -ErrorAction SilentlyContinue)) {
    throw 'keytool was not found. Install a JDK (not only a JRE) and add its bin directory to PATH.'
}
$KeyDirectory = Join-Path $env:USERPROFILE '.android'
New-Item -ItemType Directory -Force -Path $KeyDirectory | Out-Null
$Keystore = Join-Path $KeyDirectory 'kago-vpn-upload.jks'
if (Test-Path $Keystore) {
    throw "Refusing to overwrite an existing upload key: $Keystore. Back it up and choose a different filename if needed."
}
$Alias = Read-Host 'Choose an upload-key alias (default: kago-upload)'
if ([string]::IsNullOrWhiteSpace($Alias)) { $Alias = 'kago-upload' }
Write-Host 'keytool will prompt for the keystore password, key password and certificate details. Do not commit or share the generated key.'
& keytool -genkeypair -v -keystore $Keystore -alias $Alias -keyalg RSA -keysize 4096 -validity 10000
if ($LASTEXITCODE -ne 0) { throw 'keytool failed to create the upload key.' }
Write-Host "Created local upload key: $Keystore"
Write-Host 'Before running build_android_release.ps1, set KAGO_ANDROID_KEYSTORE, KAGO_ANDROID_KEYSTORE_PASSWORD, KAGO_ANDROID_KEY_ALIAS, and KAGO_ANDROID_KEY_PASSWORD in the current PowerShell session. Keep passwords out of source files and chat.'
