param([switch]$SkipTests)
$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $ProjectRoot

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw 'Flutter stable is not on PATH.'
}
& flutter pub get
if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed.' }
if (-not $SkipTests) {
    & dart format --output=none --set-exit-if-changed lib test
    if ($LASTEXITCODE -ne 0) { throw 'Dart format check failed.' }
    & flutter analyze
    if ($LASTEXITCODE -ne 0) { throw 'flutter analyze failed.' }
    & flutter test
    if ($LASTEXITCODE -ne 0) { throw 'flutter test failed.' }
}
& flutter build windows --release
if ($LASTEXITCODE -ne 0) { throw 'Windows release build failed.' }

$ReleaseDir = Join-Path $ProjectRoot 'build/windows/x64/runner/Release'
if (-not (Test-Path (Join-Path $ReleaseDir 'kago_vpn.exe'))) {
    throw "Flutter Windows release executable not found in $ReleaseDir"
}
$Dist = Join-Path $ProjectRoot 'dist/KaGoVPN-Windows-x64'
if (Test-Path $Dist) { Remove-Item -Recurse -Force $Dist }
New-Item -ItemType Directory -Force -Path $Dist | Out-Null
Copy-Item -Path (Join-Path $ReleaseDir '*') -Destination $Dist -Recurse -Force
Copy-Item (Join-Path $ProjectRoot 'README.md') $Dist
Copy-Item (Join-Path $ProjectRoot 'RELEASE_STATUS.md') $Dist
$Zip = Join-Path $ProjectRoot 'dist/KaGoVPN-Windows-x64.zip'
if (Test-Path $Zip) { Remove-Item -Force $Zip }
Compress-Archive -Path (Join-Path $Dist '*') -DestinationPath $Zip -CompressionLevel Optimal
Write-Host "Windows release package created: $Zip"
Write-Warning 'Windows artifacts are unsigned. Public distribution requires a code-signing certificate; the Mihomo core is downloaded and SHA-256 verified on first start.'
