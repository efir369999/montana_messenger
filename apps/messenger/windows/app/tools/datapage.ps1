# DATA AND STORAGE, AS iOS LAYS IT (DataStorageView; after tools\ab.ps1 and tools\files.ps1 with the same -Root): A opens the letter's
# file «Отчёт о проверке.txt» (written out into the check's own Downloads, nothing started), then Settings, «Данные и память»: the two
# auto-download switches (mobile network, Wi-Fi), «КЕШ КАРТИНОК» and its «Очистить» with a mark, «КЕШ», «НА ЭТОМ КОМПЬЮТЕРЕ» -- every
# row of the measure with its size and the sum --, «Открытые файлы» holds the opened file and its trash asks first, then frees it
# («Освобождено …»), the backup's counts, the copy with contacts.
# usage: tools\datapage.ps1 -Root DIR [-Shots DIR]
param([Parameter(Mandatory = $true)][string]$Root, [string]$Shots = "")
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ui.ps1"
function Snap($name) { if ($Shots) { Shot-Montana (Join-Path $Shots "$name.png") } }
function Says([string]$text, [int]$timeout = 60) { Find-Named $text $timeout | Out-Null; "  sees: $text" }
function Named-Like([string]$pattern, [int]$timeout = 30) {
    $end = (Get-Date).AddSeconds($timeout)
    do { $hit = Get-Texts | Where-Object { $_ -match $pattern } | Select-Object -First 1; if ($hit) { return $hit }; Start-Sleep -Milliseconds 300 } while ((Get-Date) -lt $end)
    throw "nothing like '$pattern' on screen"
}
# the backup's «Беседы» row speaks its count in its own name: «Беседы 2 / 2»
function Copy-Count { [regex]::Match((Named-Like '^Беседы\s*\d+ / \d+$' 15), '\d+ / \d+').Value }
$t0 = Get-Date
$A = Start-Montana -DataDir "$Root\A"; Front-Montana -X 0 -Y 40 -Width 900 -Height 1000

"A opens the letter's file: it is written out, and named among the opened files"
Click-Named "Борис Тест"
Click-Named "Отчёт о проверке.txt" 60
Start-Sleep -Seconds 2
Click-Named "Назад"

"Settings, Data and Storage"
Open-Drawer; Click-Named "Настройки"; Click-Named "Данные и память"
Says "АВТОЗАГРУЗКА МЕДИА" 10
Says "Через мобильную сеть" 10
Says "Через Wi-Fi" 10
Says "КЕШ КАРТИНОК" 10
Snap "170-A-data-top"
Click-Named "Очистить" 10   # the exact name: the picture cache's row
Says "Готово" 10
"  the picture cache let go"
Says "НА ЭТОМ КОМПЬЮТЕРЕ" 10
foreach ($r in @("Вложения чатов", "Файлы без письма", "Картинки стен", "Копии, ждущие на компьютере", "Хранится для ваших собеседников", "Открытые файлы", "История чатов", "Лица", "Остальное", "На этом компьютере")) {
    $row = Named-Like ("^" + [regex]::Escape($r) + ": .+") 30
    "  row: $row"
}
$opened = Named-Like '^Открытые файлы: .+' 5
if ($opened -match 'Ноль') { throw "the opened file is not counted: $opened" }
try { (Find-Named "Открытые файлы: " 5).GetCurrentPattern([System.Windows.Automation.ScrollItemPattern]::Pattern).ScrollIntoView(); Start-Sleep -Milliseconds 500 } catch {}
Snap "171-A-data-measure"
Click-Named "Очистить: Открытые файлы" 10
Says "Очистить открытые файлы?" 10
Snap "172-A-data-ask"
Click-In "Очистить открытые файлы?" "Очистить"   # the sheet's own: the picture cache's row of that name stands under its shade
$word = Named-Like '^Освобождено .+\. Файлов вернулось в чаты: 0\.$' 30
"  sees: $word"
Snap "173-A-data-freed"
Click-In "Кеш" "ОК"   # the alert's button, in Cyrillic as the app says it
$after = Named-Like '^Открытые файлы: Ноль' 30
"  after: $after"
$inv = Copy-Count
"  the backup takes conversations: $inv"
Says "КОПИЯ У СОБЕСЕДНИКОВ" 10

"The copy's conversations: one left out, the count says so, and put back"
$taken = [int]($inv -split ' / ')[0]; $all = [int]($inv -split ' / ')[1]
Click-Named "Беседы"
Says "Беседа, оставленная вне копии" 10
Snap "174-A-copy-chats"
Click-Named "Борис Тест"
Snap "174b-A-copy-chats-out"
Click-Named "Назад"
$out = Copy-Count
if ($out -ne "$($taken - 1) / $all") { throw "leaving Boris out did not change the count: $out (was $inv)" }
"  Boris left out: $out"
Click-Named "Беседы"; Click-Named "Борис Тест"; Click-Named "Назад"
$back = Copy-Count
if ($back -ne $inv) { throw "Boris did not come back into the copy: $back" }
"  Boris back: $back"

"The copy's attachments by kind; the films: all chosen, asked, and the node that holds none keeps them here"
Click-Named "Вложения"
Says "Голосовые" 10
Snap "175-A-copy-kinds"
Click-Named "Видео"
Says "В копии" 10
Click-Named "Выбрать"
Click-Named "Выбрать все"
Snap "176-A-copy-choosing"
Click-Named "Удалить"
$ask = Named-Like '^Убрать с компьютера файлов: \d+\?$' 10
"  sees: $ask"
Click-In $ask "Убрать с компьютера"
$stay = Named-Like '^Ваш узел ещё не хранит выбранных файлов: \d+ — они остаются на компьютере\.$' 30
"  sees: $stay"
Snap "177-A-copy-stayed"
Click-In "Кеш" "ОК"
Click-Named "Назад"; Click-Named "Назад"
"done in $([int]((Get-Date) - $t0).TotalSeconds) s"
Stop-Montana
