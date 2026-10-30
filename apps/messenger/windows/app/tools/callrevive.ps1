# A CALL OUTLIVES ITS PROCESS, LIVE (after tools\ab.ps1 with the same -Root), on WebView2's test devices (no microphone of this
# computer): A calls B, both talk; B's program is killed in the middle of the call -- A says «Восстановление связи…» and waits
# for it; B is started again and goes back into the call by itself (nothing rings on either side) -- the timers run at both;
# then the caller's program dies and comes back the same way; A hangs up and B sees the end.
# usage: tools\callrevive.ps1 -Root DIR [-Shots DIR]
param([Parameter(Mandatory = $true)][string]$Root, [string]$Shots = "")
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ui.ps1"
function Snap($name) { if ($Shots) { Shot-Montana (Join-Path $Shots "$name.png") } }
function Says([string]$text, [int]$timeout = 60) { Find-Named $text $timeout | Out-Null; "  sees: $text" }
function Talking([int]$timeout = 40) {
    $end = (Get-Date).AddSeconds($timeout)
    while ((Get-Date) -lt $end) { $s = Call-Timer; if ($s -ge 1) { return $s }; Start-Sleep -Milliseconds 500 }
    throw "the call never connected"
}
function Wrote([string]$who, [string]$line, [int]$timeout = 20) {
    $end = (Get-Date).AddSeconds($timeout)
    do {
        if (@(Get-Content "$Root\$who\trace.log" -Encoding UTF8 -ErrorAction SilentlyContinue) | Where-Object { $_ -like "* call $line*" }) { "  ${who}: $line"; return }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $end)
    throw "${who} never wrote '$line'"
}
$env:MONTANA_TRACE = "1"
foreach ($w in @("A", "B")) { Remove-Item "$Root\$w\trace.log" -ErrorAction SilentlyContinue }
$t0 = Get-Date
$B = Start-Montana -DataDir "$Root\B" -FakeMedia; Front-Montana -X 920 -Y 40 -Width 900 -Height 900
Start-Sleep -Seconds 2
$A = Start-Montana -DataDir "$Root\A" -FakeMedia; Front-Montana -X 0 -Y 40 -Width 900 -Height 900
Start-Sleep -Seconds 2
"A calls B by voice"
Click-Named "Борис Тест"; Click-Named "Позвонить"; Click-Named "Аудиозвонок"
Use-Montana $B; Front-Montana
Says "Принять" 60
Click-Named "Принять"
$null = Talking 40
Use-Montana $A; Front-Montana
$null = Talking 20
Start-Sleep -Seconds 7   # the call is on the disk by now (every five seconds)
"B's program dies in the call"
Use-Montana $B; Stop-Montana
Use-Montana $A
Says "Восстановление связи…" 40
Start-Sleep -Seconds 3
"B starts again and goes back in by itself"
$B = Start-Montana -DataDir "$Root\B" -FakeMedia -KeepCall; Front-Montana -X 920 -Y 40 -Width 900 -Height 900
Wrote "B" "rejoin held tx" 30
$sb = Talking 60
"  B: the timer runs again at ${sb} s"
Use-Montana $A; Front-Montana
$sa = Talking 40
"  A: the timer runs at ${sa} s"
if (Get-Texts | Where-Object { $_ -eq "Принять" }) { throw "a ring stands where the call went on" }
Snap "76-A-revived"
Start-Sleep -Seconds 7
"A's program dies in the call"
Stop-Montana
Use-Montana $B
Says "Восстановление связи…" 40
Start-Sleep -Seconds 3
"A starts again and goes back in"
$A = Start-Montana -DataDir "$Root\A" -FakeMedia -KeepCall; Front-Montana -X 0 -Y 40 -Width 900 -Height 900
Wrote "A" "rejoin held tx" 30
$sa = Talking 60
"  A: the timer runs again at ${sa} s"
Use-Montana $B; Front-Montana
$sb = Talking 40
"  B: the timer runs at ${sb} s"
Use-Montana $A; Front-Montana
Click-Named "Отбой"
Use-Montana $B
Says "Звонок завершён" 30
"done in $([int]((Get-Date) - $t0).TotalSeconds) s"
Use-Montana $A; Stop-Montana; Use-Montana $B; Stop-Montana
