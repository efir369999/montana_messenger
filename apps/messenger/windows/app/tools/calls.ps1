# A CALL, LIVE (after tools\ab.ps1 with the same -Root): A calls B by voice; B's window rings by the ring letter, B accepts,
# both sides connect (WebRTC through Montana's lane and TURN) and the timer runs; A hangs up, B sees the call end; the log
# holds the call on both sides.
# usage: tools\calls.ps1 -Root DIR [-Shots DIR]
param([Parameter(Mandatory = $true)][string]$Root, [string]$Shots = "")
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ui.ps1"
function Snap($name) { if ($Shots) { Shot-Montana (Join-Path $Shots "$name.png") } }
function Says([string]$text, [int]$timeout = 60) { Find-Named $text $timeout | Out-Null; "  sees: $text" }
$t0 = Get-Date
$B = Start-Montana -DataDir "$Root\B"; Front-Montana -X 920 -Y 40 -Width 900 -Height 900
Start-Sleep -Seconds 2
$A = Start-Montana -DataDir "$Root\A"; Front-Montana -X 0 -Y 40 -Width 900 -Height 900
Start-Sleep -Seconds 2
"A calls B"
Click-Named "Борис Тест"; Click-Named "Позвонить"; Click-Named "Аудиозвонок"
Says "Аудиовызов Montana" 10
Snap "33-A-calling"
"B rings"
Use-Montana $B
Says "Принять" 60
Snap "34-B-ringing"
Click-Named "Принять"
"both talk"
$deadline = (Get-Date).AddSeconds(40); $talking = $false
while (-not $talking -and (Get-Date) -lt $deadline) {
    if ((Call-Timer) -ge 1) { $talking = $true } else { Start-Sleep -Milliseconds 500 }
}
if (-not $talking) { throw "B never connected" }
"  B: the timer runs"
Use-Montana $A
$deadline = (Get-Date).AddSeconds(20); $talking = $false
while (-not $talking -and (Get-Date) -lt $deadline) {
    if ((Call-Timer) -ge 1) { $talking = $true } else { Start-Sleep -Milliseconds 500 }
}
if (-not $talking) { throw "A never connected" }
"  A: the timer runs"
Start-Sleep -Seconds 3
Snap "35-A-talking"
"A folds the call into the app (iOS fold): the back mark, then the pill brings it back; the voice goes on"
Click-In "Аудиовызов Montana" "Назад"   # the call's own back mark, not a page's under it
Says "Отбой" 5   # the pill's red round
Gone-Named "Выкл. звук" 5   # the call's own keys left the screen
Snap "35b-A-folded"
Click-Named "Аудиовызов Montana"
Says "Выкл. звук" 5
"  the call folded and came back"
Click-Named "Отбой"
Use-Montana $B
Says "Звонок завершён" 30
"done in $([int]((Get-Date) - $t0).TotalSeconds) s"
Use-Montana $A; Stop-Montana; Use-Montana $B; Stop-Montana
