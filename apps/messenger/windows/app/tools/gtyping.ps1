# A GROUP'S «TYPING», LIVE (after tools\groups.ps1 with the same -Root): B types in the group without sending, and A's head says
# «Борис Тест печатает…»; then A, the owner, types, and B's head says «Алиса Тест печатает…».
# usage: tools\gtyping.ps1 -Root DIR [-Shots DIR]
param([Parameter(Mandatory = $true)][string]$Root, [string]$Shots = "")
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ui.ps1"
function Snap($name) { if ($Shots) { Shot-Montana (Join-Path $Shots "$name.png") } }
# one types again and again (a word each time, as keys would), the other looks at its head between
function Types($who, $at, [string]$line) {
    for ($i = 0; $i -lt 10; $i++) {
        Use-Montana $who; Type-Into "Сообщение..." "Пишу $i"
        Use-Montana $at
        try { Find-Named $line 4 | Out-Null; "  sees: $line"; return } catch {}
    }
    throw "'$line' never showed"
}
$t0 = Get-Date
$A = Start-Montana -DataDir "$Root\A"; Front-Montana -X 0 -Y 40 -Width 700 -Height 950
Start-Sleep -Seconds 2
$title = $null
for ($i = 0; $i -lt 40 -and -not $title; $i++) { $title = Get-Texts | Where-Object { $_ -like "Группа *" } | Select-Object -First 1; Start-Sleep -Milliseconds 300 }
if (-not $title) { throw "no group in A's list" }
Click-Named $title
$B = Start-Montana -DataDir "$Root\B"; Front-Montana -X 720 -Y 40 -Width 1100 -Height 950
Start-Sleep -Seconds 2
Click-Named $title
"B types in «$title»"
Types $B $A "Борис Тест печатает…"
Use-Montana $A; Snap "49-A-typing"
"A types"
Types $A $B "Алиса Тест печатает…"
Use-Montana $B; Snap "50-B-typing"
"done in $([int]((Get-Date) - $t0).TotalSeconds) s"
Use-Montana $B; Stop-Montana; Use-Montana $A; Stop-Montana
