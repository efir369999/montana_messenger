# THE PERSONS OF ONE COMPUTER (iOS MTSeats, the second identity checklist), in one data folder: Anna is made; the plus at the
# drawer's head makes room -- the program starts again on the Montana road with the way back -- and Vera is made beside her, Anna
# untouched. Vera writes to Anna's link while Anna waits on the shelf: the shelf is alive (a process of Anna's own, no window), so
# Anna's face in the drawer seats her with Vera's letter already there; Anna answers, Vera is seated again and finds the answer.
# The plus then the cross bring the last person back; Vera's own words typed on an empty seat seat Vera, no second copy born.
# usage: tools\seats.ps1 -Root DIR [-Shots DIR]
param([Parameter(Mandatory = $true)][string]$Root, [string]$Shots = "")
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ui.ps1"
function Snap($name) { if ($Shots) { Shot-Montana (Join-Path $Shots "$name.png") } }
function Says([string]$text, [int]$timeout = 60) { Find-Named $text $timeout | Out-Null; "  sees: $text" }
$dir = Join-Path $Root "S"
if (Test-Path $dir) { Remove-Item -Recurse -Force $dir }
function Place { Front-Montana -X 0 -Y 40 -Width 1500 -Height 950 }
# the words on the screen of the making, read from it in their numbers' order and kept in this process alone (a throw-away
# person's, never written anywhere)
function Read-Words {
    $names = @(); foreach ($e in (All-Named)) { try { $names += $e.Current.Name } catch {} }
    $w = @{}
    # each word stands as its number, a dot and the word: three names
    for ($i = 0; $i -lt $names.Count - 2; $i++) { if ($names[$i] -match '^(\d{1,2})$' -and $names[$i + 1] -eq '.') { $w[[int]$Matches[1]] = $names[$i + 2] } }
    if ($w.Count -ne 24) { throw "the making shows $($w.Count) words" }
    (1..24 | ForEach-Object { $w[$_] }) -join " "
}
function Make([string]$name, [switch]$Door) {
    if ($Door) { Click-Named "Продолжить с Montana" }
    Click-Named "Создать"; Click-Named "Готово"
    Click-Named "Я понимаю и беру ответственность на себя"; Click-Named "Показать слова"
    Find-Named "Я записал слова в надёжном месте" | Out-Null
    $words = Read-Words
    Click-Named "Я записал слова в надёжном месте"; Click-Named "Ваша личность в Montana"
    Find-Named "Готово" | Out-Null; Start-Sleep -Milliseconds 500
    Type-First-Field $name; Click-Named "Готово"; Click-Named "Принимаю"
    $words
}
function Drawer { Open-Drawer; Start-Sleep -Milliseconds 600 }
# a person's face in the drawer, from the calls' pane (no chat row there wears the same name)
function Seat-Of([string]$name) { Click-Named "Звонки"; Drawer; Click-Named $name; Follow-Montana $dir | Out-Null; Place }
function Seat-Folders { @(Get-ChildItem (Join-Path $dir "Seats") -Directory -ErrorAction SilentlyContinue).Count }
$t0 = Get-Date

"Anna: the first person of this computer"
Start-Montana -DataDir $dir | Out-Null; Place
Make "Анна Тест" -Door | Out-Null
Says "Скопировать ссылку" | Out-Null
$link = $null
for ($i = 0; $i -lt 40 -and -not $link; $i++) { $link = Get-Texts | Where-Object { $_ -like "https://montana.quest/perp/*" } | Select-Object -First 1; Start-Sleep -Milliseconds 300 }
if (-not $link) { throw "Anna shows no link" }

"the plus at the drawer's head: Anna goes to the shelf, the first screen opens on the Montana road with the way back"
Drawer; Click-Named "Выберите способ входа"
Follow-Montana $dir | Out-Null; Place
Says "Открыть личность" 20
Says "Отмена" 10
Snap "113-seat-empty"
$vera = Make "Вера Тест"
Says "Скопировать ссылку" | Out-Null

"Vera writes to Anna's link while Anna waits on the shelf"
Click-Named "Сканировать"; Type-Into "Ссылка" $link; Click-Named "Открыть"
Says "Анна Тест" 30
Type-Into "Сообщение..." "Привет, Анна, это Вера"; Click-Named "Отправить"
Sent-Settle
$shelf = @(Get-CimInstance Win32_Process -Filter "Name='montana-desktop.exe'" | Where-Object { $_.CommandLine -like '*--shelf*' }).Count
"  Montana processes of the shelf (no window): $shelf"
if ($shelf -lt 1) { throw "nobody waits alive on the shelf" }
$end = (Get-Date).AddSeconds(120)
do { $x = Get-Texts; if (($x -contains "Доставлено") -or ($x -contains "Прочитано")) { break }; Start-Sleep -Seconds 1 } while ((Get-Date) -lt $end)
if (-not (($x -contains "Доставлено") -or ($x -contains "Прочитано"))) { throw "Anna's shelf never took Vera's letter" }
"  sees: Доставлено -- Anna's shelf took the letter"

"Anna's face in the drawer seats her: Vera's letter is already there"
Seat-Of "Анна Тест"
Click-Named "Чаты"
Says "Вера Тест" 30
Click-Named "Вера Тест"
Says "Привет, Анна, это Вера" 30
Snap "114-seat-anna"
Type-Into "Сообщение..." "Здравствуй, Вера"; Click-Named "Отправить"
Sent-Settle

"Vera is seated again: Anna's answer came while she waited"
Seat-Of "Вера Тест"
Click-Named "Чаты"; Click-Named "Анна Тест"
Says "Здравствуй, Вера" 90
Snap "115-seat-vera"

"the plus, then the cross: the empty seat goes, Vera is back"
Drawer; Click-Named "Выберите способ входа"
Follow-Montana $dir | Out-Null; Place
Click-Named "Отмена"
Follow-Montana $dir | Out-Null; Place
Click-Named "Чаты"
Says "Анна Тест" 30

"from Anna, the plus and Vera's own words: Vera's seat is lifted, no second Vera"
Seat-Of "Анна Тест"
Drawer; Click-Named "Выберите способ входа"
Follow-Montana $dir | Out-Null; Place
Click-Named "Открыть личность"
Find-Named "Восстановить" 15 | Out-Null; Start-Sleep -Milliseconds 500
Type-First-Field $vera
Click-Named "Восстановить"
Follow-Montana $dir | Out-Null; Place
Click-Named "Чаты"; Click-Named "Анна Тест"
Says "Здравствуй, Вера" 30
# the empty seats the cross and the words left are swept once their window's files are let go
$end = (Get-Date).AddSeconds(60)
while ((Seat-Folders) -ne 1 -and (Get-Date) -lt $end) { Start-Sleep -Seconds 2 }
$seats = Seat-Folders
"  seat folders under Seats: $seats"
if ($seats -ne 1) { throw "the words made a second copy ($seats seat folders)" }
Drawer
Snap "116-seat-drawer"

"Montana opened a second time: it leaves, and the window standing comes forward"
$psi = New-Object System.Diagnostics.ProcessStartInfo $script:exe
$psi.UseShellExecute = $false
$psi.EnvironmentVariables["MONTANA_DATA_DIR"] = $dir
$psi.EnvironmentVariables["MONTANA_NO_HELLO"] = "1"
$second = [System.Diagnostics.Process]::Start($psi)
if (-not $second.WaitForExit(15000)) { $second.Kill(); throw "a second Montana for the same computer stayed" }
"  the second one left"
Says "Анна Тест" 10
"done in $([int]((Get-Date) - $t0).TotalSeconds) s"
Stop-Montana
