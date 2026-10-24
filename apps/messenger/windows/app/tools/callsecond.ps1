# THE SECOND LINE, LIVE (after tools\ab.ps1 with the same -Root; WebView2's test devices -- no microphone or camera of this
# computer opens): C («Кира Тест», born once and met with A, as callgrow does it) calls A while A talks with B. A sees «Кира Тест
# звонит» over the call and declines -- C's call ends, A's talk with B goes on. C calls again: «Удержать и принять» -- A talks
# with C, B is told it is on hold, A sees B parked; «Переключить» -- A is back with B, C on hold; A hangs up on B -- the call
# with C stands on hold, «Удержать» resumes it. Then B calls, C calls over it: «Завершить и принять» ends B's call and A talks
# with C.
# usage: tools\callsecond.ps1 -Root DIR [-Shots DIR]
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
function Talking([int]$timeout = 40) {
    $end = (Get-Date).AddSeconds($timeout)
    while ((Get-Date) -lt $end) { if ((Call-Timer) -ge 1) { return }; Start-Sleep -Milliseconds 500 }
    throw "the call never connected"
}
# a narrow window stands in the chat itself after a call (no list, no «Чаты»): from there the call key is at hand
function Dial([string]$who) {
    if (-not @(All-Named | Where-Object { $_.Current.Name -eq "Позвонить" }).Count) { Click-Named "Чаты"; Click-Named $who }
    Click-Named "Позвонить"; Click-Named "Аудиозвонок"
}
$env:MONTANA_TRACE = "1"
$t0 = Get-Date
$met = Test-Path "$Root\K"   # Kira is born and meets A once (callgrow uses the same identity)
$A = Start-Montana -DataDir "$Root\A" -FakeMedia; Front-Montana -X 0 -Y 40 -Width 900 -Height 900
Start-Sleep -Seconds 2
if (-not $met) {
"A shows its link"
Click-Named "Написать"; Click-Named "Мой код и ссылка"
$link = $null
for ($i = 0; $i -lt 40 -and -not $link; $i++) { $link = Get-Texts | Where-Object { $_ -like "https://montana.quest/perp/*" } | Select-Object -First 1; Start-Sleep -Milliseconds 300 }
if (-not $link) { throw "A shows no link" }
Click-Named "Закрыть"
"C: a new identity, «Кира Тест», meets A"
$C = Start-Montana -DataDir "$Root\K" -FakeMedia; Front-Montana -X 920 -Y 40 -Width 900 -Height 900
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
Use-Montana $C; Front-Montana
Click-Named "Назад"
} else {
$C = Start-Montana -DataDir "$Root\K" -FakeMedia; Front-Montana -X 920 -Y 40 -Width 900 -Height 900
Start-Sleep -Seconds 2
}
$B = Start-Montana -DataDir "$Root\B" -FakeMedia; Front-Montana -X 1840 -Y 40 -Width 900 -Height 900
Start-Sleep -Seconds 2

"B calls A; both talk"
Dial "Алиса Тест"
Use-Montana $A; Front-Montana
Click-Named "Принять" 60
Talking 40
Use-Montana $B; Front-Montana
Talking 20

"C calls A over the call: A declines the second line"
Use-Montana $C; Front-Montana
Dial "Алиса Тест"
Use-Montana $A; Front-Montana
Says "Кира Тест звонит" 60
Snap "104-A-second-line"
Use-Montana $C; Front-Montana
Says "Звонит…" 20
Use-Montana $A; Front-Montana
Click-Named "Отклонить"
Gone-Named "Кира Тест звонит" 10
Use-Montana $C; Front-Montana
Says "Звонок завершён" 30
Use-Montana $A; Front-Montana
$was = Call-Timer; Start-Sleep -Seconds 2
if ((Call-Timer) -le $was) { throw "A's talk with B stopped" }
"  A still talks with B"

"C calls again: «Удержать и принять»"
Use-Montana $C; Front-Montana
Start-Sleep -Seconds 3
Dial "Алиса Тест"
Use-Montana $A; Front-Montana
Says "Кира Тест звонит" 60
Click-Named "Удержать и принять"
Says "Борис Тест: На удержании" 15
Use-Montana $C; Front-Montana
Talking 40
Use-Montana $B; Front-Montana
Says "На удержании" 20
Use-Montana $A; Front-Montana
Talking 20
Snap "105-A-parked"

"«Переключить»: A is back with B, C on hold"
Click-Named "Переключить"
Says "Кира Тест: На удержании" 15
Use-Montana $B; Front-Montana
Gone-Named "На удержании" 20
Use-Montana $C; Front-Montana
Says "На удержании" 20

"A hangs up on B: the call with C stands on hold; «Удержать» resumes it"
Use-Montana $A; Front-Montana
Click-Named "Отбой"
Use-Montana $B; Front-Montana
Says "Звонок завершён" 30
Use-Montana $A; Front-Montana
Says "Кира Тест" 10
Says "На удержании" 10
Click-Named "Удержать"
Gone-Named "На удержании" 10
Use-Montana $C; Front-Montana
Gone-Named "На удержании" 20
"  the call with C goes on"
Use-Montana $A; Front-Montana
Click-Named "Отбой"
Use-Montana $C; Front-Montana
Says "Звонок завершён" 30

"B calls, C calls over it: «Завершить и принять»"
Start-Sleep -Seconds 3
Use-Montana $B; Front-Montana
Dial "Алиса Тест"
Use-Montana $A; Front-Montana
Click-Named "Принять" 60
Talking 40
Use-Montana $C; Front-Montana
Dial "Алиса Тест"
Use-Montana $A; Front-Montana
Says "Кира Тест звонит" 60
Click-Named "Завершить и принять"
Use-Montana $B; Front-Montana
Says "Звонок завершён" 30
Use-Montana $C; Front-Montana
Talking 40
Use-Montana $A; Front-Montana
Talking 20
Gone-Named "На удержании" 5
Click-Named "Отбой"
"done in $([int]((Get-Date) - $t0).TotalSeconds) s"
Use-Montana $A; Stop-Montana; Use-Montana $B; Stop-Montana; Use-Montana $C; Stop-Montana
