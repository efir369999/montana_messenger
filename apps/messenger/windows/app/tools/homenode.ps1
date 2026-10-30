# YOUR NODE, THE PAGE (iOS HomeNodeView; after tools\ab.ps1 with the same -Root): A opens Settings, «Ваш узел» -- the address in its
# row, the node's word, the set-up of a machine one owns, the copies, what the node offers. A throwaway identity stands below
# level 8: the set-up, the switch and «Send a copy now» stand dimmed with «Opens at level 8. Your level is N.»; an address named
# without a set-up is spoken to through its front (https://<address>/pushwake), and a machine with no such front answers nothing:
# «Ваш узел не ответил»; the files' section stands dimmed too. Data and Storage, «КЕШ»: «Очистить кеш» asks «Очистить кеш?» and
# clears only what the node's book names -- for this person nothing. The road of a copy
# to one's own node and back -- iOS's own door, a certificate it made for itself, its digest pinned -- is the live test
# homenode::tests::a_copy_goes_to_ones_own_node_and_comes_back_and_another_certificate_hears_nothing (tools\homenode-door.ps1).
# usage: tools\homenode.ps1 -Root DIR [-Shots DIR]
param([Parameter(Mandatory = $true)][string]$Root, [string]$Shots = "")
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ui.ps1"
Add-Type -AssemblyName System.Windows.Forms
function Snap($name) { if ($Shots) { Shot-Montana (Join-Path $Shots "$name.png") } }
function Says([string]$text, [int]$timeout = 60) { Find-Named $text $timeout | Out-Null; "  sees: $text" }
# whether an element of this name takes a press now (a dimmed row does not)
function Enabled([string]$name) { (Find-Named $name 10).Current.IsEnabled }
$t0 = Get-Date
$A = Start-Montana -DataDir "$Root\A"; Front-Montana -X 0 -Y 40 -Width 900 -Height 1000

"A opens Settings, «Ваш узел»"
Open-Drawer; Click-Named "Настройки"; Click-Named "Ваш узел"
Says "ВАШ УЗЕЛ" 10
Says "Копии на ваш узел" 10
$lvl = Get-Texts | Where-Object { $_ -match '^Открывается на уровне 8\. Ваш уровень — \d+\.$' } | Select-Object -First 1
if (-not $lvl) { throw "the page does not say the level that opens the node" }
"  sees: $lvl"
foreach ($n in @("Настроить ваш узел", "Отправить копию сейчас", "Восстановить с вашего узла")) {
    if (Enabled $n) { throw "«$n» takes a press below level 8 (or with no copy held)" }
    "  dimmed: $n"
}
Snap "151-A-node"

"A names an address with no set-up: the node is spoken to through its front, and nothing answers there"
Type-Into "Адрес" "127.0.0.1"
(Find-Named "Адрес" 5).SetFocus(); Start-Sleep -Milliseconds 300   # the value is set without the focus: the field takes it, then Enter
[System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
Start-Sleep -Seconds 8
Snap "152-A-node-named"
Says "Ваш узел не ответил" 40
Says "ФАЙЛЫ НА ВАШЕМ УЗЛЕ" 10
if (Enabled "Отдать файлы узлу сейчас") { throw "«Отдать файлы узлу сейчас» takes a press below level 8" }
"  dimmed: Отдать файлы узлу сейчас"
try { (Find-Named "Отдать файлы узлу сейчас" 5).GetCurrentPattern([System.Windows.Automation.ScrollItemPattern]::Pattern).ScrollIntoView(); Start-Sleep -Milliseconds 600 } catch {}
Snap "152-A-node-silent"

"Data and Storage: the cache section -- clearing asks first, and only the node's word clears: the node's book of this person names no file, so nothing leaves"
Click-Named "Назад"; Click-Named "Данные и память"
Says "КЕШ" 10
$end = (Get-Date).AddSeconds(30)
while (-not (Enabled "Очистить кеш")) { if ((Get-Date) -gt $end) { throw "«Очистить кеш» stays dimmed with an address named" }; Start-Sleep -Milliseconds 500 }
Click-Named "Очистить кеш"
Says "Очистить кеш?" 10
Snap "153-A-cache-ask"
Click-In "Очистить кеш?" "Очистить"   # the sheet's own: the picture cache's row of that name stands under its shade
$end = (Get-Date).AddSeconds(60); $said = $null
while (-not $said) { $said = Get-Texts | Where-Object { $_ -like "Стёрто с компьютера: файлов — 0,*" -or $_ -eq "Ваш узел не ответил. Ничего не стёрто." } | Select-Object -First 1; if ((Get-Date) -gt $end) { throw "the clearing said nothing" }; Start-Sleep -Milliseconds 500 }
"  sees: $said"
Snap "154-A-cache-word"
"done in $([int]((Get-Date) - $t0).TotalSeconds) s"
Stop-Montana
