# CHOOSING LETTERS, LIVE (after tools\ab.ps1 with the same -Root): B writes three letters to A, chooses the first by the
# letter's menu «Выбрать» and the others by the marks beside them -- «Выделено: 3» -- and «Удалить» takes all three away here
# (iOS deleteSelected: for me).
# usage: tools\select.ps1 -Root DIR [-Shots DIR]
param([Parameter(Mandatory = $true)][string]$Root, [string]$Shots = "")
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ui.ps1"
function Snap($name) { if ($Shots) { Shot-Montana (Join-Path $Shots "$name.png") } }
function Says([string]$text, [int]$timeout = 60) { Find-Named $text $timeout | Out-Null; "  sees: $text" }
$t0 = Get-Date
$stamp = Get-Date -Format "HHmmss"
$B = Start-Montana -DataDir "$Root\B"; Front-Montana -X 0 -Y 40 -Width 1500 -Height 950
Start-Sleep -Seconds 2
"B writes three letters"
Click-Named "Алиса Тест"
foreach ($i in 1..3) {
    Type-Into "Сообщение..." "Выбор $stamp $i"; Click-Named "Отправить"
    Says "Выбор $stamp $i" 15
}
"B chooses them"
RightClick-Named "Выбор $stamp 1"; Click-Named "Выбрать"
Says "Выделено: 1" 10
Click-Named "Выбрать: Выбор $stamp 2"; Click-Named "Выбрать: Выбор $stamp 3"
Says "Выделено: 3" 10
Snap "37-B-chosen"
Click-Named "Удалить"
foreach ($i in 1..3) { Gone-Named "Выбор $stamp $i" 15 }
"  gone: all three"
"done in $([int]((Get-Date) - $t0).TotalSeconds) s"
Stop-Montana
