# A GROUP'S ROOM RECORDED, IN THE WINDOWS (after tools\ab.ps1 with the same -Root), on WebView2's test devices (a made-up
# microphone, no sound out): A makes a group with B and opens a voice chat, B comes in; A presses «Записать» -- the group is told the
# call is recorded; A stops -- «Запись звонка» goes to the group's chat and comes to B; A ends the room for everyone.
# usage: tools\roomrecord.ps1 -Root DIR [-Shots DIR]
param([Parameter(Mandatory = $true)][string]$Root, [string]$Shots = "")
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ui.ps1"
function Snap($name) { if ($Shots) { Shot-Montana (Join-Path $Shots "$name.png") } }
function Says([string]$text, [int]$timeout = 60) { Find-Named $text $timeout | Out-Null; "  sees: $text" }
function Linked([string]$who, [int]$timeout = 60) {
    $end = (Get-Date).AddSeconds($timeout)
    while ((Get-Date) -lt $end) {
        if (Get-Texts | Where-Object { $_ -like "$who, слушает*" -or $_ -like "$who, говорит*" }) { "  linked: $who"; return }
        Start-Sleep -Milliseconds 500
    }
    throw "the pair with $who never stood"
}
$t0 = Get-Date
$stamp = Get-Date -Format "HHmmss"
$title = "Запись $stamp"
$A = Start-Montana -DataDir "$Root\A" -FakeMedia; Front-Montana -X 0 -Y 40 -Width 1100 -Height 900
Start-Sleep -Seconds 2
"A makes the group and opens a voice chat, inviting B"
Click-Named "Написать"; Click-Named "Новая группа"
Click-Named "Выбрать: Борис Тест"; Click-Named "Готово"
Type-Into "Название группы" $title; Click-Named "Готово"
Says "Вы создали группу «$title»" 15
Click-Named "Позвонить"; Click-Named "Голосовой чат"
Click-Named "Пригласить: Борис Тест"; Click-Named "Пригласить"
Says "Голосовой чат: $title" 15
$B = Start-Montana -DataDir "$Root\B" -FakeMedia; Front-Montana -X 1120 -Y 40 -Width 1100 -Height 900
Start-Sleep -Seconds 2
Click-Named $title 90
Says "Алиса Тест приглашает вас" 90
Click-Named "Голосовой чат: Алиса Тест приглашает вас"
Linked "Алиса Тест" 60
"A records the room"
Use-Montana $A; Front-Montana
Linked "Борис Тест" 60
Click-Named "Записать"
Says "Идёт запись" 10
Start-Sleep -Seconds 4
Click-Named "Остановить запись"
Gone-Named "Идёт запись" 10
Says "Запись звонка" 60
"  A: the recording stands in the group's chat"
Use-Montana $B; Front-Montana
Says "Этот звонок записывается" 90
Says "Запись звонка" 90
"  B: the notice and the recording came"
Snap "95-B-room-recording"
Use-Montana $A; Front-Montana
Click-Named "Завершить для всех"
Press-MenuRow "Завершить для всех"
Gone-Named "Голосовой чат: $title" 10
"done in $([int]((Get-Date) - $t0).TotalSeconds) s"
Use-Montana $A; Stop-Montana; Use-Montana $B; Stop-Montana
