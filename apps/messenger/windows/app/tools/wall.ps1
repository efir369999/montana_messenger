# THE WALL, LIVE (after tools\ab.ps1 with the same -Root): A writes a post with a picture (a drawn one) on her own wall; B opens
# A's page and A's wall comes by her page -- the words and the picture (its poster, then its file fetched from the node by the
# post's own key); B likes it and comments on it, and writes a post of his own on A's wall; A sees B's like, B's comment and
# B's post on her wall, and both stand in her Wall of Thoughts; B's Wall of Thoughts holds A's posts «На стене: Алиса Тест».
# Then A chooses her page's ground «Индиго»: it reaches B by the ground's word (iOS «PG:», sent once B's word proves its build
# reads it, «G») and A's page at B stands on it, read from B's window's own pixels.
# usage: tools\wall.ps1 -Root DIR [-Shots DIR]
param([Parameter(Mandatory = $true)][string]$Root, [string]$Shots = "")
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ui.ps1"
function Snap($name) { if ($Shots) { Shot-Montana (Join-Path $Shots "$name.png") } }
function Says([string]$text, [int]$timeout = 60) { Find-Named $text $timeout | Out-Null; "  sees: $text" }
function Wrote([string]$who, [string]$line, [int]$timeout = 60) {
    $end = (Get-Date).AddSeconds($timeout)
    do { $hit = Get-Content "$Root\$who\trace.log" -Encoding UTF8 -ErrorAction SilentlyContinue | Where-Object { $_ -like "*$line*" } | Select-Object -Last 1; if ($hit) { "  ${who}: $($hit -replace '^\d+ ', '')"; return }; Start-Sleep -Milliseconds 500 } while ((Get-Date) -lt $end)
    throw "$who never wrote '$line'"
}
# a button by its name, when a tab of the page's strip shares it («Видео»: the strip's tab and a post's film)
function Press([string]$name, [int]$timeout = 15) {
    $end = (Get-Date).AddSeconds($timeout)
    do {
        $b = @(All-Named | Where-Object { try { $_.Current.Name -eq $name -and $_.Current.ControlType -eq [System.Windows.Automation.ControlType]::Button } catch { $false } }) | Select-Object -First 1
        if ($b) { $b.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke(); return }
        Start-Sleep -Milliseconds 300
    } while ((Get-Date) -lt $end)
    throw "no button '$name'"
}
# the menu «Ещё» of the post whose words these are: a root used before holds older posts over it
function PostMenu([string]$text) {
    $e = Find-Named $text 15
    $walk = [System.Windows.Automation.TreeWalker]::ControlViewWalker
    $more = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty, "Ещё")
    for ($i = 0; $i -lt 6 -and $e; $i++) {
        $e = $walk.GetParent($e)
        $m = if ($e) { $e.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $more) } else { $null }
        if ($m) { $m.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke(); Start-Sleep -Milliseconds 300; return }
    }
    throw "no menu of the post '$text'"
}
# my page stands before anything on it is pressed: the drawer opens it 0.3 s after it leaves (App.jsx fromDrawer), and until then the
# page under the drawer is still the reader's -- the Wall of Thoughts wears the very «Комментарии 1» of my post, whose comments it opens
# under my page, where they stand out of the reader's tree (App.jsx covered: inert) -- a run of 25.10.2026 pressed it there
function MyPage { Open-Drawer; Click-Named "Алиса Тест"; Find-Exact "Моя стена" 15 | Out-Null }
function PeerPage([string]$who) { Click-Named "Контакты"; RightClick-Named $who }
# the share of a region's points whose colour passes a test (this window's own pixels): x and y in parts of the window
function Share([double]$x0, [double]$x1, [double]$y0, [double]$y1, [scriptblock]$test) {
    $f = Join-Path $env:TEMP "montana-wall-shot.png"
    Shot-Montana $f
    $bmp = [System.Drawing.Bitmap]::FromFile($f)
    try {
        $n = 0; $hit = 0
        for ($i = 0; $i -lt 10; $i++) { for ($j = 0; $j -lt 10; $j++) {
            $c = $bmp.GetPixel([int]($bmp.Width * ($x0 + ($x1 - $x0) * $i / 9)), [int]($bmp.Height * ($y0 + ($y1 - $y0) * $j / 9)))
            $n++; if (& $test $c) { $hit++ } } }
        [double]$hit / $n
    } finally { $bmp.Dispose(); Remove-Item $f -ErrorAction SilentlyContinue }
}
$blue = { param($c) $c.B -gt $c.R + 20 }
function Page-Ground([string]$tile) {
    MyPage; Click-Named "Изменить"; Click-Named "Изменить фон страницы"
    Click-Named $tile; Find-Named "Предпросмотр" 10 | Out-Null; Click-Named "Готово"; Gone-Named "Предпросмотр" 10
    Click-Named "Готово"; Click-Named "Готово"; Click-Named "Назад"
}
Add-Type -AssemblyName System.Drawing
$pic = Join-Path $Root "wall-test.png"
$bmp = New-Object System.Drawing.Bitmap 1200, 900
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.Clear([System.Drawing.Color]::FromArgb(255, 40, 90, 200))
$g.FillEllipse([System.Drawing.Brushes]::Orange, 300, 200, 600, 500)
$g.Dispose(); $bmp.Save($pic, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
# a film (two seconds of the test pattern, when ffmpeg is here), a track (a second of 440 Hz) and a file, for the post of files
$film = Join-Path $Root "film.mp4"
if (Get-Command ffmpeg -ErrorAction SilentlyContinue) {
    & ffmpeg -hide_banner -loglevel error -y -f lavfi -i "testsrc=duration=2:size=320x240:rate=15" -c:v libx264 -pix_fmt yuv420p -movflags +faststart $film
}
if (-not (Test-Path $film)) { $film = $null; "  no ffmpeg here: the post goes without its film" }
$wav = Join-Path $Root "tone.wav"
$rate = 8000; $data = New-Object byte[] ($rate * 2)
for ($i = 0; $i -lt $rate; $i++) { $b = [BitConverter]::GetBytes([int16](8000 * [math]::Sin(2 * [math]::PI * 440 * $i / $rate))); $data[2 * $i] = $b[0]; $data[2 * $i + 1] = $b[1] }
$ms = New-Object IO.MemoryStream; $w = New-Object IO.BinaryWriter $ms
$w.Write([Text.Encoding]::ASCII.GetBytes("RIFF")); $w.Write([int](36 + $data.Length)); $w.Write([Text.Encoding]::ASCII.GetBytes("WAVEfmt "))
$w.Write([int]16); $w.Write([int16]1); $w.Write([int16]1); $w.Write([int]$rate); $w.Write([int]($rate * 2)); $w.Write([int16]2); $w.Write([int16]16)
$w.Write([Text.Encoding]::ASCII.GetBytes("data")); $w.Write([int]$data.Length); $w.Write($data); $w.Flush()
[IO.File]::WriteAllBytes($wav, $ms.ToArray()); $w.Dispose()
$doc = Join-Path $Root "note.txt"
[IO.File]::WriteAllText($doc, "A file of a post on the wall.")
$stamp = Get-Date -Format "HHmmss"
$first = "Первая запись Алисы $stamp"
$media = "Пост с фильмом, треком и файлом $stamp"
$theirs = "Запись Бориса на стене Алисы $stamp"
$said = "Комментарий Бориса $stamp"
$env:MONTANA_TRACE = "1"
Remove-Item "$Root\A\trace.log", "$Root\B\trace.log" -ErrorAction SilentlyContinue
$t0 = Get-Date
$B = Start-Montana -DataDir "$Root\B"; Front-Montana -X 920 -Y 40 -Width 900 -Height 950
Start-Sleep -Seconds 2
$A = Start-Montana -DataDir "$Root\A"; Front-Montana -X 0 -Y 40 -Width 900 -Height 950
Start-Sleep -Seconds 2

"A writes on her own wall: words and a picture"
MyPage
Says "Написать на стене" 15
Click-Named "Написать на стене"
Type-Into "Напишите что-нибудь" $first
Click-Named "Фото и видео"; Pick-File $pic
Find-Named "Убрать: wall-test.png" 15 | Out-Null
Click-Named "Опубликовать"
Gone-Named "Новая запись" 90
Says $first 15
Snap "106-A-my-wall"
Click-Named "Назад"

"B opens A's page: her wall comes with the picture"
Use-Montana $B; Front-Montana
PeerPage "Алиса Тест"
Says $first 120
$end = (Get-Date).AddSeconds(60); $got = $null
while ((Get-Date) -lt $end -and -not $got) {
    $got = @(Get-Content "$Root\B\trace.log" -Encoding UTF8 -ErrorAction SilentlyContinue | Where-Object { $_ -like "*wall picture file*" }) | Select-Object -Last 1
    if (-not $got) { Start-Sleep -Milliseconds 500 }
}
if (-not $got) { throw "B never drew the picture's file" }
Find-Named "Фото" 10 | Out-Null
"  B draws the picture's own file: $($got -replace '^\d+ ', '')"
"B likes it and comments on it"
Click-Named "Нравится 0"
Says "Нравится 1" 10
# the comments open on their own page (iOS MTBoardComments); a comment costs B one coin, carried to A
Click-Named "Комментарии 0"
Type-Into "Написать комментарий" $said
Click-Named "Отправить"
Says $said 15
Wrote "B" "wall_do comment words=1" 20
Click-Named "Закрыть"
Gone-Named "Написать комментарий" 10   # the sheet goes down first (0.26 s): its post stands again under it
"B saves A's post, reposts it; its coin is weighed by what B holds -- none from the time cut (iOS 2304, fold-6): refused"
PostMenu $first; Click-Named "Сохранить"
Wrote "B" "wall_do keep words=1" 60
PostMenu $first; Click-Named "Репост"
Wrote "B" "wall_do repost words=1" 60
Click-Named "Подарить монету"
Says "Недостаточно монет" 15
Click-Named "ОК"
Snap "107-B-marks"
"B's menu reports A's post (iOS onReport, Guideline 1.2): the report's page carries the post's words; closed unsent"
PostMenu $first; Press-MenuRow "Пожаловаться"
Says "Причина" 10
Says $first 10
Snap "107-B-report"
Click-Named "Закрыть"
Says $first 15
"B writes a post on A's wall"
Click-Named "Написать на стене" 30
Type-Into "Напишите что-нибудь" $theirs
Click-Named "Опубликовать"
Gone-Named "Новая запись" 90
Says $theirs 15
Snap "107-B-on-A-wall"
Click-Named "Назад"

"A sees B's like, comment and post on her wall"
Use-Montana $A; Front-Montana
MyPage
Says $theirs 120
Says "Нравится 1" 60
Click-Named "Комментарии 1" 60
Says $said 10
# THE CHAIN OF COMMENTS (iOS MTBoardComments): the number in the chain, the moment to the millisecond, the gematria of the seal
$line = @(Get-Texts | Where-Object { $_ -match '^\d+ · \d\d\.\d\d\.\d{4} \d\d:\d\d:\d\d\.\d{3} · gematria \d+$' })
if (-not $line.Count) { throw "no comment wears its number line" }
"  the comment's line: $($line[0])"
"A hides B's comment from her visitors (iOS hideComment)"
# the comment's eye by its whole name: a long post of an earlier run wears «Показать полностью», a text no press moves
Click-Exact "Скрыть"
Find-Exact "Показать" 10 | Out-Null
Snap "108-A-wall-moved"
Click-Named "Закрыть"
# B's marks stand on A's post: kept by A and B, reposted once
Says "Хранители 2" 60
Says "Репост 1" 30
Snap "108-A-wall-marks"
"A's long post folds past its eighth line (iOS MTPostFold): «Показать полностью» under it"
Click-Named "Написать на стене"
Type-Into "Напишите что-нибудь" ("Длинная запись Алисы $stamp. " + ("Слова идут строка за строкой, чтобы пост свернулся после восьмой строки. " * 12))
Click-Named "Опубликовать"
Gone-Named "Новая запись" 90
Says "Показать полностью" 15
Snap "108-A-long-post"
Click-Named "Назад"
"A's Wall of Thoughts holds both"
Open-Drawer; Click-Named "Стена Мыслей"
Says $first 15
Says $theirs 15
"B's Wall of Thoughts holds A's posts on A's wall"
Use-Montana $B; Front-Montana
Open-Drawer; Click-Named "Стена Мыслей"
Says $first 30
Says "На стене: Алиса Тест" 10
Snap "109-B-thoughts"
"B's Wall of Thoughts leads to A's page: by the wall's line over B's own post (iOS wallLink) and by a writer's name (iOS MTBoardOpen)"
Click-Named "На стене: Алиса Тест"
Says "Заблокировать" 15
Click-Named "Назад"
Click-Named "Алиса Тест"
Says "Заблокировать" 15
Click-Named "Назад"
"B no longer reads the hidden comment on A's page: the page's version moved with it"
$end = (Get-Date).AddSeconds(150); $n = 1
while ((Get-Date) -lt $end) {
    PeerPage "Алиса Тест"
    Start-Sleep -Seconds 2
    try { Click-Named "Комментарии 1" 10 } catch {}
    Start-Sleep -Seconds 1
    $n = @(All-Named | Where-Object { try { $_.Current.Name -eq $said } catch { $false } }).Count
    # the list stands open: the hidden comment's number line is on screen, its words are not
    $open = @(Get-Texts | Where-Object { $_ -match '^\d+ · \d\d\.\d\d\.\d{4} .* · gematria \d+$' }).Count
    if ($n -eq 0 -and $open -gt 0) { break }
    $n = 1
    try { Click-Named "Закрыть" 3 } catch {}
    Click-Named "Назад"; Start-Sleep -Seconds 8
}
if ($n -ne 0) { throw "the hidden comment still reads at B" }
"  the comment stands at B without its words"
Click-Named "Закрыть"
Click-Named "Назад"
"A shows it again"
Use-Montana $A; Front-Montana
MyPage
Click-Named "Комментарии 1" 30
Click-Exact "Показать"   # the long post above wears «Показать полностью»: only the eye's own name is pressed
Find-Exact "Скрыть" 10 | Out-Null
Click-Named "Закрыть"
"A's post of a film, a track and a file, kept first as a draft (iOS MTBoardComposer, MTBoardDraftCell): the cross keeps the words,
the wall shows the draft, the page opens as it was left"
Click-Named "Написать на стене"
Type-Into "Напишите что-нибудь" $media
Click-Named "Закрыть"
Says "Черновик" 15
Snap "111-A-draft"
Click-Named "Черновик"
if ($film) { Click-Named "Фото и видео"; Pick-File $film; Find-Named "Убрать: film.mp4" 30 | Out-Null }
Click-Named "Треки и файлы"; Pick-File $wav; Find-Named "Убрать: tone.wav" 30 | Out-Null
Click-Named "Треки и файлы"; Pick-File $doc; Find-Named "Убрать: note.txt" 30 | Out-Null
Start-Sleep -Milliseconds 800; Snap "111-A-composer"
Click-Named "Опубликовать"
# the Wall of Thoughts stands under the page with its corner button «Новая запись»: the page's own field is what leaves
Gone-Named "Напишите что-нибудь" 120
Says $media 15
Wrote "A" "wall posted mine files=$(if ($film) { 3 } else { 2 })" 30
Snap "111-A-media-post"
Click-Named "Назад"
"B plays A's track, opens A's file and plays A's film (iOS MTBoardMediaView: the track's row, the file's row, the viewer)"
Use-Montana $B; Front-Montana
PeerPage "Алиса Тест"
Says $media 120
Click-Named "tone"
Wrote "B" "kind=wav road=wall" 60
Click-Named "note.txt"
Wrote "B" "wall_open" 60
if ($film) {
    Press "Видео"
    Wrote "B" "wall film plays" 60
    Snap "112-B-film"
    Click-Named "Закрыть"
}
"B's comment carries the post's link, and the link opens the post here (iOS MTBoardComments.open, MTPostLinkPeek)"
$posted = @(Get-Content "$Root\A\trace.log" -Encoding UTF8 | Where-Object { $_ -like "*wall posted mine files=*id=*" }) | Select-Object -Last 1
$link = "montana://wall/post/" + ($posted -replace '.*id=', '').Trim()
Click-Named "Комментарии 0"
Type-Into "Написать комментарий" "Ссылка на пост $link"
Click-Named "Отправить"
Says $link 20
Click-Named $link
Wrote "B" "wall_link opens post" 20
Snap "113-B-link-post"
Click-Named "Закрыть"; Start-Sleep -Milliseconds 500; Click-Named "Закрыть"
Click-Named "Назад"
Use-Montana $B; Front-Montana
"A's page ground reaches B (iOS «PG:»): A chooses «Индиго»; A's page at B stands on it, B's own pages on gold"
Use-Montana $A; Front-Montana
Click-Named "Чаты"
Page-Ground "Индиго"
Use-Montana $B; Front-Montana
$end = (Get-Date).AddSeconds(150); $share = 0
while ((Get-Date) -lt $end) {
    PeerPage "Алиса Тест"
    Start-Sleep -Seconds 2
    $share = Share 0.02 0.12 0.2 0.8 $blue
    if ($share -ge 0.6) { break }
    try { Click-Named "Закрыть" 3 } catch {}
    Click-Named "Назад"; Start-Sleep -Seconds 8
}
if ($share -lt 0.6) { throw "A's page ground never reached B ($([int]($share * 100))%)" }
"  A's page at B stands on indigo ($([int]($share * 100))% of the points)"
Snap "110-B-A-page-ground"
Click-Named "Назад"
if ((Share 0.02 0.12 0.2 0.8 $blue) -ge 0.3) { throw "B's own page is not on its default ground" }
"  B's own page still stands on its default ground"
Use-Montana $A; Front-Montana
Page-Ground "По умолчанию"   # the gold is gone whole (iOS 2304): the default is A's page's ground again
# A RULE OF THE WALL LEFT BY «НАЗАД» (the freeze of 25.10.2026, Wall.jsx WallRules: the rule is a step of «Стена»): «Стена» must stand
# again within 2 s -- not «leaving», inert under the window's foot -- and the window answer after the way out; no rule is changed
"A's wall rules: a rule's page left by «Назад» brings «Стена» back, and the window answers"
# a rule's row is one button UI Automation names «<rule> <value>» (read on the live window 26.10.2026), so the row is pressed and
# proved by that whole name; nothing above changed a rule, so both stand on «Все»
Open-Drawer; Press-Exact "Настройки"
Page-Drawn "Настройки" "Уведомления и звуки"; Start-Sleep -Milliseconds 450
Press-In-Page "Настройки" "Приватность"; Page-Drawn "Приватность" "Заблокированные"; Start-Sleep -Milliseconds 400
Press-In-Page "Приватность" "Стена"; Page-Drawn "Стена" "Кто может видеть мою стену Все" 10; Start-Sleep -Milliseconds 400
Press-In-Page "Стена" "Кто может писать на моей стене Все"; Page-Drawn "Кто может писать на моей стене" "Только я"; Start-Sleep -Milliseconds 400
Press-In-Page "Кто может писать на моей стене" "Назад"; Page-Left "Кто может писать на моей стене" "Только я"
Page-Drawn "Стена" "Кто может видеть мою стену Все"; Start-Sleep -Milliseconds 400
Press-In-Page "Стена" "Назад"; Page-Left "Стена" "Кто может видеть мою стену Все"
Page-Drawn "Приватность" "Заблокированные"; Start-Sleep -Milliseconds 400
Press-In-Page "Приватность" "Назад"; Page-Left "Приватность" "Заблокированные"
Page-Drawn "Настройки" "Уведомления и звуки"; Start-Sleep -Milliseconds 300
Press-In-Page "Настройки" "Закрыть"; Page-Left "Настройки" "Уведомления и звуки"
Window-Alive "a wall rule → «Назад» → «Назад» → «Назад» → «Закрыть»"
"done in $([int]((Get-Date) - $t0).TotalSeconds) s"
Use-Montana $A; Stop-Montana; Use-Montana $B; Stop-Montana
