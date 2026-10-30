# FORWARD AND SEARCH, LIVE (after tools\ab.ps1 with the same -Root): B writes a letter, A forwards it back to B, who sees it
# marked «Переслано»; then A searches for words inside letters and the hit shows under «Сообщения».
# usage: tools\forward.ps1 -Root DIR [-Shots DIR]
param([Parameter(Mandatory = $true)][string]$Root, [string]$Shots = "")
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ui.ps1"
function Snap($name) { if ($Shots) { Shot-Montana (Join-Path $Shots "$name.png") } }
function Says([string]$text, [int]$timeout = 45) { Find-Named $text $timeout | Out-Null; "  sees: $text" }
$t0 = Get-Date
$stamp = Get-Date -Format "HHmmss"
$B = Start-Montana -DataDir "$Root\B"; Front-Montana -X 0 -Y 40 -Width 1500 -Height 950
Start-Sleep -Seconds 2
Click-Named "Алиса Тест"
Type-Into "Сообщение..." "для пересылки $stamp"; Click-Named "Отправить"
Says "для пересылки $stamp" 10
Sent-Settle   # the new letter itself left (an older letter of the feed may read «Отправлено» already)
Stop-Montana
$A = Start-Montana -DataDir "$Root\A"; Front-Montana -X 0 -Y 40 -Width 1500 -Height 950
Start-Sleep -Seconds 2
Click-Named "Борис Тест"
Says "для пересылки $stamp" 60
"A forwards B's letter"
Start-Sleep -Seconds 1; RightClick-Named "для пересылки $stamp"; Click-Named "Переслать"
Click-Named "Переслать: Борис Тест"   # the picker's row
Start-Sleep -Seconds 3
Stop-Montana
$B = Start-Montana -DataDir "$Root\B"; Front-Montana -X 0 -Y 40 -Width 1500 -Height 950
Start-Sleep -Seconds 2
Click-Named "Алиса Тест"
Says "Переслано" 60
Snap "22-B-forwarded"
Stop-Montana
"A searches inside letters"
$A = Start-Montana -DataDir "$Root\A"; Front-Montana -X 0 -Y 40 -Width 1500 -Height 950
Start-Sleep -Seconds 2
Type-Into "Поиск" "пересылки $stamp"
Says "Сообщения" 10
Snap "23-A-search"
"done in $([int]((Get-Date) - $t0).TotalSeconds) s"
Stop-Montana
