# A FILE LARGER THAN 200 MB, LIVE (iOS MediaSource.file, downloadToFile; after tools\ab.ps1 with the same -Root): the check
# makes a WAV of its own of 201 MB (a drawn tone, one second written 1195 times); B picks it in Windows' Open dialog, the
# window hands it eight pieces at a time («Файл готовится: N%»), the pieces go up one at a time and the letter is «Отправлено».
# A taps the plate (a big file waits for the tap), the pieces come down one at a time into A's store; A's second tap writes
# the file out (a check's folder keeps it in A\Downloads, no program is started) and its SHA-256 is the very one B picked.
# Then A's «Музыка» plays it by the file road -- the player's ranges, each read from the pieces it crosses (A's diary says so).
# The pieces ride the nodes' blind store: about 280 MB up and as much down.
# usage: tools\bigfile.ps1 -Root DIR [-Shots DIR]
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
# the file: a WAV header and one second of a tone, 44 100 Hz, 16 bits, two channels, written 1195 times -- 210 798 044 bytes
$big = Join-Path $Root "Большая запись.wav"
$rate = 44100; $second = New-Object byte[] ($rate * 4)
for ($i = 0; $i -lt $rate; $i++) {
    $v = [int16](6000 * [Math]::Sin(2 * [Math]::PI * 330 * $i / $rate)); $b = [BitConverter]::GetBytes($v)
    $second[4 * $i] = $b[0]; $second[4 * $i + 1] = $b[1]; $second[4 * $i + 2] = $b[0]; $second[4 * $i + 3] = $b[1]
}
$data = $second.Length * 1195
$f = [IO.File]::Create($big); $w = New-Object IO.BinaryWriter $f
$w.Write([Text.Encoding]::ASCII.GetBytes("RIFF")); $w.Write([int](36 + $data)); $w.Write([Text.Encoding]::ASCII.GetBytes("WAVEfmt "))
$w.Write([int]16); $w.Write([int16]1); $w.Write([int16]2); $w.Write([int]$rate); $w.Write([int]($rate * 4)); $w.Write([int16]4); $w.Write([int16]16)
$w.Write([Text.Encoding]::ASCII.GetBytes("data")); $w.Write([int]$data)
for ($s = 0; $s -lt 1195; $s++) { $w.Write($second) }
$w.Close()
$size = (Get-Item $big).Length
if ($size -le 200MB) { throw "the file is not larger than 200 MB: $size" }
$sha = (Get-FileHash $big -Algorithm SHA256).Hash
"the file: $size bytes, SHA-256 $($sha.Substring(0, 16))…"
Remove-Item "$Root\A\trace.log", "$Root\B\trace.log" -ErrorAction SilentlyContinue
Remove-Item "$Root\A\Downloads" -Recurse -Force -ErrorAction SilentlyContinue

$A = Start-Montana -DataDir "$Root\A"; Front-Montana -X 0 -Y 40 -Width 900 -Height 900
$B = Start-Montana -DataDir "$Root\B"; Front-Montana -X 920 -Y 40 -Width 900 -Height 900
"B picks the big file"
Click-Named "Алиса Тест"
Files-Key; Pick-File $big
try { Says "Файл готовится" 30 } catch { "  (the share passed too fast to be seen)" }
Says "Большая запись.wav" 300
$t1 = Get-Date
Says "Отправлено" 1200
"  handed and laid on the nodes in $([int]((Get-Date) - $t1).TotalSeconds) s after the letter stood"
Snap "130-B-bigfile"

"A taps the plate: the pieces come down into A's store; the second tap writes the file out"
Use-Montana $A; Front-Montana
Click-Named "Борис Тест"
Says "Большая запись.wav" 120
Says "210,8 МБ" 10   # the size as iOS says it (.byteCount(style: .file): units of 1000)
$t2 = Get-Date; $end = $t2.AddSeconds(1500); $out = $false
do {
    Click-Named "Большая запись.wav"
    $out = Wrote "A" "media_open $size bytes" 15
} while (-not $out -and (Get-Date) -lt $end)
if (-not $out) { throw "A never wrote the file out" }
"  came down in $([int]((Get-Date) - $t2).TotalSeconds) s"
$got = Join-Path "$Root\A\Downloads" "Большая запись.wav"
$theirs = (Get-FileHash $got -Algorithm SHA256).Hash
if ($theirs -ne $sha) { throw "A's file is not B's: $theirs" }
"  A's file is B's very file (SHA-256 alike)"
Snap "131-A-bigfile"

"A plays it on the music page, by the file road"
Front-Montana -X 0 -Y 40 -Width 1500 -Height 950   # the drawer stands beside the chats at this width
Start-Sleep -Seconds 1
Click-Named "Музыка"
Click-Named "Большая запись"
if (-not (Wrote "A" "kind=wav road=file" 30)) { throw "the big track did not play" }
Click-Named "Большая запись"
Remove-Item $got -ErrorAction SilentlyContinue
Remove-Item $big -ErrorAction SilentlyContinue
"done in $([int]((Get-Date) - $t0).TotalSeconds) s"
Use-Montana $A; Stop-Montana; Use-Montana $B; Stop-Montana
