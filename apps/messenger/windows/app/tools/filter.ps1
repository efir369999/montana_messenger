# THE FILTER, IN THE WINDOWS (after tools\ab.ps1 with the same -Root): B writes A a letter with a listed word -- in A's
# conversation it stands folded, «Скрыто фильтром» (the list row says the same; the list shows its rows to UI Automation by
# name only); A's tap shows the words; A turns the filter off in Privacy -- B's next such letter stands open; A turns it back on.
# usage: tools\filter.ps1 -Root DIR [-Shots DIR]
param([Parameter(Mandatory = $true)][string]$Root, [string]$Shots = "")
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ui.ps1"
function Snap($name) { if ($Shots) { Shot-Montana (Join-Path $Shots "$name.png") } }
function Says([string]$text, [int]$timeout = 60) { Find-Named $text $timeout | Out-Null; "  sees: $text" }
function Privacy-Filter { Open-Drawer; Click-Named "Настройки"; Click-Named "Приватность"; Click-Named "Фильтр неприемлемого содержимого"; Click-Named "Назад"; Click-Named "Закрыть" }
$t0 = Get-Date
$stamp = Get-Date -Format "HHmmss"
$first = "Это shit, а не тест $stamp"
$second = "Ещё один shit $stamp"
$B = Start-Montana -DataDir "$Root\B"; Front-Montana -X 920 -Y 40 -Width 900 -Height 900
Start-Sleep -Seconds 2
$A = Start-Montana -DataDir "$Root\A"; Front-Montana -X 0 -Y 40 -Width 900 -Height 900
Start-Sleep -Seconds 2
"B writes a letter with a listed word"
Use-Montana $B; Front-Montana
Click-Named "Алиса Тест"
Type-Into "Сообщение..." $first; Click-Named "Отправить"
Sent-Settle
"A: the letter stands folded"
Use-Montana $A; Front-Montana
Click-Named "Борис Тест" 30
Says "Нажмите, чтобы показать" 90
if ((Get-Texts) | Where-Object { $_ -like "*$first*" }) { throw "the words stand open in the conversation" }
Snap "83-A-folded"
# letters folded before this one stand folded too: each tap opens one, until this one shows
for ($i = 0; $i -lt 8 -and -not ((Get-Texts) | Where-Object { $_ -like "*$first*" }); $i++) { Click-Named "Скрыто фильтром"; Start-Sleep -Milliseconds 600 }
Says $first 10
"  A: the tap shows the words"
"A turns the filter off: the next letter stands open"
Click-Named "Назад"
Privacy-Filter
Use-Montana $B; Front-Montana
Type-Into "Сообщение..." $second; Click-Named "Отправить"
Sent-Settle
Use-Montana $A; Front-Montana
Click-Named "Борис Тест"
Says $second 90
if ((Get-Texts) -contains "Нажмите, чтобы показать") { throw "a letter is folded with the filter off" }
"A turns the filter back on"
Click-Named "Назад"
Privacy-Filter
"done in $([int]((Get-Date) - $t0).TotalSeconds) s"
Use-Montana $A; Stop-Montana; Use-Montana $B; Stop-Montana
