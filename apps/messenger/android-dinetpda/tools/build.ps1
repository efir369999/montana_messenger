# Runs tools/wsl-build.sh inside WSL from Windows: powershell -File tools\build.ps1 <command> [args]
# The distribution is Ubuntu-24.04 unless MONTANA_WSL_DISTRO names another.
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest)
$ErrorActionPreference = 'Stop'
$distro = if ($env:MONTANA_WSL_DISTRO) { $env:MONTANA_WSL_DISTRO } else { 'Ubuntu-24.04' }
$script = Join-Path $PSScriptRoot 'wsl-build.sh'
# --exec runs bash directly: no second shell re-reads the arguments
$linux = (& wsl.exe -d $distro --exec wslpath -a $script | Out-String).Trim()
& wsl.exe -d $distro --exec bash $linux @Rest
exit $LASTEXITCODE
