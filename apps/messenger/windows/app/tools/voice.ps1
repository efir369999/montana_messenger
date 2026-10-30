# A VOICE IN THE ONE PLAYER, LIVE (iOS MessageBubble's voice, MTVoiceRound, MTWaveform, VoicePlayer.playVoice, MontanaPlayerBar; after
# tools\ab.ps1 with the same -Root), on WebView2's test devices -- a made-up microphone; no microphone of this computer is opened:
# A records three seconds and sends; B sees the voice's capsule -- its round of glass, its wave, its length -- and the microphone's
# pill under it; a tap on the capsule plays the voice in the one player: the bar stands with the speaker's name and the speed, a tap
# on the speed turns it to 1.5×, the close takes the bar down.
# usage: tools\voice.ps1 -Root DIR [-Shots DIR]
param([Parameter(Mandatory = $true)][string]$Root, [string]$Shots = "")
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ui.ps1"
function Snap($name) { if ($Shots) { Shot-Montana (Join-Path $Shots "$name.png") } }
function Says([string]$text, [int]$timeout = 30) { Find-Named $text $timeout | Out-Null; "  sees: $text" }
function Wrote([string]$who, [string]$line, [int]$timeout = 20) {
    $end = (Get-Date).AddSeconds($timeout)
    do { $hit = Get-Content "$Root\$who\trace.log" -Encoding UTF8 -ErrorAction SilentlyContinue | Where-Object { $_ -like "*$line*" } | Select-Object -Last 1; if ($hit) { "  ${who}: $($hit -replace '^\d+ ', '')"; return }; Start-Sleep -Milliseconds 500 } while ((Get-Date) -lt $end)
    throw "$who never wrote '$line'"
}
$env:MONTANA_TRACE = "1"
foreach ($w in @("A", "B")) { Remove-Item "$Root\$w\trace.log" -ErrorAction SilentlyContinue }
$t0 = Get-Date
$B = Start-Montana -DataDir "$Root\B" -FakeMedia; Front-Montana -X 920 -Y 40 -Width 900 -Height 900
Start-Sleep -Seconds 2
$A = Start-Montana -DataDir "$Root\A" -FakeMedia; Front-Montana -X 0 -Y 40 -Width 900 -Height 900
Start-Sleep -Seconds 2
"A records three seconds and sends"
Click-Named "Борис Тест"
# THE KEY HELD RECORDS, LET GO IT SENDS (iOS MontanaHoldControl): the microphone's mode, three seconds under the button
Media-Mode "Голосовое сообщение"
Hold-Named "Голосовое сообщение" 3.5
Sent-Settle
Use-Montana $B; Front-Montana
"B sees the voice's capsule: the round, the wave, the length; the microphone's pill under it"
Click-Named "Алиса Тест"
$end = (Get-Date).AddSeconds(90)
while (-not (Get-Texts | Where-Object { $_ -match "^0:0[2-4]$" })) { if ((Get-Date) -gt $end) { throw "no voice of three seconds stands" }; Start-Sleep -Milliseconds 500 }
Wrote "B" "voice wave read bars=60" 20   # the wave is read off the file once it is here
Snap "180-B-voice"
"B taps the capsule: the voice plays in the one player, the bar stands with A's name and the speed"
# the newest voice, the one just sent: its file may still be on its way (the round shows the arrow) -- a tap asks it, the next plays
$end = (Get-Date).AddSeconds(60)
do {
    Click-Class "voice-capsule" 0.5 -Last
    $tap = (Get-Date).AddSeconds(2)
    do {
        Start-Sleep -Milliseconds 150
        $played = Get-Content (Join-Path $Root "B\trace.log") -Encoding UTF8 -ErrorAction SilentlyContinue | Where-Object { $_ -like "*voice_play queue=*" }
    } while (-not $played -and (Get-Date) -lt $tap)
} while (-not $played -and (Get-Date) -lt $end)
Wrote "B" "voice_play queue=" 5
Click-Named "Пауза" 5   # three seconds are short: the voice rests where it stands, and its bar stays
Says "Плеер" 10
Snap "181-B-voice-playing"
# the speed is kept across launches (iOS voiceRate): a tap on its room turns it one step round 1 → 1.5 → 2, and the check leaves 1×
$rates = { @(Get-Content (Join-Path $Root "B\trace.log") -Encoding UTF8 -ErrorAction SilentlyContinue | Where-Object { $_ -like "*voice rate *" }) }
$before = (& $rates).Count
Click-Class "mini-plate" 0.95
Start-Sleep -Milliseconds 500
if ((& $rates).Count -le $before) { throw "a tap on the speed's room turned nothing" }
"  the speed turns: $(((& $rates) | Select-Object -Last 1) -replace '^\d+ ', '')"
for ($k = 0; $k -lt 3 -and -not (((& $rates) | Select-Object -Last 1) -like "*voice rate 1"); $k++) { Click-Class "mini-plate" 0.95; Start-Sleep -Milliseconds 400 }
Click-Named "Закрыть"
Gone-Named "Плеер" 10
"  the close took the bar down"
"done in $([int]((Get-Date) - $t0).TotalSeconds) s"
Use-Montana $A; Stop-Montana; Use-Montana $B; Stop-Montana
