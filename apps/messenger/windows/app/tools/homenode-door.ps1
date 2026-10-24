# YOUR NODE FOR A CHECK (iOS Code/Node, carried by the app byte for byte in src-tauri\node): the door is started in WSL as the
# distribution's own user, under a folder of its own (nothing installed, no unit, no user of the system made -- install.sh's work
# is a machine the person owns), with a certificate it makes for itself as install.sh makes it, on 127.0.0.1:8463. Prints
# «pin <sha256>» -- the one trust the app keeps -- and the door's process id; -Stop ends it.
# usage: tools\homenode-door.ps1 [-Dir /tmp/montana-node-check] [-Stop]
param([string]$Dir = "/tmp/montana-node-check", [switch]$Stop)
$ErrorActionPreference = "Stop"
$distro = "Ubuntu-24.04"
$pidFile = Join-Path $env:TEMP "montana-node-check.pid"
if ($Stop) {
    if (Test-Path $pidFile) { $p = Get-Content $pidFile; Stop-Process -Id $p -Force -ErrorAction SilentlyContinue; Remove-Item $pidFile }
    wsl -d $distro -- bash -c "pkill -f 'montana-node-check-door[.]py' || true" | Out-Null   # [.]: the pattern does not name this very shell
    "stopped"
    return
}
$src = (Resolve-Path "$PSScriptRoot\..\src-tauri\node\montana-home-node.py").Path
$wslSrc = "/mnt/" + $src.Substring(0, 1).ToLower() + ($src.Substring(2) -replace '\\', '/')
$make = @"
set -e
mkdir -p $Dir/vault $Dir/tls $Dir/blobs
cp '$wslSrc' $Dir/montana-node-check-door.py
if [ ! -f $Dir/tls/key.pem ]; then
  (umask 077; openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 30 -keyout $Dir/tls/key.pem -out $Dir/tls/cert.pem -subj /CN=montana-node -addext subjectAltName=IP:127.0.0.1 2>/dev/null)
fi
openssl x509 -in $Dir/tls/cert.pem -noout -fingerprint -sha256
"@
$fp = (wsl -d $distro -- bash -c ($make -replace "`r", "")) | Where-Object { $_ -match 'Fingerprint=' } | Select-Object -Last 1
if (-not $fp) { throw "no certificate" }
$pin = (($fp -split '=', 2)[1] -replace ':', '').Trim().ToLower()
$run = "cd $Dir && VAULT_DIR=$Dir/vault VAULT_TLS_CERT=$Dir/tls/cert.pem VAULT_TLS_KEY=$Dir/tls/key.pem STORE_TLS_PORT=8463 STORE_DB=$Dir/tokens.db WAKE_BLOBS=$Dir/blobs MONTANA_CAPS=vault exec python3 $Dir/montana-node-check-door.py > $Dir/door.log 2>&1"
$p = Start-Process wsl -ArgumentList @("-d", $distro, "--", "bash", "-c", "`"$run`"") -WindowStyle Hidden -PassThru
Set-Content $pidFile $p.Id
for ($i = 0; $i -lt 40; $i++) {
    Start-Sleep -Milliseconds 250
    $log = wsl -d $distro -- bash -c "cat $Dir/door.log 2>/dev/null"
    if ($log -match 'tls port=8463') { break }
}
"pin $pin"
"door $($p.Id)"
