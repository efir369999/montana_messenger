# THE BUSINESS CARD, IN THE WINDOWS (after tools\ab.ps1 with the same -Root): A opens «Визитка» from the drawer -- the plate
# carries A's name; A writes a phone and an e-mail, sends the card to B; B gets the card's photo with its words under «📇 »;
# A's card is kept: opened again, its fields stand as written.
# usage: tools\card.ps1 -Root DIR [-Shots DIR]
param([Parameter(Mandatory = $true)][string]$Root, [string]$Shots = "")
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ui.ps1"
function Snap($name) { if ($Shots) { Shot-Montana (Join-Path $Shots "$name.png") } }
function Says([string]$text, [int]$timeout = 60) { Find-Named $text $timeout | Out-Null; "  sees: $text" }
$t0 = Get-Date
$stamp = Get-Date -Format "HHmmss"
$phone = "+7 900 $stamp"
$mail = "alice$stamp@example.org"
$B = Start-Montana -DataDir "$Root\B"; Front-Montana -X 920 -Y 40 -Width 900 -Height 900
Start-Sleep -Seconds 2
$A = Start-Montana -DataDir "$Root\A"; Front-Montana -X 0 -Y 40 -Width 900 -Height 900
Start-Sleep -Seconds 2
"A writes its card"
Open-Drawer; Click-Named "Визитка"
Says "Другие способы связи" 15
$name = (Find-Named "Имя" 5)
Type-Into "Телефон" $phone
Type-Into "Почта" $mail
Says "Алиса Тест, $phone, $mail" 10
Snap "88-A-card"
Start-Sleep -Seconds 2   # kept after the typing pause
"A sends it to B"
Click-Named "Отправить"
Click-Named "Отправить: Борис Тест"
Says "Отправлено" 30
Use-Montana $B; Front-Montana
Click-Named "Алиса Тест"
Says $mail 90
"  B: the card's photo with its words"
Snap "89-B-card"
"A's card is kept"
Use-Montana $A; Stop-Montana
$A = Start-Montana -DataDir "$Root\A"; Front-Montana -X 0 -Y 40 -Width 900 -Height 900
Start-Sleep -Seconds 2
Open-Drawer; Click-Named "Визитка"
Says "Алиса Тест, $phone, $mail" 15
"done in $([int]((Get-Date) - $t0).TotalSeconds) s"
Use-Montana $A; Stop-Montana; Use-Montana $B; Stop-Montana
