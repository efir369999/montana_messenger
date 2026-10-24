# PRESENCE, LIVE (after tools\ab.ps1 with the same -Root): A and B open each other's chat; A sees B «in chat» by B's WA:1 on
# the signal lane, then «typing…» while B types, as an iPhone shows them.
# usage: tools\presence.ps1 -Root DIR [-Shots DIR]
param([Parameter(Mandatory = $true)][string]$Root, [string]$Shots = "")
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ui.ps1"
function Snap($name) { if ($Shots) { Shot-Montana (Join-Path $Shots "$name.png") } }
function Says([string]$text, [int]$timeout = 45) { Find-Named $text $timeout | Out-Null; "  sees: $text" }
$t0 = Get-Date
$A = Start-Montana -DataDir "$Root\A"; Front-Montana -X 0 -Y 40 -Width 900 -Height 900
Click-Named "Борис Тест"
$B = Start-Montana -DataDir "$Root\B"; Front-Montana -X 920 -Y 40 -Width 900 -Height 900
Click-Named "Алиса Тест"
"A: B in my chat"
Use-Montana $A
Says "В чате"
Snap "19-A-inchat"
"B types"
Use-Montana $B
Type-Into "Сообщение..." "пишу ответ"
Use-Montana $A
Says "Печатает…" 20
Snap "20-A-typing"
"done in $([int]((Get-Date) - $t0).TotalSeconds) s"
Use-Montana $A; Stop-Montana; Use-Montana $B; Stop-Montana
