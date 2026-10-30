# A GAME OF CHESS, LIVE (after tools\ab.ps1 with the same -Root): A invites B from the chat's «Шахматы» without a clock and
# plays white; B opens the invitation's card and accepts; the fool's mate is played on both boards, square by square, and
# both read «Чёрные победили»; the chat holds the invitation alone, never a move; the chess page lists the game. No coin rides
# a game (the author's word 29.10.2026 19:31 UTC): the new-game page asks no stake and neither board shows a pot.
# usage: tools\chess.ps1 -Root DIR [-Shots DIR]
param([Parameter(Mandatory = $true)][string]$Root, [string]$Shots = "")
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ui.ps1"
function Snap($name) { if ($Shots) { Shot-Montana (Join-Path $Shots "$name.png") } }
function Says([string]$text, [int]$timeout = 60) { Find-Named $text $timeout | Out-Null; "  sees: $text" }
# one move: the piece's square, then its target, on the machine whose turn it is, once its board says «Ваш ход»
function Plays($who, [string]$from, [string]$to) {
    Use-Montana $who; Front-Montana
    Says "Ваш ход" 90
    Click-Named $from; Start-Sleep -Milliseconds 300; Click-Named $to
    "  plays $from-$to"
}
$t0 = Get-Date
$A = Start-Montana -DataDir "$Root\A"; Front-Montana -X 0 -Y 40 -Width 950 -Height 1000
Start-Sleep -Seconds 2
"A invites B"
Click-Named "Борис Тест"
Click-Named "Шахматы: Борис Тест"
Says "Пригласить собеседника" 10
Click-Named "Без часов"
if ((Get-Texts) | Where-Object { $_ -eq "Ставка" }) { throw "the new-game page asks a stake" }
Click-Named "Пригласить собеседника"
Says "Ждём, когда примут приглашение" 30
Snap "54-A-invited"
$B = Start-Montana -DataDir "$Root\B"; Front-Montana -X 960 -Y 40 -Width 950 -Height 1000
Start-Sleep -Seconds 2
"B accepts"
Click-Named "Алиса Тест"
Click-Named "Шахматы · Вы играете чёрными" 90
Click-Named "Принять приглашение" 15
Says "Ход соперника" 30
"the fool's mate"
Plays $A "f2 Белая пешка" "f3"
Plays $B "e7 Чёрная пешка" "e5"
Plays $A "g2 Белая пешка" "g4"
Plays $B "d8 Чёрный ферзь" "h4"
Says "Чёрные победили" 30
if ((Get-Texts) | Where-Object { $_ -like "Банк*" }) { throw "a pot stands on B's board" }
"  B: no pot"
Snap "55-B-mate"
Use-Montana $A; Front-Montana
Says "Чёрные победили" 90
Says "1. f3 e5 2. g4 Qh4#" 10
Snap "56-A-mate"
"the chat holds the invitation alone"
Click-Named "Назад"   # narrow: back to the list, the board with the conversation
Click-Named "Борис Тест"
Says "Шахматы · Вы играете белыми" 15
if ((Get-Texts) | Where-Object { $_ -like "*montana://chess*" }) { throw "a game's letter stands in the chat as words" }
"the chess page lists the game"
Click-Named "Назад"   # narrow: the list, and the drawer over it
Open-Drawer; Click-Named "Шахматы"
Says "Борис Тест, Чёрные победили" 15
Snap "57-A-chess-page"
"done in $([int]((Get-Date) - $t0).TotalSeconds) s"
Use-Montana $B; Stop-Montana; Use-Montana $A; Stop-Montana
