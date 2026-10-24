# THE PERSON'S OWN MUSIC AND THE SHARE SHEET (iOS MTMusicFolders, UIActivityViewController; after tools\ab.ps1 with the same -Root):
# the check makes a folder with two tracks of its own (a drawn tone, WAV) in a subfolder; A's «Музыка» → «Добавить папку» opens
# Windows' own folder picker, the folder is lent, the page shows both tracks by their names (never their place); a row plays in the
# one player with the list as its queue, the bar stands, «Следующий трек» plays the other; a tap on the mini's name unfolds the big
# player -- the repeat says «Повтор трека», «Текущий плейлист» opens the queue's page «Играет из: …» -- the name folds it back
# and the close takes the bar down (A's diary says so). A lent folder is never taken back (iOS MTMusicFolders). Then «Мой код и ссылка» → «Поделиться» opens Windows' own
# share sheet over the window (A's diary says so), and the check closes it.
# usage: tools\music.ps1 -Root DIR [-Shots DIR]
param([Parameter(Mandatory = $true)][string]$Root, [string]$Shots = "")
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ui.ps1"
function Snap($name) { if ($Shots) { Shot-Montana (Join-Path $Shots "$name.png") } }
function Says([string]$text, [int]$timeout = 30) { Find-Named $text $timeout | Out-Null; "  sees: $text" }
function Wrote([string]$line, [int]$timeout = 20) {
    $end = (Get-Date).AddSeconds($timeout)
    do { $hit = Get-Content "$Root\A\trace.log" -Encoding UTF8 -ErrorAction SilentlyContinue | Where-Object { $_ -like "*$line*" } | Select-Object -Last 1; if ($hit) { "  A: $($hit -replace '^\d+ ', '')"; return }; Start-Sleep -Milliseconds 500 } while ((Get-Date) -lt $end)
    throw "A never wrote '$line'"
}
# a WAV of a tone, made here: 1.5 s, 22 050 Hz, 16 bits, one channel -- nothing of this computer's own music is touched; with a
# title, its «id3 » chunk names it (ID3v2.4, TIT2 and TPE1 in UTF-8: the shape trackmeta's own test reads)
function Syncsafe([int]$n) { [byte[]]@((($n -shr 21) -band 0x7f), (($n -shr 14) -band 0x7f), (($n -shr 7) -band 0x7f), ($n -band 0x7f)) }
function Frame([string]$id, [string]$text) {
    $body = [byte[]](@([byte]3) + [Text.Encoding]::UTF8.GetBytes($text))
    [byte[]]([Text.Encoding]::ASCII.GetBytes($id) + (Syncsafe $body.Length) + [byte[]]@(0, 0) + $body)
}
function Tone([string]$path, [double]$hz, [string]$title = "", [string]$artist = "", [double]$secs = 1.5) {
    $rate = 22050; $n = [int]($rate * $secs)
    $chunk = [byte[]]@()
    if ($title) {
        $frames = [byte[]]((Frame "TIT2" $title) + (Frame "TPE1" $artist))
        $tag = [byte[]]([Text.Encoding]::ASCII.GetBytes("ID3") + [byte[]]@(4, 0, 0) + (Syncsafe $frames.Length) + $frames)
        $chunk = [byte[]]([Text.Encoding]::ASCII.GetBytes("id3 ") + [BitConverter]::GetBytes([int]$tag.Length) + $tag)
        if ($tag.Length % 2) { $chunk = [byte[]]($chunk + [byte[]]@(0)) }
    }
    $ms = New-Object IO.MemoryStream; $w = New-Object IO.BinaryWriter $ms
    $w.Write([Text.Encoding]::ASCII.GetBytes("RIFF")); $w.Write([int](36 + $n * 2 + $chunk.Length)); $w.Write([Text.Encoding]::ASCII.GetBytes("WAVEfmt "))
    $w.Write([int]16); $w.Write([int16]1); $w.Write([int16]1); $w.Write([int]$rate); $w.Write([int]($rate * 2)); $w.Write([int16]2); $w.Write([int16]16)
    $w.Write([Text.Encoding]::ASCII.GetBytes("data")); $w.Write([int]($n * 2))
    for ($i = 0; $i -lt $n; $i++) { $w.Write([int16](8000 * [Math]::Sin(2 * [Math]::PI * $hz * $i / $rate))) }
    if ($chunk.Length) { $w.Write($chunk) }
    $w.Flush(); [IO.File]::WriteAllBytes($path, $ms.ToArray()); $w.Close()
}
$env:MONTANA_TRACE = "1"
Remove-Item "$Root\A\trace.log" -ErrorAction SilentlyContinue
$lent = Join-Path $Root "music-lent"
if (Test-Path $lent) { Remove-Item -Recurse -Force $lent }
New-Item -ItemType Directory -Force (Join-Path $lent "Альбом") | Out-Null
Tone (Join-Path $lent "Тон ля.wav") 440 "Ля первой октавы" "Проверка Montana"
Tone (Join-Path $lent "Альбом\Тон до.wav") 523
# a name longer than the mini's room: it runs past it (iOS MTMarquee), a name that fits stands still
Tone (Join-Path $lent "Тон ми.wav") 659 "Ми первой октавы, сыгранная очень долго и медленно, пока не кончится строка" "Проверка Montana" 20
$t0 = Get-Date
$A = Start-Montana -DataDir "$Root\A"; Front-Montana -X 0 -Y 40 -Width 1500 -Height 950
Start-Sleep -Seconds 2
"A lends a folder to the music page"
Click-Named "Музыка"
Click-Named "Добавить папку"
Pick-File $lent 20
Says "Ля первой октавы" 20   # the row says the track's tag (iOS MTTrackMeta): its file «Тон ля» names itself so
Says "Тон до" 10             # a track with no tag says its file's name
Says "0:01" 10               # and its length the file's own (1.5 s)
# a path -- the folder's or a track's -- never stands
if (Get-Texts | Where-Object { $_ -like "*$lent*" -or $_ -match "[A-Za-z]:\\" }) { throw "a place stands on the page" }
Snap "120-A-music"
"the one player (iOS VoicePlayer, MontanaPlayerBar): a row plays with the list as the queue, the bar stands, the track after follows"
Click-Named "Ля первой октавы"
Wrote "music_play i=" 20
Snap "121-A-music-bar"
Says "Плеер" 10
Click-Named "Следующий трек"
Wrote "music mini next" 10
Click-Named "Ми первой октавы, сыгранная очень долго и медленно, пока не кончится строка"
Wrote "marquee runs" 10   # the long name runs in the mini; the shots 3 s apart catch it in two places
Snap "121b-A-marquee-1"; Start-Sleep -Seconds 3; Snap "121c-A-marquee-2"
$plays = @(Get-Content (Join-Path $Root "A\trace.log") -Encoding UTF8 | Where-Object { $_ -like "*music_play i=*" }).Count
if ($plays -lt 2) { throw "the track after never played ($plays plays)" }
"  the track after plays ($plays plays)"
"the mini unfolds where it stands at a tap on its name (iOS MTPlayerHead): the big player's plate, the repeat said under the name,"
"the playlist's own page; the name folds it back"
Click-Class "mini-plate" 0.3
Wrote "music mini unfolds" 10
Says "Текущий плейлист" 10
Click-Named "Повтор"
Wrote "music repeat track" 5   # «Повтор трека» stands under the name two seconds (the shot holds it)
Snap "122-A-big-player"
Click-Named "Текущий плейлист"
Says "Сейчас играет" 10
Says "Проверка Montana" 10   # the artist the file's own tag names, under its name
# the queue's source over its rows, in the capitals of a section's head (iOS «Playing from …»)
$end = (Get-Date).AddSeconds(5)
while (-not (Get-Texts | Where-Object { $_ -imatch "^играет из:" })) { if ((Get-Date) -gt $end) { throw "the queue's page names no source" }; Start-Sleep -Milliseconds 300 }
Snap "123-A-queue"
Click-Named "Закрыть"
Gone-Named "Сейчас играет" 10
Click-Class "head-words" 0.5
Wrote "music mini folds" 10
Click-Named "Закрыть"
Gone-Named "Плеер" 10
"  the close took the bar down"
"A shares the link through Windows' own sheet"
Click-Named "Чаты"
Click-Named "Написать"; Click-Named "Мой код и ссылка"
Says "Поделиться" 10
Click-Named "Поделиться"
Wrote "share sheet shown=true" 15
Start-Sleep -Seconds 2
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.SendKeys]::SendWait("{ESC}")   # the sheet takes the keys while it stands; the check closes it
Start-Sleep -Seconds 1
Front-Montana
Click-Named "Закрыть"
"done in $([int]((Get-Date) - $t0).TotalSeconds) s"
Stop-Montana
