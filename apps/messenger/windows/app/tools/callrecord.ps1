# A CALL AND ITS RECORDING RULE, IN THE WINDOWS (after tools\ab.ps1 with the same -Root), on WebView2's test devices (a made-up
# microphone, no sound out). iOS 2304 (MTCallRecordingPolicy.mayRecord, the author's word 20.10.2026 20:2x MSK): a correspondent's
# recording switch -- off below level 7, as Access by level shows it -- holds against an equal or lower level; both throw-away
# people stand below it at the same level, so neither may record the other: «Записать» stands on neither call screen, and both
# sides burn the call's seconds (callRecorded: recorded by neither). The recording's own road (the notices, «Запись звонка» in the
# chat, the callee's copy kept here) wants a level of 7 and a person's consent; no switch of a test run lifts a level, so it is no
# part of this check any more.
# usage: tools\callrecord.ps1 -Root DIR [-Shots DIR]
param([Parameter(Mandatory = $true)][string]$Root, [string]$Shots = "")
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ui.ps1"
function Snap($name) { if ($Shots) { Shot-Montana (Join-Path $Shots "$name.png") } }
function Says([string]$text, [int]$timeout = 60) { Find-Named $text $timeout | Out-Null; "  sees: $text" }
function Talking([int]$timeout = 40) {
    $end = (Get-Date).AddSeconds($timeout)
    while ((Get-Date) -lt $end) { if ((Call-Timer) -ge 1) { return }; Start-Sleep -Milliseconds 500 }
    throw "the call never connected"
}
function NoRecord([string]$who) {
    if ((Get-Texts) -contains "Записать") { throw "${who} offers «Записать» against the other's switch" }
    "  ${who}: no «Записать» -- the other's switch holds"
}
function Burned([string]$who, [int]$timeout = 20) {
    $end = (Get-Date).AddSeconds($timeout)
    do {
        if (Get-Content "$Root\$who\trace.log" -Encoding UTF8 -ErrorAction SilentlyContinue | Where-Object { $_ -match "coins call=.* recording=false" }) { "  ${who}: the call's seconds burn"; return }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $end)
    throw "${who} never burned the call's seconds"
}
$t0 = Get-Date
$env:MONTANA_TRACE = "1"
foreach ($w in @("A", "B")) { Remove-Item "$Root\$w\trace.log" -ErrorAction SilentlyContinue }
$B = Start-Montana -DataDir "$Root\B" -FakeMedia; Front-Montana -X 920 -Y 40 -Width 900 -Height 900
Start-Sleep -Seconds 2
$A = Start-Montana -DataDir "$Root\A" -FakeMedia; Front-Montana -X 0 -Y 40 -Width 900 -Height 900
Start-Sleep -Seconds 2
"A calls B"
Click-Named "Борис Тест"; Click-Named "Позвонить"; Click-Named "Аудиозвонок"
Use-Montana $B; Front-Montana
Says "Принять" 60
Click-Named "Принять"
Talking 40
Start-Sleep -Seconds 3
NoRecord "B"
Use-Montana $A; Front-Montana
Talking 20
NoRecord "A"
Snap "92-A-no-record"
Burned "A"
Burned "B"
Click-Named "Отбой"
Use-Montana $B
Says "Звонок завершён" 30
"done in $([int]((Get-Date) - $t0).TotalSeconds) s"
Use-Montana $A; Stop-Montana; Use-Montana $B; Stop-Montana
