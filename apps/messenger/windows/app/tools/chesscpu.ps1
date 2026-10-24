# THE TRAINING GAME, LIVE (after tools\ab.ps1 with the same -Root): A opens the drawer's «Шахматы», plays the computer with
# white: A's 1. e4 is answered by the engine's move, then «Вернуть ход» takes both back; the page lists the game.
# usage: tools\chesscpu.ps1 -Root DIR [-Shots DIR]
param([Parameter(Mandatory = $true)][string]$Root, [string]$Shots = "")
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ui.ps1"
function Snap($name) { if ($Shots) { Shot-Montana (Join-Path $Shots "$name.png") } }
function Says([string]$text, [int]$timeout = 60) { Find-Named $text $timeout | Out-Null; "  sees: $text" }
$t0 = Get-Date
$A = Start-Montana -DataDir "$Root\A"; Front-Montana -X 0 -Y 40 -Width 950 -Height 1000
Start-Sleep -Seconds 2
"A plays the computer"
Open-Drawer; Click-Named "Шахматы"
Click-Named "♚ Играть с компьютером"
Click-Named "Белые фигуры"
Click-Named "Играть с компьютером"
Says "Ваш ход" 15
Click-Named "e2 Белая пешка"; Start-Sleep -Milliseconds 300; Click-Named "e4"
$answer = $null
for ($i = 0; $i -lt 60 -and -not $answer; $i++) { $answer = Get-Texts | Where-Object { $_ -match '^1\. e4 \S+' } | Select-Object -First 1; Start-Sleep -Milliseconds 500 }
if (-not $answer) { throw "the computer never answered" }
"  sees: $answer"
Says "Ваш ход" 10
Snap "58-A-computer"
"A takes the move back"
Click-Named "Вернуть ход"
Start-Sleep -Seconds 1
if (Get-Texts | Where-Object { $_ -match '^1\. ' }) { throw "the moves stayed" }
Says "e2 Белая пешка" 5
"  the board stands at the start again"
Click-Named "Назад"
Says "Компьютер, уровень" 10
"done in $([int]((Get-Date) - $t0).TotalSeconds) s"
Stop-Montana
