# THE FOLDERS OVER THE CHATS, LIVE (after tools\groups.ps1 with the same -Root): A sees the tabs «Все», «Чаты», «Группы»,
# «Каналы» over the list; «Группы» holds the group alone, «Чаты» the pair alone. In Settings → «Папки с чатами» A makes the
# folder «Работа» of the personal chats, and its tab holds B alone.
# usage: tools\folders.ps1 -Root DIR [-Shots DIR]
param([Parameter(Mandatory = $true)][string]$Root, [string]$Shots = "")
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ui.ps1"
function Snap($name) { if ($Shots) { Shot-Montana (Join-Path $Shots "$name.png") } }
function Says([string]$text, [int]$timeout = 60) { Find-Named $text $timeout | Out-Null; "  sees: $text" }
$t0 = Get-Date
$A = Start-Montana -DataDir "$Root\A"; Front-Montana -X 0 -Y 40 -Width 1500 -Height 950
Start-Sleep -Seconds 2
try { Click-Named "Папка: Все" 10 } catch {}   # whatever tab stood chosen, All first
$title = $null
for ($i = 0; $i -lt 40 -and -not $title; $i++) { $title = Get-Texts | Where-Object { $_ -like "Группа *" } | Select-Object -First 1; Start-Sleep -Milliseconds 300 }
if (-not $title) { throw "no group in A's list" }
Says "Папка: Все" 15
Says "Папка: Каналы" 5
"A: «Группы» holds the group alone"
Click-Named "Папка: Группы"
Says $title 10
Gone-Named "Борис Тест" 10
"  and not B's chat"
"A: «Чаты» holds the pair alone"
Click-Named "Папка: Чаты"
Says "Борис Тест" 10
Gone-Named $title 10
"  and not the group"
Snap "51-A-folders"
"A makes the folder «Работа» of the personal chats"
Open-Drawer; Click-Named "Настройки"; Click-Named "Папки с чатами"
Says "Рекомендуемые папки" 10
Click-Named "Создать папку"
Type-Into "Название папки" "Работа"
Click-Named "Добавить чаты"
Click-Named "Личные"   # the personal chats: B's, the group stays out
Click-Named "Готово"   # the picker
Click-Named "Готово"   # the folder
Says "Работа" 10
Click-Named "Назад"; Click-Named "Закрыть"
Click-Named "Папка: Работа"
Says "Борис Тест" 10
Gone-Named $title 10
"  «Работа» holds B alone"
Snap "52-A-folder-work"
"A holds the tab: its menu as iOS's (contextMenu) -- the folder's page, its chats, the order of the tabs, remove; removed, All stands"
RightClick-Named "Папка: Работа"
Says "Изменить папку" 10
Says "Добавить чаты" 5
Says "Изменить порядок вкладок" 5
Snap "53-A-folder-menu"
Click-Named "Убрать"
Says "Удалить «Работа»?" 10
Says "Папка будет удалена, ваши чаты останутся." 5
Click-Named "Убрать"
Gone-Named "Папка: Работа" 10
Says "Борис Тест" 10
Says $title 10
"  the folder is gone, All stands with both chats"
RightClick-Named "Папка: Все"
Says "Изменить папки" 10
Click-Named "Изменить папки"
Says "Рекомендуемые папки" 10
Click-Named "Назад"
Click-Named "Папка: Все"   # the next scenarios find the group in the list: the tab All stands chosen again
Start-Sleep -Seconds 1
"done in $([int]((Get-Date) - $t0).TotalSeconds) s"
Stop-Montana
