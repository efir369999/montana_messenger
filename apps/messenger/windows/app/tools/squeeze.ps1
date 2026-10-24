# A FILM MADE LIGHT BEFORE IT GOES, LIVE (iOS MontanaVideo.compressResumable; after tools\ab.ps1 with the same -Root): the check
# makes a dense film of its own with the machine's ffmpeg (1920 x 1080, 30 frames a second, 12 s, H.264 at 10 Mbit/s and a tone as
# AAC, in a .mov -- what a camera hands); B picks it in Windows' Open dialog, the letter stands at once and its bubble wears the
# pill of iOS -- the ring and «Сжатие N%» while Media Foundation writes it again within the 960 x 540 box, then the share of its
# pieces --, and B's diary says the road («video road=written 1920x1080->960x540»). The letter is «Отправлено»; A's window
# reads the film that came: 960 x 540, an mp4, lighter than the source.
# usage: tools\squeeze.ps1 -Root DIR [-Shots DIR]
param([Parameter(Mandatory = $true)][string]$Root, [string]$Shots = "")
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ui.ps1"
function Snap($name) { if ($Shots) { Shot-Montana (Join-Path $Shots "$name.png") } }
function Says([string]$text, [int]$timeout = 60) { Find-Named $text $timeout | Out-Null; "  sees: $text" }
function Wrote([string]$who, [string]$line, [int]$timeout = 20) {
    $end = (Get-Date).AddSeconds($timeout)
    do { $hit = Get-Content "$Root\$who\trace.log" -Encoding UTF8 -ErrorAction SilentlyContinue | Where-Object { $_ -like "*$line*" } | Select-Object -Last 1; if ($hit) { "  ${who}: $($hit -replace '^\d+ ', '')"; return $true }; Start-Sleep -Milliseconds 500 } while ((Get-Date) -lt $end)
    $false
}
$env:MONTANA_TRACE = "1"
$t0 = Get-Date
$ffmpeg = (Get-Command ffmpeg -ErrorAction SilentlyContinue).Source
if (-not $ffmpeg) { throw "no ffmpeg on this machine to make the check's film" }
$film = Join-Path $Root "Плотный фильм.mov"
Remove-Item $film -ErrorAction SilentlyContinue
& $ffmpeg -hide_banner -loglevel error -f lavfi -i "testsrc2=size=1920x1080:rate=30,noise=alls=24:allf=t" -f lavfi -i "sine=frequency=440:sample_rate=48000" `
    -t 12 -c:v libx264 -b:v 10M -maxrate 10M -bufsize 20M -pix_fmt yuv420p -c:a aac -b:a 128k -ac 2 $film
if (-not (Test-Path $film)) { throw "ffmpeg made no film" }
$size = (Get-Item $film).Length
"the film: 1920 x 1080, 12 s, $size bytes"
Remove-Item "$Root\A\trace.log", "$Root\B\trace.log" -ErrorAction SilentlyContinue

$A = Start-Montana -DataDir "$Root\A"; Front-Montana -X 0 -Y 40 -Width 900 -Height 900
$B = Start-Montana -DataDir "$Root\B"; Front-Montana -X 920 -Y 40 -Width 900 -Height 900
"B picks the film: the letter stands, its pill says the writing"
Click-Named "Алиса Тест"
Files-Key
try { Pick-File $film } catch { "  (the Open dialog was slow to come: the button again)"; Files-Key; Pick-File $film 30 }
$end = (Get-Date).AddSeconds(60); $pill = $null
while (-not $pill -and (Get-Date) -lt $end) {
    $pill = Get-Texts | Where-Object { $_ -match '^(В очереди|Сжатие( \d+%)?)$' } | Select-Object -First 1
    if (-not $pill) { Start-Sleep -Milliseconds 200 }
}
if (-not $pill) { throw "no pill of the writing on B's bubble" }
"  sees: $pill"
Snap "160-B-squeeze"
if (-not (Wrote "B" "video road=written 1920x1080->960x540" 240)) { throw "B's film was not written again" }
$written = [long]((Get-Content "$Root\B\trace.log" -Encoding UTF8 | Where-Object { $_ -like "*video road=written*" } | Select-Object -Last 1) -replace '.*bytes=(\d+).*', '$1')
$end = (Get-Date).AddSeconds(30); $up = $null
while (-not $up -and (Get-Date) -lt $end) { $up = Get-Texts | Where-Object { $_ -match '^\d+%$' } | Select-Object -First 1; if (-not $up) { Start-Sleep -Milliseconds 150 } }
if ($up) { "  sees the pieces going: $up"; Snap "161-B-pieces" } else { "  (the pieces went up too fast to be seen)" }
Says "Отправлено" 300
Snap "162-B-sent"

"A reads the film that came"
Use-Montana $A; Front-Montana
Click-Named "Борис Тест"
$end = (Get-Date).AddSeconds(240); $came = $false
while (-not $came -and (Get-Date) -lt $end) { $came = Wrote "A" "media film theirs 960x540 mp4 $written" 10 }   # this very film, by its size
if (-not $came) { throw "A did not read B's written film (960 x 540, mp4, $written bytes)" }
if ($written -le 0 -or $written -ge $size / 2) { throw "the film that came is not lighter: $written of $size" }
"  A's film: $written bytes of B's $size"
# the feed opened at its newest end and stays there while the pictures above come in (iOS stickBottom)
Start-Sleep -Seconds 2
Snap "163-A-film"
Remove-Item $film -ErrorAction SilentlyContinue
"done in $([int]((Get-Date) - $t0).TotalSeconds) s"
Use-Montana $A; Stop-Montana; Use-Montana $B; Stop-Montana
