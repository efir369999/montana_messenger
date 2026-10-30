# A SCREEN AND A PICTURE IN A CALL, LIVE (after tools\ab.ps1 with the same -Root), on WebView2's own test devices -- a drawn
# camera, a drawn screen, a made-up microphone, no sound out; no camera, microphone or screen of this computer is opened:
# A calls B by voice and shows its screen -- B gets a picture «Экран» that was not in the call, frames flow (the diary of B
# names their size); A stops -- the picture leaves B, the call stays a voice call; then A calls B with video: both see a
# picture, A shows its screen in the camera's place and takes it back.
# usage: tools\callshare.ps1 -Root DIR [-Shots DIR]
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
# the diary lines of a window that name a picture's size and its frames, from the n-th on: a size above nothing with frames
# decoded is a picture that flowed
function Picture([string]$who, [string]$what, [int]$n, [int]$timeout = 20) {
    $end = (Get-Date).AddSeconds($timeout)
    $last = ""
    do {
        $lines = @(Get-Content "$Root\$who\trace.log" -Encoding UTF8 -ErrorAction SilentlyContinue | Where-Object { $_ -match "call $what " })
        for ($i = $n - 1; $i -lt $lines.Count; $i++) {
            $last = $lines[$i]
            if ($last -match "call $what (\d+)x(\d+) in=(\d+)" -and [int]$Matches[1] -gt 0 -and [int]$Matches[3] -gt 0) {
                "  ${who}: $what $($Matches[1])x$($Matches[2]), $($Matches[3]) frames"; return
            }
        }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $end)
    throw "${who}: no picture under '$what': $last"
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
"A shows its screen"
Click-Named "Трансляция"
Says "Вы делитесь экраном" 15
Use-Montana $B; Front-Montana
Says "Экран" 30
Picture "B" "share seen" 1
Snap "70-B-screen"
"A stops: the picture leaves B"
Use-Montana $A; Front-Montana
Click-Named "Трансляция"
Gone-Named "Вы делитесь экраном" 10
Use-Montana $B; Front-Montana
Gone-Named "Экран" 20
"  B: the screen left; the call goes on"
Talking 5
Use-Montana $A; Front-Montana
Click-Named "Отбой"
Use-Montana $B
Says "Звонок завершён" 30
Start-Sleep -Seconds 3
"A calls B with video"
Use-Montana $A; Front-Montana
Click-Named "Позвонить"; Click-Named "Видеозвонок"
Use-Montana $B; Front-Montana
Says "Принять" 60
Click-Named "Принять"
Talking 40
Picture "B" "picture seen" 1
Use-Montana $A; Front-Montana
Talking 20
Picture "A" "picture seen" 1
Snap "71-A-video"
"A shows its screen in the camera's place"
Click-Named "Трансляция"
Says "Вы делитесь экраном" 15
Use-Montana $B; Front-Montana
Says "Экран" 30
Picture "B" "share seen" 2
Use-Montana $A; Front-Montana
Click-Named "Трансляция"
Gone-Named "Вы делитесь экраном" 10
Use-Montana $B; Front-Montana
Gone-Named "Экран" 20
"  B: the camera's picture again"
Use-Montana $A; Front-Montana
Click-Named "Отбой"
Use-Montana $B
Says "Звонок завершён" 30
"done in $([int]((Get-Date) - $t0).TotalSeconds) s"
Use-Montana $A; Stop-Montana; Use-Montana $B; Stop-Montana
