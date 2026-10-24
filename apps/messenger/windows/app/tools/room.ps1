# A GROUP'S ROOM, LIVE (after tools\ab.ps1 with the same -Root): A makes a group with B and opens a voice chat in it, inviting B;
# B sees the room over the group's chat under A's name and comes in by it; on both screens the other's pair stands (listening or
# speaking); B leaves and A sees B go; A ends the room for everyone; the feed holds «Вы начали голосовой чат» and its end.
# usage: tools\room.ps1 -Root DIR [-Shots DIR]
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
    throw "the pair with $who never stood: " + ((Get-Texts | Where-Object { $_ -like "$who,*" }) -join " | ")
}
$t0 = Get-Date
$stamp = Get-Date -Format "HHmmss"
$title = "Комната $stamp"
# the room's seconds are coins (iOS MTCallMint): A's trace says each second the room talked went to the book
$env:MONTANA_TRACE = "1"
Remove-Item "$Root\A\trace.log" -ErrorAction SilentlyContinue
$A = Start-Montana -DataDir "$Root\A"; Front-Montana -X 0 -Y 40 -Width 1100 -Height 900
Start-Sleep -Seconds 2
"A makes the group and opens a voice chat, inviting B"
Click-Named "Написать"; Click-Named "Новая группа"
Click-Named "Выбрать: Борис Тест"; Click-Named "Готово"
Type-Into "Название группы" $title; Click-Named "Готово"
Says "Вы создали группу «$title»" 15
Click-Named "Позвонить"; Click-Named "Голосовой чат"
Click-Named "Пригласить: Борис Тест"; Click-Named "Пригласить"
Says "Голосовой чат: $title" 15
Says "Вы, это вы" 10
Snap "50-A-room"
$B = Start-Montana -DataDir "$Root\B"; Front-Montana -X 1120 -Y 40 -Width 1100 -Height 900
Start-Sleep -Seconds 2
"B sees the room over the group's chat and comes in"
Click-Named $title 90
Says "Алиса Тест приглашает вас" 90
Click-Named "Голосовой чат: Алиса Тест приглашает вас"
Says "Голосовой чат: $title" 20
Linked "Алиса Тест" 60
Snap "51-B-room"
Use-Montana $A; Front-Montana
Linked "Борис Тест" 60
"B leaves; A sees B go"
Use-Montana $B; Front-Montana
Click-Named "Выйти"
Gone-Named "Голосовой чат: $title" 10
Use-Montana $A; Front-Montana
$end = (Get-Date).AddSeconds(60)
while ((Get-Date) -lt $end -and (Get-Texts | Where-Object { $_ -like "Борис Тест, *" })) { Start-Sleep -Milliseconds 500 }
if (Get-Texts | Where-Object { $_ -like "Борис Тест, *" }) { throw "A still holds B in the room" }
"  A: B went"
"A ends the room for everyone"
Click-Named "Завершить для всех"
Press-MenuRow "Завершить для всех"
Gone-Named "Голосовой чат: $title" 10
Says "Вы начали голосовой чат" 15
Says "Голосовой чат завершён" 15
Snap "52-A-feed"
$c = @(Get-Content "$Root\A\trace.log" -Encoding UTF8 -ErrorAction SilentlyContinue | Where-Object { $_ -like "* coins call=room:*" })
if ($c.Count -lt 1) { throw "the room's seconds never reached the coin book ($($c.Count) lines)" }
"  A: the room's seconds reached the coin book ($($c.Count) times, not recorded: burned)"
"done in $([int]((Get-Date) - $t0).TotalSeconds) s"
Use-Montana $A; Stop-Montana; Use-Montana $B; Stop-Montana
