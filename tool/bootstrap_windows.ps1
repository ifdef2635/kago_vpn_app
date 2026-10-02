$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $projectRoot

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
  throw 'Flutter SDK не найден в PATH. Установите Flutter и повторите запуск.'
}

if ((Test-Path (Join-Path $projectRoot 'windows/CMakeLists.txt'))) {
  Write-Host 'Windows runner уже существует; генерация пропущена.' -ForegroundColor Yellow
} else {
  Write-Host 'Генерация официального Windows runner через flutter create...'
  & flutter create --platforms=windows .
  if ($LASTEXITCODE -ne 0) { throw "flutter create завершился с кодом $LASTEXITCODE" }
}

Write-Host 'Загрузка зависимостей...'
& flutter pub get
if ($LASTEXITCODE -ne 0) { throw "flutter pub get завершился с кодом $LASTEXITCODE" }

Write-Host ''
Write-Host 'Готово. Проверьте Visual Studio Desktop development with C++, затем выполните:' -ForegroundColor Green
Write-Host '  flutter doctor -v'
Write-Host '  flutter run -d windows'
