# A CALL OF TWO GROWS INTO A ROOM, LIVE (after tools\ab.ps1 with the same -Root): C, a new identity, meets A by A's card;
# A calls B, both talk; A adds C to the call -- A and B go on in a room of a group born for it without hanging up, and C comes
# in by the invitation; every pair stands; A ends the room for everyone.
# usage: tools\callgrow.ps1 -Root DIR [-Shots DIR]
param([Parameter(Mandatory = $true)][string]$Root, [string]$Shots = "")
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ui.ps1"
function Snap($name) { if ($Shots) { Shot-Montana (Join-Path $Shots "$name.png") } }
function Says([string]$text, [int]$timeout = 60) { Find-Named $text $timeout | Out-Null; "  sees: $text" }
function Left([int]$timeout = 30) {
    $end = (Get-Date).AddSeconds($timeout)
    do { $x = Get-Texts; if (($x -contains "Отправлено") -or ($x -contains "Доставлено") -or ($x -contains "Прочитано")) { return }; Start-Sleep -Milliseconds 500 } while ((Get-Date) -lt $end)
    throw "the letter never left"
}
function Linked([string]$who, [int]$timeout = 60) {
    $end = (Get-Date).AddSeconds($timeout)
    while ((Get-Date) -lt $end) {
        if (Get-Texts | Where-Object { $_ -like "$who, слушает*" -or $_ -like "$who, говорит*" }) { "  linked: $who"; return }
        Start-Sleep -Milliseconds 500
    }
    throw "the pair with $who never stood: " + ((Get-Texts | Where-Object { $_ -like "$who,*" }) -join " | ")
}
function Talking([int]$timeout = 40) {
    $end = (Get-Date).AddSeconds($timeout)
    while ((Get-Date) -lt $end) { if ((Call-Timer) -ge 1) { return }; Start-Sleep -Milliseconds 500 }
    throw "the call never connected"
}
$t0 = Get-Date
$room = "Голосовой чат: Групповой звонок"
$met = Test-Path "$Root\K"   # Kira is born and meets A once (glink's C is another identity)
$A = Start-Montana -DataDir "$Root\A"; Front-Montana -X 0 -Y 40 -Width 900 -Height 900
Start-Sleep -Seconds 2
if (-not $met) {
"A shows its link"
Click-Named "Написать"; Click-Named "Мой код и ссылка"
$link = $null
for ($i = 0; $i -lt 40 -and -not $link; $i++) { $link = Get-Texts | Where-Object { $_ -like "https://montana.quest/perp/*" } | Select-Object -First 1; Start-Sleep -Milliseconds 300 }
if (-not $link) { throw "A shows no link" }
Click-Named "Закрыть"
"C: a new identity, «Кира Тест», meets A"
$C = Start-Montana -DataDir "$Root\K"; Front-Montana -X 920 -Y 40 -Width 900 -Height 900
Click-Named "Продолжить с Montana"; Click-Named "Создать"; Click-Named "Готово"   # my page's ground first (gold)
Click-Named "Я понимаю и беру ответственность на себя"; Click-Named "Показать слова"
Click-Named "Я записал слова в надёжном месте"; Click-Named "Ваша личность в Montana"
Find-Named "Готово" | Out-Null; Start-Sleep -Milliseconds 500
Type-First-Field "Кира Тест"; Click-Named "Готово"; Click-Named "Принимаю"
Click-Named "Сканировать"; Type-Into "Ссылка" $link; Click-Named "Открыть"
Says "Алиса Тест" 30
Type-Into "Сообщение..." "Привет от Киры"; Click-Named "Отправить"
Left 30
Use-Montana $A; Front-Montana
Says "Кира Тест" 90
Click-Named "Кира Тест"
Says "Привет от Киры" 60
Type-Into "Сообщение..." "Привет, Кира!"; Click-Named "Отправить"
Left 30
Use-Montana $C; Front-Montana
Says "Привет, Кира!" 90
Click-Named "Назад"
} else {
$C = Start-Montana -DataDir "$Root\K"; Front-Montana -X 920 -Y 40 -Width 900 -Height 900
Start-Sleep -Seconds 2
}
"A calls B; both talk"
$B = Start-Montana -DataDir "$Root\B"; Front-Montana -X 1840 -Y 40 -Width 900 -Height 900
Start-Sleep -Seconds 2
Use-Montana $A; Front-Montana
if (-not $met) { Click-Named "Назад" }
Click-Named "Борис Тест"; Click-Named "Позвонить"; Click-Named "Аудиозвонок"
Use-Montana $B; Front-Montana
Says "Принять" 60
Click-Named "Принять"
Talking 40
Use-Montana $A; Front-Montana
Talking 20
"A adds C: the call goes on in a room"
Click-Named "Добавить в звонок"; Click-Named "Добавить в звонок: Кира Тест"; Click-Named "Готово"
Says $room 30
Snap "60-A-grown"
Use-Montana $B; Front-Montana
Says $room 40
Linked "Алиса Тест" 60
Use-Montana $A; Front-Montana
Linked "Борис Тест" 60
"C comes in by the invitation"
Use-Montana $C; Front-Montana
Click-Named "Групповой звонок" 90
Says "Алиса Тест приглашает вас" 60
Click-Named "Голосовой чат: Алиса Тест приглашает вас"
Says $room 20
Linked "Алиса Тест" 60
Linked "Борис Тест" 60
Snap "61-C-room"
Use-Montana $A; Front-Montana
Linked "Кира Тест" 60
Use-Montana $B; Front-Montana
Linked "Кира Тест" 60
"A ends the room for everyone"
Use-Montana $A; Front-Montana
Click-Named "Завершить для всех"
Press-MenuRow "Завершить для всех"
Gone-Named $room 10
Use-Montana $C; Front-Montana
Gone-Named $room 60
"done in $([int]((Get-Date) - $t0).TotalSeconds) s"
Use-Montana $A; Stop-Montana; Use-Montana $B; Stop-Montana; Use-Montana $C; Stop-Montana
