# A GROUP'S LIVE STREAM WITH A WATCHER, LIVE (after tools\ab.ps1 with the same -Root), on WebView2's own test devices -- a drawn
# camera, a made-up microphone, no sound out; no camera or microphone of this computer is opened: A makes a group with B and
# opens a live stream; B comes in by the bar as a watcher -- no microphone and no camera of its own, A's picture on A's tile and
# frames flow (the diary names them); B watching is counted at A; A ends the stream for everyone.
# usage: tools\roomlive.ps1 -Root DIR [-Shots DIR]
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
$env:MONTANA_TRACE = "1"
foreach ($w in @("A", "B")) { Remove-Item "$Root\$w\trace.log" -ErrorAction SilentlyContinue }
$t0 = Get-Date
$stamp = Get-Date -Format "HHmmss"
$title = "Эфир $stamp"
$A = Start-Montana -DataDir "$Root\A" -FakeMedia; Front-Montana -X 0 -Y 40 -Width 1100 -Height 900
Start-Sleep -Seconds 2
"A makes the group and opens a live stream, inviting B"
Click-Named "Написать"; Click-Named "Новая группа"
Click-Named "Выбрать: Борис Тест"; Click-Named "Готово"
Type-Into "Название группы" $title; Click-Named "Готово"
Says "Вы создали группу «$title»" 15
Click-Named "Позвонить"; Click-Named "Трансляция"
Click-Named "Пригласить: Борис Тест"; Click-Named "Пригласить"
Says "Трансляция: $title" 15
$B = Start-Montana -DataDir "$Root\B" -FakeMedia; Front-Montana -X 1120 -Y 40 -Width 1100 -Height 900
Start-Sleep -Seconds 2
"B comes in by the bar and watches"
Click-Named $title 90
Says "Алиса Тест приглашает вас" 90
Click-Named "Трансляция: Алиса Тест приглашает вас"
Says "Трансляция: $title" 20
Linked "Алиса Тест" 60
Says "Алиса Тест: Видео" 30
Picture "B" "camera"
foreach ($key in @("Микрофон", "Видео", "Показать экран")) { if ((Get-Texts) -contains $key) { throw "a watcher holds '$key'" } }
"  B: a watcher, no microphone, no camera, no screen of its own"
Snap "77-B-live"
Use-Montana $A; Front-Montana
Says "Смотрят: 2" 30
"A ends the stream for everyone"
Click-Named "Завершить для всех"
Press-MenuRow "Завершить для всех"
Gone-Named "Трансляция: $title" 10
Use-Montana $B; Front-Montana
Gone-Named "Трансляция: $title" 60
"done in $([int]((Get-Date) - $t0).TotalSeconds) s"
Use-Montana $A; Stop-Montana; Use-Montana $B; Stop-Montana
