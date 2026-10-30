# THE GROUNDS, IN THE WINDOW (after tools\ab.ps1 with the same -Root): A's page wears the default ground -- the app's dark one,
# the gold is gone whole (iOS 2304 MTWallpaper.retired) -- softened behind the chats; from B's page A chooses «Фон чата» →
# «Синий» -- the chat with B stands on blue, the list still on the dark default; from A's
# own page «Изменить фон страницы» → «Индиго» -- the list turns indigo; a photo of A's own (a drawn green picture) placed in the
# preview becomes the chat's ground and is still there after A's window is closed and opened again; «Как у моей страницы»
# gives the chat back the page's ground. Then a person being made: the first screen on burgundy, «Создать» asks my page's
# ground first (the default marked), «Небо» is chosen -- the making's pages and then the new person's chats stand on it.
# What the window draws is read from its own pixels (PrintWindow, this window only).
# usage: tools\ground.ps1 -Root DIR [-Shots DIR]
param([Parameter(Mandatory = $true)][string]$Root, [string]$Shots = "")
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ui.ps1"
function Snap($name) { if ($Shots) { Shot-Montana (Join-Path $Shots "$name.png") } }
function Says([string]$text, [int]$timeout = 60) { Find-Named $text $timeout | Out-Null; "  sees: $text" }
# the share of a region's points whose colour passes a test: x and y in parts of the window
function Share([double]$x0, [double]$x1, [double]$y0, [double]$y1, [scriptblock]$test) {
    $f = Join-Path $env:TEMP "montana-ground-shot.png"
    Shot-Montana $f
    $bmp = [System.Drawing.Bitmap]::FromFile($f)
    try {
        $n = 0; $hit = 0
        for ($i = 0; $i -lt 12; $i++) {
            for ($j = 0; $j -lt 12; $j++) {
                $c = $bmp.GetPixel([int]($bmp.Width * ($x0 + ($x1 - $x0) * $i / 11)), [int]($bmp.Height * ($y0 + ($y1 - $y0) * $j / 11)))
                $n++; if (& $test $c) { $hit++ }
            }
        }
        [double]$hit / $n
    } finally { $bmp.Dispose(); Remove-Item $f -ErrorAction SilentlyContinue }
}
# the chat's ground is read right of the date's plate, under the title's capsule -- the capsule takes the whole top row since
# d7384c1 (iOS chatTitleBubble: maxWidth .infinity) and is glass of its own, never the ground
$warm = { param($c) $c.R -gt $c.B + 25 }   # the burgundy of the first screen
$dark = { param($c) [Math]::Max($c.R, [Math]::Max($c.G, $c.B)) -lt 70 }   # the default: the dark gradient, the Logo at 0.035
$blue = { param($c) $c.B -gt $c.R + 10 }
$green = { param($c) $c.G -gt $c.R + 40 -and $c.G -gt $c.B + 40 }
function Expect([string]$what, [double]$x0, [double]$x1, [double]$y0, [double]$y1, [scriptblock]$test, [double]$least = 0.6) {
    $end = (Get-Date).AddSeconds(10)
    do { $s = Share $x0 $x1 $y0 $y1 $test; if ($s -ge $least) { break }; Start-Sleep -Milliseconds 500 } while ((Get-Date) -lt $end)
    if ($s -lt $least) { throw "$what -- only $([int]($s * 100))% of the points" }
    "  $what ($([int]($s * 100))% of the points)"
}
function Chosen([string]$name) {
    $e = Find-Named $name 10; $p = $null
    if ($e.TryGetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern, [ref]$p)) { return $p.Current.IsSelected }
    if ($e.TryGetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern, [ref]$p)) { return $p.Current.ToggleState -eq "On" }
    throw "'$name' tells no choice"
}
function Pick-Tile([string]$name) {
    Click-Named $name
    Says "Предпросмотр" 10
    Click-Named "Готово"
    Gone-Named "Предпросмотр" 10
    if (-not (Chosen $name)) { throw "«$name» is not marked chosen" }
    "  «$name» chosen"
}
function Peer-Ground {
    Click-Named "Контакты"
    RightClick-Named "Борис Тест"   # the row's own menu is the person's page
    Click-Named "Фон чата"
    Says "Фоны Montana" 10
}
# THE CHAT'S GROUND IS READ AT THE FEED'S HEAD, where the first day's plate stands under the title's capsule and nothing right of it:
# the feed opens at its newest end, and the scenes before this one in the full order fill the chat with B -- there A's own card and a
# picture stood under the capsule, right of the plate (a full run of 25.10.2026 read 34 % «dark» on A's card letter). The wheel draws the
# feed down over its middle until the window's pixels there stand still.
function Feed-Look {
    $f = Join-Path $env:TEMP "montana-ground-feed.png"
    Shot-Montana $f
    $bmp = [System.Drawing.Bitmap]::FromFile($f)
    try { $s = ""; for ($i = 0; $i -lt 8; $i++) { for ($j = 0; $j -lt 12; $j++) { $s += $bmp.GetPixel([int]($bmp.Width * (0.42 + 0.07 * $i)), [int]($bmp.Height * (0.15 + 0.055 * $j))).ToArgb() } }; $s }
    finally { $bmp.Dispose(); Remove-Item $f -ErrorAction SilentlyContinue }
}
function Feed-Head {
    $r = New-Object MontanaWin+Rect; [MontanaWin]::GetWindowRect((Handle), [ref]$r) | Out-Null
    $x = [int]($r.Left + ($r.Right - $r.Left) * 0.7); $y = [int]($r.Top + ($r.Bottom - $r.Top) * 0.5)
    $before = Feed-Look
    for ($i = 0; $i -lt 30; $i++) {
        if (Point-Holder $x $y) { Front-Montana; $who = Point-Holder $x $y; if ($who) { throw "the wheel over the feed would turn $who -- another program holds the front" } }
        [MontanaMouse]::SetCursorPos($x, $y) | Out-Null; Start-Sleep -Milliseconds 100
        for ($k = 0; $k -lt 10; $k++) { [MontanaMouse]::mouse_event(0x0800, 0, 0, 1200, [UIntPtr]::Zero); Start-Sleep -Milliseconds 30 }
        Start-Sleep -Milliseconds 700
        $now = Feed-Look
        if ($now -eq $before) { return }
        $before = $now
    }
    throw "the chat's feed never stood still at its head"
}
function Open-Talk { Click-Named "Чаты"; Click-Named "Борис Тест"; Find-Named "Сообщение..." 15 | Out-Null; Start-Sleep -Milliseconds 800; Feed-Head }
Add-Type -AssemblyName System.Drawing
$pic = Join-Path $Root "ground-test.png"
$bmp = New-Object System.Drawing.Bitmap 1200, 800
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.Clear([System.Drawing.Color]::FromArgb(255, 30, 180, 60))
$g.FillEllipse((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 20, 140, 50))), 300, 150, 600, 500)
$g.Dispose(); $bmp.Save($pic, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
$env:MONTANA_TRACE = "1"
Remove-Item "$Root\A\trace.log" -ErrorAction SilentlyContinue
# every ground this check chooses is given back at its end: A's page to the default, the chat to my page's
$t0 = Get-Date
$A = Start-Montana -DataDir "$Root\A"; Front-Montana -X 0 -Y 40 -Width 1500 -Height 950
Start-Sleep -Seconds 2
"the default ground (the dark one) by default"
Open-Talk
Expect "the list stands on the dark default" 0.02 0.22 0.45 0.9 $dark
Expect "the chat with B stands on the dark default" 0.8 0.97 0.17 0.24 $dark
Snap "99-A-default"
"B's page: «Фон чата» → «Синий»"
Peer-Ground
Pick-Tile "Синий"
Click-Named "Готово"; Click-Named "Назад"
Open-Talk
Expect "the chat with B stands on blue" 0.8 0.97 0.17 0.24 $blue
Expect "the list still stands on the dark default" 0.02 0.22 0.45 0.9 $dark
Snap "100-A-chat-blue"
"my page: «Изменить фон страницы» → «Индиго»"
Open-Drawer; Click-Named "Алиса Тест"
Click-Named "Изменить"; Click-Named "Изменить фон страницы"
Says "Фон страницы" 10
if (-not (Chosen "По умолчанию")) { throw "the default ground is not marked as my page's" }
Pick-Tile "Индиго"
Click-Named "Готово"
Click-Named "Готово"   # the editor's checkmark
Click-Named "Назад"
Click-Named "Чаты"
Expect "the list stands on indigo" 0.02 0.22 0.45 0.9 $blue
Snap "101-A-page-indigo"
"a photo of mine, placed, as the chat's ground"
Peer-Ground
Click-Named "Фото"; Click-Named "Выбрать фотографию"; Pick-File $pic
Says "Предпросмотр" 10
Start-Sleep -Milliseconds 800
Click-Named "Готово"
Gone-Named "Предпросмотр" 15
Click-Named "Готово"; Click-Named "Назад"
$line = @(Get-Content "$Root\A\trace.log" -Encoding UTF8 -ErrorAction SilentlyContinue | Where-Object { $_ -match "ground kept chat photo (\d+)x(\d+)" }) | Select-Object -Last 1
if (-not $line) { throw "no photo ground was kept" }
"  kept: $($line -replace '^\d+ ', '')"
Open-Talk
Expect "the chat with B stands on the photo" 0.8 0.97 0.17 0.24 $green
Snap "102-A-chat-photo"
"closed and opened again: the grounds stay"
Stop-Montana; Start-Sleep -Seconds 2
$A = Start-Montana -DataDir "$Root\A"; Front-Montana -X 0 -Y 40 -Width 1500 -Height 950
Start-Sleep -Seconds 2
Open-Talk
Expect "the chat with B still stands on the photo" 0.8 0.97 0.17 0.24 $green
Expect "the list still stands on indigo" 0.02 0.22 0.45 0.9 $blue
"«Как у моей страницы»: the chat wears my page's ground again"
Peer-Ground
Pick-Tile "Как у моей страницы"
Click-Named "Готово"; Click-Named "Назад"
Open-Talk
Expect "the chat with B stands on my page's indigo" 0.8 0.97 0.17 0.24 $blue
"my page back to the default"
Open-Drawer; Click-Named "Алиса Тест"
Click-Named "Изменить"; Click-Named "Изменить фон страницы"
Pick-Tile "По умолчанию"
Click-Named "Готово"; Click-Named "Готово"; Click-Named "Назад"
Click-Named "Чаты"
Expect "the list stands on the dark default again" 0.02 0.22 0.45 0.9 $dark
Stop-Montana
"a person being made chooses the ground first: «Небо»; the making and then the chats wear it"
$dir = Join-Path $Root ("G" + (Get-Date -Format "HHmmss"))
$G = Start-Montana -DataDir $dir; Front-Montana -X 0 -Y 40 -Width 1500 -Height 950
Click-Named "Продолжить с Montana"
Expect "the first screen stands on burgundy" 0.05 0.95 0.3 0.7 $warm
Click-Named "Создать"
Says "Фон страницы" 15
if (-not (Chosen "По умолчанию")) { throw "the default ground is not marked for a person being made" }
Pick-Tile "Небо"
Click-Named "Готово"
Find-Named "Я понимаю и беру ответственность на себя" 30 | Out-Null
Expect "the warning stands on the sky" 0.05 0.95 0.3 0.7 $blue
Snap "103-G-making-sky"
Click-Named "Я понимаю и беру ответственность на себя"; Click-Named "Показать слова"
Click-Named "Я записал слова в надёжном месте"; Click-Named "Ваша личность в Montana"
Click-Named "Готово"; Click-Named "Принимаю"
Find-Named "Поиск" 30 | Out-Null
Expect "the new person's chats stand on the sky" 0.8 0.97 0.17 0.24 $blue
"done in $([int]((Get-Date) - $t0).TotalSeconds) s"
Stop-Montana
Start-Sleep -Seconds 2
Remove-Item -Recurse -Force $dir -ErrorAction SilentlyContinue
