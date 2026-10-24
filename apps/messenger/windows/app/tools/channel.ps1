# A CHANNEL, LIVE (after tools\ab.ps1 with the same -Root): A makes the channel «Канал HHmmss» in three steps (what it is; its
# name and words; B as its subscriber) and posts into it; B finds the post, has no field to write in but «Выкл. звук», and its
# screen shows the post; A's eye under the post counts two.
# usage: tools\channel.ps1 -Root DIR [-Shots DIR]
param([Parameter(Mandatory = $true)][string]$Root, [string]$Shots = "")
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ui.ps1"
function Snap($name) { if ($Shots) { Shot-Montana (Join-Path $Shots "$name.png") } }
function Says([string]$text, [int]$timeout = 60) { Find-Named $text $timeout | Out-Null; "  sees: $text" }
$t0 = Get-Date
$stamp = Get-Date -Format "HHmmss"
$title = "Канал $stamp"
$A = Start-Montana -DataDir "$Root\A"; Front-Montana -X 0 -Y 40 -Width 1500 -Height 950
Start-Sleep -Seconds 2
"A makes the channel"
Click-Named "Написать"; Click-Named "Новый канал"
Says "Что такое канал?" 10
Click-Named "Создать канал"
Type-Into "Название канала" $title
Type-Into "Описание (необязательно)" "Проверка канала с Windows"
Click-Named "Готово"
Click-Named "Выбрать: Борис Тест"; Click-Named "Готово"
Says "Сообщений пока нет" 30   # the channel opens with an empty feed: no event rows in a channel (iOS)
Type-Into "Сообщение..." "Пост канала $stamp"; Click-Named "Отправить"
Says "Отправлено" 30
Snap "34-A-channel"
Stop-Montana
"B finds the post and reads it"
$B = Start-Montana -DataDir "$Root\B"; Front-Montana -X 0 -Y 40 -Width 1500 -Height 950
Says $title 90
Click-Named $title
Says "Пост канала $stamp" 60
Says "Выкл. звук" 10
if ((Get-Texts) -contains "Сообщение...") { throw "a subscriber has a field to write in" }
Start-Sleep -Seconds 3   # the post stays before the eyes: its name goes to the owner
Snap "35-B-channel"
Stop-Montana
"A's eye counts B"
$A = Start-Montana -DataDir "$Root\A"; Front-Montana -X 0 -Y 40 -Width 1500 -Height 950
Start-Sleep -Seconds 2
Click-Named $title
Says "Просмотры: 2" 90
Snap "36-A-views"
"done in $([int]((Get-Date) - $t0).TotalSeconds) s"
Stop-Montana
