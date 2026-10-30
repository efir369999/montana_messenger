# A BREAK IN A CALL, LIVE (after tools\ab.ps1 with the same -Root): A calls B by voice and both talk; then B's web view -- the
# processes that carry its WebRTC -- stands still for twelve seconds, as a network that went away; A says «Восстановление
# связи…» and asks for fresh checks (call-restart); B's view moves again, and the call goes on: the timer runs on both sides.
# usage: tools\callbreak.ps1 -Root DIR [-Shots DIR]
param([Parameter(Mandatory = $true)][string]$Root, [string]$Shots = "")
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ui.ps1"
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class MontanaFreeze {
  [DllImport("ntdll.dll")] public static extern int NtSuspendProcess(IntPtr h);
  [DllImport("ntdll.dll")] public static extern int NtResumeProcess(IntPtr h);
}
"@
function Snap($name) { if ($Shots) { Shot-Montana (Join-Path $Shots "$name.png") } }
function Says([string]$text, [int]$timeout = 60) { Find-Named $text $timeout | Out-Null; "  sees: $text" }
function Tree([int]$id) { foreach ($k in @(Get-CimInstance Win32_Process -Filter "ParentProcessId=$id")) { $k.ProcessId; Tree $k.ProcessId } }
function Timer-Runs([int]$seconds) {
    $deadline = (Get-Date).AddSeconds($seconds)
    while ((Get-Date) -lt $deadline) {
        $t = Call-Timer   # the call screen's own timer, never an hour of the list
        if ($t -ge 0) { return $t }
        Start-Sleep -Milliseconds 500
    }
    -1
}
$t0 = Get-Date
$B = Start-Montana -DataDir "$Root\B"; Front-Montana -X 920 -Y 40 -Width 900 -Height 900
Start-Sleep -Seconds 2
$A = Start-Montana -DataDir "$Root\A"; Front-Montana -X 0 -Y 40 -Width 900 -Height 900
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
Start-Sleep -Seconds 3
"B's view stands still for 12 s"
$frozen = @(Tree $B.Id)
if (-not $frozen) { throw "B's web view has no processes of its own" }
try {
    foreach ($id in $frozen) { $p = Get-Process -Id $id -ErrorAction SilentlyContinue; if ($p) { [MontanaFreeze]::NtSuspendProcess($p.Handle) | Out-Null } }
    Says "Восстановление связи" 15
    Snap "40-A-reconnecting"
    Start-Sleep -Seconds 6
} finally {
    foreach ($id in $frozen) { $p = Get-Process -Id $id -ErrorAction SilentlyContinue; if ($p) { [MontanaFreeze]::NtResumeProcess($p.Handle) | Out-Null } }
}
"B's view moves again"
$a1 = Timer-Runs 30
if ($a1 -lt 0) { throw "A's call did not come back" }
Start-Sleep -Seconds 3
$a2 = Timer-Runs 5
if ($a2 -le $a1) { throw "A's timer stands still ($a1 -> $a2)" }
"  A: the timer runs again ($a1 s -> $a2 s)"
Use-Montana $B
$b1 = Timer-Runs 15
if ($b1 -lt 0) { throw "B's call did not come back" }
"  B: the timer runs ($b1 s)"
Snap "41-B-talking-again"
Use-Montana $A
Click-Named "Отбой"
Use-Montana $B
Says "Звонок завершён" 30
"done in $([int]((Get-Date) - $t0).TotalSeconds) s"
Use-Montana $A; Stop-Montana; Use-Montana $B; Stop-Montana
