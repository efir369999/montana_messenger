# HOLD AND PICTURES ASKED IN A VOICE CALL, LIVE (after tools\ab.ps1 with the same -Root), on WebView2's own test devices -- a drawn
# camera, a made-up microphone, no sound out; no camera or microphone of this computer is opened: A calls B by voice; A holds
# the call -- both see «На удержании» -- and takes it back; A asks for pictures, B sees «Алиса Тест звонит по видео» and says yes
# -- both cameras come in and frames flow both ways (the diaries name them); A presses «Видео» again -- A's camera rests and B's
# picture stays on A's screen, B covers A (iOS 2304 «call-camera-off»); B presses «Видео» -- the last live camera leaves and both
# return to voice; A asks again and B says no -- A's ask ends.
# usage: tools\callvideo.ps1 -Root DIR [-Shots DIR]
param([Parameter(Mandatory = $true)][string]$Root, [string]$Shots = "")
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ui.ps1"
function Snap($name) { if ($Shots) { Shot-Montana (Join-Path $Shots "$name.png") } }
function Says([string]$text, [int]$timeout = 60) { Find-Named $text $timeout | Out-Null; "  sees: $text" }
function Talking([int]$timeout = 40) {
    $end = (Get-Date).AddSeconds($timeout)
    while ((Get-Date) -lt $end) { if ((Call-Timer) -ge 1) { return }; Start-Sleep -Milliseconds 500 }
    throw "the call never connected"
}
function Pressed([string]$name) {
    $e = Find-Named $name 5; $p = $null
    if (-not $e.TryGetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern, [ref]$p)) { throw "'$name' is no toggle" }
    $p.Current.ToggleState -eq [System.Windows.Automation.ToggleState]::On
}
function Diary([string]$who) { @(Get-Content "$Root\$who\trace.log" -Encoding UTF8 -ErrorAction SilentlyContinue) }
function Wrote([string]$who, [string]$line, [int]$timeout = 20) {
    $end = (Get-Date).AddSeconds($timeout)
    do { if (Diary $who | Where-Object { $_ -like "* call $line*" }) { "  ${who}: $line"; return }; Start-Sleep -Milliseconds 500 } while ((Get-Date) -lt $end)
    throw "${who} never wrote '$line'"
}
function Picture([string]$who, [int]$timeout = 25) {
    $end = (Get-Date).AddSeconds($timeout)
    $last = ""
    do {
        foreach ($l in (Diary $who | Where-Object { $_ -match "call picture seen " })) {
            $last = $l
            if ($l -match "call picture seen (\d+)x(\d+) in=(\d+)" -and [int]$Matches[1] -gt 0 -and [int]$Matches[3] -gt 0) {
                "  ${who}: picture $($Matches[1])x$($Matches[2]), $($Matches[3]) frames"; return
            }
        }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $end)
    throw "${who}: no picture: $last"
}
$env:MONTANA_TRACE = "1"
foreach ($w in @("A", "B")) { Remove-Item "$Root\$w\trace.log" -ErrorAction SilentlyContinue }
$t0 = Get-Date
$B = Start-Montana -DataDir "$Root\B" -FakeMedia; Front-Montana -X 920 -Y 40 -Width 900 -Height 900
Start-Sleep -Seconds 2
$A = Start-Montana -DataDir "$Root\A" -FakeMedia; Front-Montana -X 0 -Y 40 -Width 900 -Height 900
Start-Sleep -Seconds 2
"A calls B by voice"
Click-Named "Борис Тест"; Click-Named "Позвонить"; Click-Named "Аудиозвонок"
Use-Montana $B; Front-Montana
Says "Принять" 60
Click-Named "Принять"
Talking 40
Use-Montana $A; Front-Montana
Talking 20
"A holds the call and takes it back"
Click-Named "Удержать"
Says "На удержании" 5
Use-Montana $B; Front-Montana
Says "На удержании" 30
Use-Montana $A; Front-Montana
Click-Named "Удержать"
Use-Montana $B; Front-Montana
Gone-Named "На удержании" 30
"  B: the hold is over"
"A asks for pictures; B says yes"
Use-Montana $A; Front-Montana
Click-Named "Видео"
Use-Montana $B; Front-Montana
Says "Алиса Тест звонит по видео" 30
Snap "74-B-asked"
Click-Named "Принять"
Picture "B"
Picture "A"
Snap "75-B-pictures"
"A rests its camera: B's picture stays at A, B covers A"
Use-Montana $A; Front-Montana
Click-Named "Видео"
Wrote "A" "my camera rests, the peer's picture stays"
Wrote "B" "peer's camera rests mine=live"
# the key wears its plate while my camera lives, as iOS's (video && !cameraOff): resting, it stands unlit; B's stays lit
if (Pressed "Видео") { throw "A: «Видео» still lit while A's camera rests" }
"  A: «Видео» unlit while the camera rests"
Snap "76-A-camera-rests"
"B leaves its camera too: the last live one -- both return to voice"
Use-Montana $B; Front-Montana
if (-not (Pressed "Видео")) { throw "B: «Видео» unlit while B's camera lives" }
"  B: «Видео» lit"
Click-Named "Видео"
Wrote "B" "video mode ended tell=true"
Wrote "A" "video mode ended tell=false"
Use-Montana $A; Front-Montana
"A asks again; B says no"
Click-Named "Видео"
Use-Montana $B; Front-Montana
Says "Алиса Тест звонит по видео" 30
Click-Named "Отклонить"
Wrote "A" "video consent declined"
Use-Montana $A; Front-Montana
Click-Named "Отбой"
Use-Montana $B
Says "Звонок завершён" 30
"done in $([int]((Get-Date) - $t0).TotalSeconds) s"
Use-Montana $A; Stop-Montana; Use-Montana $B; Stop-Montana
