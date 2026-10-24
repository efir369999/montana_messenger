# THE PROTOCOL CORE FOR WINDOWS (iOS: core/Montana-Core/tools/build-for-a-telephone.sh): the boundary crate mt-boundary of
# core/Montana-Core, unchanged, built by app/protocol-core into montana_core.dll with the core's own toolchain (1.92.0) and two
# build tasks at a time (the core's own bound), then laid beside the program in target\release, where the installer takes it.
# usage: tools\protocol-core.ps1
$ErrorActionPreference = "Stop"
$root = Resolve-Path "$PSScriptRoot\..\.."
$target = Join-Path $root "target"
$env:CARGO_TARGET_DIR = Join-Path $target "protocol-core"
Push-Location (Join-Path $root "app\protocol-core")
try {
    cargo +1.92.0-x86_64-pc-windows-msvc build --release -j 2
    if ($LASTEXITCODE -ne 0) { throw "the protocol core did not build" }
} finally { Pop-Location }
$dll = Join-Path $env:CARGO_TARGET_DIR "release\montana_core.dll"
Copy-Item $dll (Join-Path $target "release\montana_core.dll") -Force
$h = (Get-FileHash $dll -Algorithm SHA256).Hash.ToLower()
"montana_core.dll $((Get-Item $dll).Length) bytes, SHA-256 $h"
