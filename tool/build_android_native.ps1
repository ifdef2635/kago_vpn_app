$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$SdkRoot = if ($env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT } else { $env:ANDROID_HOME }
$NdkRoot = if ($env:ANDROID_NDK_HOME) { $env:ANDROID_NDK_HOME } else { $env:ANDROID_NDK_ROOT }

if (-not $NdkRoot -and $SdkRoot -and (Test-Path (Join-Path $SdkRoot 'ndk'))) {
    $NdkRoot = Get-ChildItem (Join-Path $SdkRoot 'ndk') -Directory |
        Sort-Object { [version]$_.Name } -Descending |
        Select-Object -First 1 -ExpandProperty FullName
}
if (-not $NdkRoot -or -not (Test-Path (Join-Path $NdkRoot 'toolchains/llvm/prebuilt/windows-x86_64/bin'))) {
    throw 'Android NDK for Windows was not found. Install the NDK in Android Studio or set ANDROID_NDK_HOME.'
}
if (-not (Get-Command go -ErrorAction SilentlyContinue)) {
    throw 'Go is required to compile the bundled Mihomo core. Install the Go version declared in native/android/go.mod.'
}

$Toolchain = Join-Path $NdkRoot 'toolchains/llvm/prebuilt/windows-x86_64'
$CoreDir = Join-Path $ProjectRoot 'native/android'
$TempRoot = Join-Path $CoreDir 'build/android-native'
$OriginalPath = $env:Path
Push-Location $CoreDir
try {
    & go test ./...
    if ($LASTEXITCODE -ne 0) { throw 'Go core unit tests failed.' }

    $env:CGO_ENABLED = '1'
    $env:PATH = "$(Join-Path $Toolchain 'bin');$OriginalPath"
    $env:CC = 'clang.exe'
    $env:CXX = 'clang++.exe'

    $targets = @(
        @{ Abi = 'arm64-v8a'; Arch = 'arm64'; Triple = 'aarch64-linux-android' },
        @{ Abi = 'x86_64'; Arch = 'amd64'; Triple = 'x86_64-linux-android' }
    )
    foreach ($target in $targets) {
        $env:GOOS = 'android'
        $env:GOARCH = $target.Arch
        $targetFlags = "--target=$($target.Triple)21 --sysroot=$(Join-Path $Toolchain 'sysroot')"
        $env:CGO_CFLAGS = $targetFlags
        $env:CGO_CXXFLAGS = $targetFlags
        $env:CGO_LDFLAGS = "$targetFlags -llog -landroid -lc++_shared"
        $libcxx = Join-Path $Toolchain "sysroot/usr/lib/$($target.Triple)/libc++_shared.so"
        if (-not (Test-Path $env:CC) -or -not (Test-Path $env:CXX)) { throw "NDK compiler missing for $($target.Abi)." }
        if (-not (Test-Path $libcxx)) { throw "NDK libc++_shared.so missing for $($target.Abi)." }

        $abiTemp = Join-Path $TempRoot "$($target.Abi).tmp"
        $output = Join-Path $abiTemp 'libkago_mihomo_bridge.so'
        New-Item -ItemType Directory -Force -Path $abiTemp | Out-Null
        Write-Host "Building pinned Mihomo v1.19.32 for Android $($target.Abi)..."
        & go build -mod=readonly -buildmode=c-shared -tags cmfa `
            -ldflags '-X github.com/metacubex/mihomo/constant.Version=1.19.32 -s -w' `
            -o $output .
        if ($LASTEXITCODE -ne 0) { throw "Native Mihomo build failed for $($target.Abi)." }

        $jniDir = Join-Path $ProjectRoot "android/app/src/main/jniLibs/$($target.Abi)"
        New-Item -ItemType Directory -Force -Path $jniDir | Out-Null
        Copy-Item -Force $output (Join-Path $jniDir 'libkago_mihomo_bridge.so')
        Copy-Item -Force $libcxx (Join-Path $jniDir 'libc++_shared.so')
        Remove-Item -Recurse -Force $abiTemp
    }
} finally {
    $env:GOOS = $null
    $env:GOARCH = $null
    $env:CC = $null
    $env:CXX = $null
    $env:CGO_CFLAGS = $null
    $env:CGO_CXXFLAGS = $null
    $env:CGO_ENABLED = $null
    $env:CGO_LDFLAGS = $null
    $env:Path = $OriginalPath
    Pop-Location
}
Write-Host 'Android native Mihomo libraries installed in android/app/src/main/jniLibs/.'
