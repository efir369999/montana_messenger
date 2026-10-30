# THE OTHER CAMERA IN A VIDEO CALL (iOS switchCamera; after tools\ab.ps1 with the same -Root): A runs with two of WebView2's own
# drawn cameras (nothing of this computer is opened), B with the test devices; A calls B by video, B answers; A's call screen shows
# «Сменить камеру» -- only because A has two cameras: B, with one, has no such key -- and the switch moves A's picture to the
# other camera on the same lane, the call going on (A's diary names the switch).
# usage: tools\callflip.ps1 -Root DIR [-Shots DIR]
param([Parameter(Mandatory = $true)][string]$Root, [string]$Shots = "")
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ui.ps1"
function Snap($name) { if ($Shots) { Shot-Montana (Join-Path $Shots "$name.png") } }
function Says([string]$text, [int]$timeout = 60) { Find-Named $text $timeout | Out-Null; "  sees: $text" }
function Diary([string]$who) { @(Get-Content "$Root\$who\trace.log" -Encoding UTF8 -ErrorAction SilentlyContinue) }
function Wrote([string]$who, [string]$line, [int]$timeout = 20) {
    $end = (Get-Date).AddSeconds($timeout)
    do { $hit = Diary $who | Where-Object { $_ -like "* call $line*" } | Select-Object -Last 1; if ($hit) { "  ${who}: $($hit -replace '^\d+ call ', '')"; return }; Start-Sleep -Milliseconds 500 } while ((Get-Date) -lt $end)
    throw "${who} never wrote '$line'"
}
$env:MONTANA_TRACE = "1"
foreach ($w in @("A", "B")) { Remove-Item "$Root\$w\trace.log" -ErrorAction SilentlyContinue }
$t0 = Get-Date
$B = Start-Montana -DataDir "$Root\B" -FakeMedia; Front-Montana -X 920 -Y 40 -Width 900 -Height 900
Start-Sleep -Seconds 2
$A = Start-Montana -DataDir "$Root\A" -Cameras 2; Front-Montana -X 0 -Y 40 -Width 900 -Height 900
Start-Sleep -Seconds 2
"A calls B by video"
Click-Named "Борис Тест"; Click-Named "Позвонить"; Click-Named "Видеозвонок"
Use-Montana $B; Front-Montana
Says "Принять" 60
Click-Named "Принять"
$end = (Get-Date).AddSeconds(40)
while ((Get-Date) -lt $end -and (Call-Timer) -lt 1) { Start-Sleep -Milliseconds 500 }
if ((Call-Timer) -lt 1) { throw "the call never connected" }
if (Get-Texts | Where-Object { $_ -eq "Сменить камеру" }) { throw "B has one camera and still shows the switch" }
"  B: one camera, no switch"
Use-Montana $A; Front-Montana
Says "Сменить камеру" 20
Snap "118-A-flip"
Click-Named "Сменить камеру"
Wrote "A" "camera switched" 15
Start-Sleep -Seconds 2
if ((Call-Timer) -lt 1) { throw "the call ended with the switch" }
"  the call goes on after the switch"
Click-Named "Сменить камеру"
Wrote "A" "camera switched 2 -> 1" 15
Click-Named "Отбой"
"done in $([int]((Get-Date) - $t0).TotalSeconds) s"
Use-Montana $A; Stop-Montana; Use-Montana $B; Stop-Montana
