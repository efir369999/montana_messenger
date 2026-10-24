# BLOCKING, LIVE (after tools\ab.ps1 with the same -Root): A blocks B; B's letter never lands at A and gets no receipt, B sees
# A «seen long ago»; A unblocks from Privacy → Blocked users, and B's next letter lands.
# usage: tools\blocks.ps1 -Root DIR [-Shots DIR]
param([Parameter(Mandatory = $true)][string]$Root, [string]$Shots = "")
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ui.ps1"
function Snap($name) { if ($Shots) { Shot-Montana (Join-Path $Shots "$name.png") } }
function Says([string]$text, [int]$timeout = 45) { Find-Named $text $timeout | Out-Null; "  sees: $text" }
$t0 = Get-Date
$stamp = Get-Date -Format "HHmmss"
$A = Start-Montana -DataDir "$Root\A"; Front-Montana -X 0 -Y 40 -Width 900 -Height 900
Find-Named "Борис Тест" 20 | Out-Null
function Privacy-Blocked { Open-Drawer; Click-Named "Настройки"; Click-Named "Приватность"; Click-Named "Заблокированные" }
function Close-Settings { Click-Named "Назад"; Click-Named "Назад"; Click-Named "Закрыть" }
# a clean start: an earlier run may have left B blocked
Privacy-Blocked; Start-Sleep -Seconds 1
if ((Get-Texts) -contains "Разблокировать") { Click-Named "Разблокировать"; Start-Sleep -Seconds 1 }
Close-Settings
"A blocks B"
RightClick-Named "Борис Тест"; Click-Named "Заблокировать"; Click-Named "Заблокировать контакт"
Start-Sleep -Seconds 3
$B = Start-Montana -DataDir "$Root\B"; Front-Montana -X 920 -Y 40 -Width 900 -Height 900
Click-Named "Алиса Тест"
"B: A is gone"
Says "Очень давно" 60
Type-Into "Сообщение..." "при блокировке $stamp"; Click-Named "Отправить"
Says "Отправлено" 30
Snap "21-B-blocked"
"A: the letter never lands"
Use-Montana $A; Front-Montana
Click-Named "Борис Тест"
Says "Заблокирован"
Start-Sleep -Seconds 20
if ((Get-Texts) -contains "при блокировке $stamp") { throw "a blocked person's letter landed" }
"  20 s: nothing of B's landed"
Use-Montana $B
if ((Get-Texts) -contains "Доставлено") { throw "a blocked person got a receipt" }
"  B got no receipt"
"A unblocks from Privacy"
Use-Montana $A; Front-Montana
Click-Named "Назад"   # from the chat to the list (a narrow window shows one at a time)
Privacy-Blocked
Says "Борис Тест"; Click-Named "Разблокировать"
Says "Никто не заблокирован."
Close-Settings
"B writes again"
Use-Montana $B; Front-Montana
Type-Into "Сообщение..." "после разблокировки $stamp"; Click-Named "Отправить"
Use-Montana $A; Front-Montana
Click-Named "Борис Тест"
Says "после разблокировки $stamp" 60
if ((Get-Texts) -contains "при блокировке $stamp") { throw "the letter sent while blocked came back" }
"  the blocked letter stays away; the new one landed"
"done in $([int]((Get-Date) - $t0).TotalSeconds) s"
Use-Montana $A; Stop-Montana; Use-Montana $B; Stop-Montana
