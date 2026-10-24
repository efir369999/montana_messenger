# THE ROUTE CHANGES UNDER A CALL, LIVE (after tools\ab.ps1 with the same -Root): A calls B by voice and both talk; then the route
# A reaches the internet by changes (Wi-Fi to mobile: MONTANA_ROUTE_FILE stands for the profile Windows names) -- A binds the
# call's checks to the relays and asks for fresh ones (iOS requestRouteRelayRecovery), and the call goes on on both sides. With
# MONTANA_TRACE=1 A's trace.log says which road the call rides after it.
# usage: tools\callroute.ps1 -Root DIR
param([Parameter(Mandatory = $true)][string]$Root, [string]$Shots = "")
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ui.ps1"
function Says([string]$text, [int]$timeout = 60) { Find-Named $text $timeout | Out-Null; "  sees: $text" }
function Timer-Runs([int]$seconds) {
    $deadline = (Get-Date).AddSeconds($seconds)
    while ((Get-Date) -lt $deadline) {
        $t = Call-Timer
        if ($t -ge 0) { return $t }
        Start-Sleep -Milliseconds 500
    }
    -1
}
$t0 = Get-Date
$route = Join-Path $Root "route-A.txt"
Set-Content -Path $route -Value "w:first" -Encoding ASCII
$B = Start-Montana -DataDir "$Root\B"; Front-Montana -X 920 -Y 40 -Width 900 -Height 900
Start-Sleep -Seconds 2
$env:MONTANA_ROUTE_FILE = $route
$A = Start-Montana -DataDir "$Root\A"; Front-Montana -X 0 -Y 40 -Width 900 -Height 900
Remove-Item Env:MONTANA_ROUTE_FILE
Start-Sleep -Seconds 2
"A calls B"
Click-Named "Борис Тест"; Click-Named "Позвонить"; Click-Named "Аудиозвонок"
Use-Montana $B
Says "Принять" 60
Click-Named "Принять"
if ((Timer-Runs 40) -lt 0) { throw "B never connected" }
Use-Montana $A
if ((Timer-Runs 20) -lt 0) { throw "A never connected" }
"  both talk"
Start-Sleep -Seconds 4
"A's route changes"
Set-Content -Path $route -Value "c:second" -Encoding ASCII
Start-Sleep -Seconds 18
$a1 = Timer-Runs 10
Start-Sleep -Seconds 3
$a2 = Timer-Runs 5
if ($a1 -lt 0 -or $a2 -le $a1) { throw "A's call did not go on ($a1 -> $a2)" }
"  A: the timer runs ($a1 s -> $a2 s)"
Use-Montana $B
$b1 = Timer-Runs 10
if ($b1 -lt 0) { throw "B's call did not go on" }
"  B: the timer runs ($b1 s)"
$trace = Join-Path $Root "A\trace.log"
if (Test-Path $trace) { Get-Content $trace | Select-String "route" | Select-Object -Last 3 | ForEach-Object { "  A trace: $_" } }
Use-Montana $A
Click-Named "Отбой"
Use-Montana $B
Says "Звонок завершён" 30
"done in $([int]((Get-Date) - $t0).TotalSeconds) s"
Use-Montana $A; Stop-Montana; Use-Montana $B; Stop-Montana
