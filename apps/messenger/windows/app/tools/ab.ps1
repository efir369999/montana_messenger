# TWO PEOPLE ON ONE MACHINE, LIVE: two windows, each with a data folder and a fresh throw-away identity of its own. A shows
# its card; B pastes A's link, writes; A sees the letter, answers; B sees the answer; the ladder walks to «Read».
# Montana's own nodes carry the letters. usage: tools\ab.ps1 -Root DIR [-Shots DIR]
param([Parameter(Mandatory = $true)][string]$Root, [string]$Shots = "")
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ui.ps1"
if (Test-Path $Root) { Remove-Item -Recurse -Force $Root }
function Snap($name) { if ($Shots) { Shot-Montana (Join-Path $Shots "$name.png") } }
function Says([string]$text, [int]$timeout = 60) { Find-Named $text $timeout | Out-Null; "  sees: $text" }
# my letter left: the ladder under it says so -- «Отправлено», or already «Доставлено» when the other machine is on and quick
function Left([int]$timeout = 30) {
    $end = (Get-Date).AddSeconds($timeout)
    do { $x = Get-Texts; if (($x -contains "Отправлено") -or ($x -contains "Доставлено") -or ($x -contains "Прочитано")) { "  sees: the letter left"; return }; Start-Sleep -Milliseconds 500 } while ((Get-Date) -lt $end)
    throw "the letter never left"
}

function Onboard([string]$dir, [string]$name, [int]$x) {
    $p = Start-Montana -DataDir $dir
    Front-Montana -X $x -Y 40 -Width 900 -Height 900
    Click-Named "Продолжить с Montana"; Click-Named "Создать"; Click-Named "Готово"   # my page's ground first (gold)
    Click-Named "Я понимаю и беру ответственность на себя"; Click-Named "Показать слова"
    Click-Named "Я записал слова в надёжном месте"; Click-Named "Ваша личность в Montana"
    Find-Named "Готово" | Out-Null; Start-Sleep -Milliseconds 500
    Type-First-Field $name; Click-Named "Готово"; Click-Named "Принимаю"
    $p
}

$t0 = Get-Date
"A: a new identity, «Алиса Тест»"
$A = Onboard "$Root\A" "Алиса Тест" 0
Says "Скопировать ссылку" | Out-Null
$link = $null
for ($i = 0; $i -lt 40 -and -not $link; $i++) { $link = Get-Texts | Where-Object { $_ -like "https://montana.quest/perp/*" } | Select-Object -First 1; Start-Sleep -Milliseconds 300 }
if (-not $link) { throw "A shows no link" }
"  A's link: $($link.Substring(0, 34))…"
Snap "1-A-card"

"B: a new identity, «Борис Тест»; scans A's card by its link"
$B = Onboard "$Root\B" "Борис Тест" 920
Click-Named "Сканировать"; Type-Into "Ссылка" $link; Click-Named "Открыть"
Says "Сообщений пока нет"
Says "Алиса Тест"
Type-Into "Сообщение..." "Привет, Алиса! Пишу с Windows."; Click-Named "Отправить"
Left 30
Snap "2-B-sent"

"A: the letter arrives"
Use-Montana $A; Front-Montana
Says "Борис Тест" 90
Click-Named "Борис Тест"
Says "Привет, Алиса! Пишу с Windows."
Type-Into "Сообщение..." "Привет, Борис! Дошло."; Click-Named "Отправить"
Left 30
Snap "3-A-reply"

"B: the answer arrives and is read"
Use-Montana $B; Front-Montana
Says "Привет, Борис! Дошло." 90
Start-Sleep -Seconds 2   # B keeps looking at it: the read mark leaves 0.8 s later, while the chat is still before the eyes
Snap "4-B-answer"

"A: B read it"
Use-Montana $A; Front-Montana
Says "Прочитано" 90
Snap "5-A-read"
# the question at the opening (keep the copy with contacts?) answered «not now» on both: the later checks start without it,
# and tools\keeping.ps1 turns the keeping on by its own switch
foreach ($w in @($A, $B)) {
    Use-Montana $w; Front-Montana
    if ((Get-Texts) -contains "Не сейчас") { Click-Named "Не сейчас"; Gone-Named "Хранить вашу копию у собеседников?" 10 }
}
"done in $([int]((Get-Date) - $t0).TotalSeconds) s"
Use-Montana $A; Stop-Montana; Use-Montana $B; Stop-Montana
