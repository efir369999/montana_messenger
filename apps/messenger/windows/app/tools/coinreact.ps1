# COINS ON A LETTER AND AUTO-REACTIONS, LIVE (iOS MTCoinSend.react, MTAutoReact; after tools\ab.ps1 with the same -Root), BY THE
# RULE OF iOS 2304: a paid reaction is a SEND weighed by what the giver holds, and from the time cut of 23.10.2026 the book mints
# nothing (fold-6), so the fresh people of a check hold no coins. B writes; A gives the letter a coin from its menu («Подарить
# монету») -- refused («Недостаточно монет»), and nothing reaches B. Then A chooses B in «Автореакции» with 3 coins: B's next letter
# asks its pay by itself -- refused the same (paid=0), nothing credited on B's side. A lets B go after.
# usage: tools\coinreact.ps1 -Root DIR [-Shots DIR]
param([Parameter(Mandatory = $true)][string]$Root, [string]$Shots = "")
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ui.ps1"
function Snap($name) { if ($Shots) { Shot-Montana (Join-Path $Shots "$name.png") } }
function Says([string]$text, [int]$timeout = 60) { Find-Named $text $timeout | Out-Null; "  sees: $text" }
function Wrote([string]$who, [string]$line, [int]$timeout = 60) {
    $end = (Get-Date).AddSeconds($timeout)
    do { $hit = Get-Content "$Root\$who\trace.log" -Encoding UTF8 -ErrorAction SilentlyContinue | Where-Object { $_ -like "*$line*" } | Select-Object -Last 1; if ($hit) { "  ${who}: $($hit -replace '^\d+ ', '')"; return }; Start-Sleep -Milliseconds 500 } while ((Get-Date) -lt $end)
    throw "$who never wrote '$line'"
}
function Send([string]$words) { Type-Into "Сообщение..." $words; [System.Windows.Forms.SendKeys]::SendWait("{ENTER}"); Says $words 20 | Out-Null }
Add-Type -AssemblyName System.Windows.Forms
$env:MONTANA_TRACE = "1"
Remove-Item "$Root\A\trace.log", "$Root\B\trace.log" -ErrorAction SilentlyContinue
$stamp = Get-Date -Format "HHmmss"
$t0 = Get-Date
$A = Start-Montana -DataDir "$Root\A"; Front-Montana -X 0 -Y 40 -Width 1200 -Height 950
$B = Start-Montana -DataDir "$Root\B"; Front-Montana -X 920 -Y 40 -Width 1200 -Height 950
"B writes; A gives the letter a coin -- A holds none: refused"
Click-Named "Алиса Тест"; Send "за это письмо монета $stamp"
Use-Montana $A; Front-Montana
Click-Named "Борис Тест"; Says "за это письмо монета $stamp" 90
RightClick-Named "за это письмо монета $stamp"
Click-Named "Подарить монету" 10
Says "Недостаточно монет" 10
"  A: refused -- A holds no coins"
"A chooses B in the auto-reactions with 3 coins"
# iOS opens the auto-reactions from the Money Flow's coin of the chat, by a hold (the right click here)
RightClick-Named "Денежный поток"
Says "Автореакции" 10
Type-Into "Борис Тест" "3"
Snap "170-A-autoreact"
Click-Named "Назад"
Use-Montana $B; Front-Montana
Send "автореакция $stamp"
Wrote "A" "auto_react coins=3 paid=0" 120
Start-Sleep -Seconds 5
if (Get-Content "$Root\B\trace.log" -Encoding UTF8 -ErrorAction SilentlyContinue | Where-Object { $_ -like "*coin_reaction received*" }) { throw "B was credited coins A does not hold" }
"  B: nothing credited"
"A lets B go"
Use-Montana $A; Front-Montana
Click-Named "Борис Тест"
RightClick-Named "Денежный поток"
Says "Автореакции" 10
Type-Into "Борис Тест" ""
Click-Named "Назад"
"done in $([int]((Get-Date) - $t0).TotalSeconds) s"
Use-Montana $A; Stop-Montana; Use-Montana $B; Stop-Montana
