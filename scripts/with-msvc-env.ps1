# Imports the MSVC x64 build environment (LIB / INCLUDE / PATH) into the current
# PowerShell session, then runs whatever command is passed as arguments.
#
# Why: on Windows the default Rust toolchain is `*-pc-windows-msvc`, whose linker
# needs the Windows SDK import libs (kernel32.lib, ...) on LIB. A bare shell does
# not set these. We would normally call vcvars64.bat, but on this machine
# vswhere.exe is missing so vcvars leaves LIB empty. We therefore discover the
# MSVC + Windows SDK paths directly and build LIB/INCLUDE ourselves.
#
# Usage:
#     powershell -File scripts/with-msvc-env.ps1 cargo build --release
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Command
)
$ErrorActionPreference = 'Stop'

function Find-LatestDir($base) {
    Get-ChildItem $base -Directory -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending | Select-Object -First 1
}

# --- MSVC toolset ---
$vcRoots = @(
    "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Tools\MSVC",
    "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC",
    "C:\Program Files (x86)\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC"
)
$msvc = $null
foreach ($r in $vcRoots) { if (Test-Path $r) { $msvc = Find-LatestDir $r; break } }
if (-not $msvc) { throw "MSVC toolset not found" }

# --- Windows SDK ---
$sdkRoot = "C:\Program Files (x86)\Windows Kits\10"
$sdkLibBase = Join-Path $sdkRoot "Lib"
$sdkVer = (Find-LatestDir $sdkLibBase).Name
if (-not $sdkVer) { throw "Windows SDK not found under $sdkLibBase" }
$sdkIncBase = Join-Path $sdkRoot "Include\$sdkVer"

$libDirs = @(
    (Join-Path $msvc.FullName "lib\x64"),
    (Join-Path $sdkLibBase "$sdkVer\ucrt\x64"),
    (Join-Path $sdkLibBase "$sdkVer\um\x64")
)
$incDirs = @(
    (Join-Path $msvc.FullName "include"),
    (Join-Path $sdkIncBase "ucrt"),
    (Join-Path $sdkIncBase "shared"),
    (Join-Path $sdkIncBase "um")
)
$binDir = Join-Path $msvc.FullName "bin\Hostx64\x64"

$env:LIB = ($libDirs -join ';')
$env:INCLUDE = ($incDirs -join ';')
$env:PATH = "$binDir;$env:PATH"

# Ensure cargo is on PATH.
$cargoBin = Join-Path $env:USERPROFILE ".cargo\bin"
if (Test-Path $cargoBin) { $env:PATH = "$cargoBin;$env:PATH" }

if ($Command.Count -eq 0) {
    Write-Output "MSVC env ready (MSVC $($msvc.Name), SDK $sdkVer)."
    exit 0
}
& $Command[0] @($Command[1..($Command.Count - 1)])
exit $LASTEXITCODE
