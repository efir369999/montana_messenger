# A ROUND VIDEO NOTE, IN THE WINDOWS (after tools\ab.ps1 with the same -Root), on WebView2's test devices -- a drawn camera, a
# made-up microphone; no camera or microphone of this computer is opened: A presses «Видеосообщение», the circle records for
# three seconds and leaves; A's letter is a round note of its seconds (an MP4, H.264 and AAC), and B gets it as a round note
# whose file its window decodes (the diary names the picture's size). The camera runs at the height of the quality of
# Appearance (iOS MontanaNoteQuality, medium -- 720 -- by default) and the file's square stays 480.
# usage: tools\note.ps1 -Root DIR [-Shots DIR]
param([Parameter(Mandatory = $true)][string]$Root, [string]$Shots = "")
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ui.ps1"
function Snap($name) { if ($Shots) { Shot-Montana (Join-Path $Shots "$name.png") } }
function Says([string]$text, [int]$timeout = 60) { Find-Named $text $timeout | Out-Null; "  sees: $text" }
$env:MONTANA_TRACE = "1"
Remove-Item "$Root\A\trace.log", "$Root\B\trace.log" -ErrorAction SilentlyContinue
$t0 = Get-Date
$B = Start-Montana -DataDir "$Root\B"; Front-Montana -X 920 -Y 40 -Width 900 -Height 900
Start-Sleep -Seconds 2
$A = Start-Montana -DataDir "$Root\A" -FakeMedia; Front-Montana -X 0 -Y 40 -Width 900 -Height 900
Start-Sleep -Seconds 2
"A records a round note"
Click-Named "Борис Тест"
$before = @(Get-Texts | Where-Object { $_ -like "Видеосообщение *" }).Count
# a tap turns the key to the camera, a hold carried up locks the round's tape: it rolls on with its bin and its send (iOS)
Media-Mode "Видеосообщение"
Hold-Named "Видеосообщение" 1.2 -Lock
Find-Named "Отмена" 10 | Out-Null
Start-Sleep -Seconds 3
Snap "84-A-recording"
$cam = Get-Content "$Root\A\trace.log" -Encoding UTF8 -ErrorAction SilentlyContinue | Where-Object { $_ -like "* note camera *" } | Select-Object -Last 1
if ($cam -notmatch "note camera medium \d+ rate 1500000") { throw "the note did not take the medium quality: $cam" }
"  A: $($cam -replace '^\d+ ', '')"
Click-Named "Отправить"
Sent-Settle 60
$end = (Get-Date).AddSeconds(30)
while ((Get-Date) -lt $end -and @(Get-Texts | Where-Object { $_ -like "Видеосообщение 0:0*" }).Count -le $before) { Start-Sleep -Milliseconds 500 }
if (@(Get-Texts | Where-Object { $_ -like "Видеосообщение 0:0*" }).Count -le $before) { throw "A's letter is no round note" }
"  A: the letter is a round note of its seconds"
"B gets a round note"
Use-Montana $B; Front-Montana
Click-Named "Алиса Тест"
Says "Видеосообщение 0:0" 90
$end = (Get-Date).AddSeconds(60); $line = $null
while ((Get-Date) -lt $end -and -not $line) {
    $line = @(Get-Content "$Root\B\trace.log" -Encoding UTF8 -ErrorAction SilentlyContinue | Where-Object { $_ -match "media note theirs (\d+)x(\d+)" -and [int]$Matches[1] -gt 0 }) | Select-Object -Last 1
    if (-not $line) { Start-Sleep -Milliseconds 500 }
}
if (-not $line) { throw "B never decoded the note: " + (@(Get-Content "$Root\B\trace.log" -ErrorAction SilentlyContinue | Where-Object { $_ -like "* media note*" }) -join " | ") }
"  B decodes it: $($line -replace '^\d+ ', '')"
if ($line -notmatch "480x480") { throw "the note's square is not 480: $line" }
Snap "85-B-note"
"done in $([int]((Get-Date) - $t0).TotalSeconds) s"
Use-Montana $A; Stop-Montana; Use-Montana $B; Stop-Montana
