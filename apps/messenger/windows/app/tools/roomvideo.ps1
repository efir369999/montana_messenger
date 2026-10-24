# PICTURES AND A SCREEN IN A GROUP'S ROOM, LIVE (after tools\ab.ps1 with the same -Root), on WebView2's own test devices -- a
# drawn camera, a drawn screen, a made-up microphone, no sound out; no camera, microphone or screen of this computer is opened:
# A makes a group with B and opens a video chat; B comes in by the bar with its camera; each tile shows the other's picture and
# frames flow (the diary names their size); B shows A's picture large -- A is told and sends it whole; A shows its screen --
# B's tile of A says «Экран» and frames flow; A takes it back -- A's camera again; A ends the room for everyone.
# usage: tools\roomvideo.ps1 -Root DIR [-Shots DIR]
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
# a diary line of a window that names a tile's picture of the given kind: a size above nothing with frames decoded flowed
function Picture([string]$who, [string]$what, [int]$timeout = 25) {
    $end = (Get-Date).AddSeconds($timeout)
    $last = ""
    do {
        foreach ($l in @(Get-Content "$Root\$who\trace.log" -Encoding UTF8 -ErrorAction SilentlyContinue | Where-Object { $_ -match "room picture \w+ $what " })) {
            $last = $l
            if ($l -match "room picture \w+ $what (\d+)x(\d+) in=(\d+)" -and [int]$Matches[1] -gt 0 -and [int]$Matches[3] -gt 0) {
                "  ${who}: $what $($Matches[1])x$($Matches[2]), $($Matches[3]) frames"; return
            }
        }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $end)
    throw "${who}: no picture under '$what': $last"
}
function Wrote([string]$who, [string]$line, [int]$timeout = 20) {
    $end = (Get-Date).AddSeconds($timeout)
    do {
        if (@(Get-Content "$Root\$who\trace.log" -Encoding UTF8 -ErrorAction SilentlyContinue) | Where-Object { $_ -like "* room $line*" }) { "  ${who}: $line"; return }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $end)
    throw "${who} never wrote '$line'"
}
$env:MONTANA_TRACE = "1"
foreach ($w in @("A", "B")) { Remove-Item "$Root\$w\trace.log" -ErrorAction SilentlyContinue }
$t0 = Get-Date
$stamp = Get-Date -Format "HHmmss"
$title = "Видео $stamp"
$A = Start-Montana -DataDir "$Root\A" -FakeMedia; Front-Montana -X 0 -Y 40 -Width 1100 -Height 900
Start-Sleep -Seconds 2
"A makes the group and opens a video chat, inviting B"
Click-Named "Написать"; Click-Named "Новая группа"
Click-Named "Выбрать: Борис Тест"; Click-Named "Готово"
Type-Into "Название группы" $title; Click-Named "Готово"
Says "Вы создали группу «$title»" 15
Click-Named "Позвонить"; Click-Named "Видеочат"
Click-Named "Пригласить: Борис Тест"; Click-Named "Пригласить"
Says "Видеочат: $title" 15
$B = Start-Montana -DataDir "$Root\B" -FakeMedia; Front-Montana -X 1120 -Y 40 -Width 1100 -Height 900
Start-Sleep -Seconds 2
"B comes in by the bar, with its camera"
Click-Named $title 90
Says "Алиса Тест приглашает вас" 90
Click-Named "Видеочат: Алиса Тест приглашает вас"
Says "Видеочат: $title" 20
Linked "Алиса Тест" 60
Says "Алиса Тест: Видео" 30
Picture "B" "camera"
Use-Montana $A; Front-Montana
Linked "Борис Тест" 60
Says "Борис Тест: Видео" 30
Picture "A" "camera"
Snap "72-A-video-room"
"B shows A's picture large"
Use-Montana $B; Front-Montana
Click-Named "Алиса Тест: Видео"
Wrote "A" "pair * wants me large=true"
Use-Montana $A; Front-Montana
"A shows its screen"
Click-Named "Показать экран"
Says "Экран" 10
Use-Montana $B; Front-Montana
Says "Алиса Тест: Экран" 30
Picture "B" "screen"
Snap "73-B-screen-room"
"A takes the screen back: its camera again"
Use-Montana $A; Front-Montana
Click-Named "Экран"
Use-Montana $B; Front-Montana
Says "Алиса Тест: Видео" 30
"A ends the room for everyone"
Use-Montana $A; Front-Montana
Click-Named "Завершить для всех"
Press-MenuRow "Завершить для всех"
Gone-Named "Видеочат: $title" 10
Use-Montana $B; Front-Montana
Gone-Named "Видеочат: $title" 60
"done in $([int]((Get-Date) - $t0).TotalSeconds) s"
Use-Montana $A; Stop-Montana; Use-Montana $B; Stop-Montana
