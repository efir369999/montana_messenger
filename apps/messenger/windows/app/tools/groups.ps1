# A GROUP, LIVE (after tools\ab.ps1 with the same -Root): A makes the group «Проверка группы» with B; B finds it in the list
# and writes into it; A sees the letter under B's name.
# usage: tools\groups.ps1 -Root DIR [-Shots DIR]
param([Parameter(Mandatory = $true)][string]$Root, [string]$Shots = "")
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ui.ps1"
function Snap($name) { if ($Shots) { Shot-Montana (Join-Path $Shots "$name.png") } }
function Says([string]$text, [int]$timeout = 60) { Find-Named $text $timeout | Out-Null; "  sees: $text" }
$t0 = Get-Date
$stamp = Get-Date -Format "HHmmss"
$title = "Группа $stamp"
$A = Start-Montana -DataDir "$Root\A"; Front-Montana -X 0 -Y 40 -Width 1500 -Height 950
Start-Sleep -Seconds 2
"A makes the group"
Click-Named "Написать"; Click-Named "Новая группа"
Click-Named "Выбрать: Борис Тест"; Click-Named "Готово"
Type-Into "Название группы" $title; Click-Named "Готово"
Says "Вы создали группу «$title»" 15
Snap "30-A-group"
Stop-Montana
"B finds it and writes"
$B = Start-Montana -DataDir "$Root\B"; Front-Montana -X 0 -Y 40 -Width 1500 -Height 950
Says $title 90
Click-Named $title
Type-Into "Сообщение..." "Пишу в группу $stamp"; Click-Named "Отправить"
Says "Отправлено" 30
Snap "31-B-group"
Stop-Montana
"A hears B in the group"
$A = Start-Montana -DataDir "$Root\A"; Front-Montana -X 0 -Y 40 -Width 1500 -Height 950
Start-Sleep -Seconds 2
Click-Named $title
Says "Пишу в группу $stamp" 60
Says "Борис Тест"
Snap "32-A-group-letter"
"done in $([int]((Get-Date) - $t0).TotalSeconds) s"
Stop-Montana
