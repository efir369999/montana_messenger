# THE PIPE SECRET'S WALK ACROSS 29.10.2026, WINDOWS <-> ANDROID, LIVE (iOS MTNodeWire.pipeSecret: one SHA-256 step a UTC day after
# day 20754 = 28.10.2026; the letter's key and the daily label walk, the author field and a coin blind stand on the root). A Windows
# test identity (WalkTest, -Root\W) and the emulator MontanaA's test identity (AliceTest, the patched APK) write both ways on the
# clients' own days: today (live, and a letter through the node's box while Windows is away); 28.10 (the anchor, no step); 29.10 (the
# first step); 03.11 (six steps on, days missed between) -- live; the old letters still stand. A box letter across the switch
# itself needs the real date (the node's clock names a box letter's minute): it is checked on 29.10 (docs/NEXT.md). Windows
# counts its day by MONTANA_CLOCK_SHIFT_DAYS (a check's run only), the emulator by its own clock set ahead and given back at the
# end. Real nodes, test identities only; nothing of the coins is written (a check's run writes no chain; the APK's writes are off).
# usage: tools\walk.ps1 -Root DIR [-Shots DIR]   (-Root\W holds WalkTest; MontanaA already holds the chat with it)
param([Parameter(Mandatory = $true)][string]$Root, [string]$Shots = "")
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ui.ps1"
. "$PSScriptRoot\android.ps1" -Device emulator-5554
if ($Shots) { New-Item -ItemType Directory -Force $Shots | Out-Null }
function Snap($name) { if ($Shots) { Shot-Montana (Join-Path $Shots "$name.png") } }
function DSnap($name) { if ($Shots) { Droid-Shot (Join-Path $Shots "$name.png") } }
$today = [int][Math]::Floor(([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) / 86400000)
$anchor = 20754

# the emulator's own day, set ahead in UTC (its clock's network time off for the check)
function Droid-Day([int]$shift) {
    Droid-Adb root | Out-Null; Start-Sleep -Seconds 2
    Droid-Adb shell settings put global auto_time 0 | Out-Null
    $t = [DateTime]::UtcNow.AddDays($shift)
    Droid-Adb shell ("date -u " + $t.ToString("MMddHHmmyyyy.ss")) | Out-Null
    Droid-Adb shell am force-stop $script:Package | Out-Null
    Droid-Start; Start-Sleep -Seconds 4
    "  android's day: " + ((Droid-Adb shell "date -u +%d.%m.%Y") -join "")
}
function Win-Day([int]$shift) {
    Stop-Montana
    $env:MONTANA_CLOCK_SHIFT_DAYS = "$shift"
    $script:proc = Start-Montana -DataDir "$Root\W"; Front-Montana -X 0 -Y 40 -Width 900 -Height 900
    Start-Sleep -Seconds 3
    foreach ($n in @("AliceTest", "Собеседник")) { try { Click-Named $n 5; return } catch {} }
    throw "Windows holds no chat with the Android side"
}
function Droid-Chat {
    if (-not (Droid-Nodes | Where-Object { $_.Text -like "Сообщение*" -or $_.Desc -like "Сообщение*" })) { Droid-Tap "WalkTest" 30 }
}
function Droid-Send([string]$text) {
    Droid-Chat
    Droid-Tap "Сообщение…"; Droid-Type $text; Start-Sleep -Milliseconds 400
    $send = Droid-Nodes | Where-Object { $_.Desc -eq "Отправить" -or $_.Text -eq "Отправить" } | Select-Object -First 1
    if (-not $send) { throw "android: no send key" }
    Droid-TapAt $send.X $send.Y
}
# an older letter stands above the screen: the feed is scrolled up until it shows (the tree reads the views in sight)
function Droid-Seek([string]$text) {
    Droid-Chat
    for ($i = 0; $i -lt 15; $i++) {
        if (Droid-Nodes | Where-Object { $_.Text -like "*$text*" }) { "  android sees: $text"; return }
        Droid-Adb shell input swipe 540 700 540 1600 300 | Out-Null; Start-Sleep -Milliseconds 700
    }
    throw "android: '$text' is not in the feed"
}
function Win-Send([string]$text) { Type-Into "Сообщение..." $text; Click-Named "Отправить"; Start-Sleep -Milliseconds 500 }
function Exchange([string]$day) {
    $a2w = "walk $day a2w"; $w2a = "walk $day w2a"
    Droid-Send $a2w
    Page-Says $a2w 180
    Win-Send $w2a
    Droid-Chat; Droid-Wait $w2a 180
}

$t0 = Get-Date
Droid-Up "MontanaA"
try {
    "today (day $today): both ways, live"
    Droid-Day 0; Win-Day 0
    Exchange "d$today"
    "today: a letter laid while Windows is away waits in the node's box and opens by its own minute (the box's road, on real time)"
    Stop-Montana
    Droid-Send "walk box a2w"
    Start-Sleep -Seconds 8
    Win-Day 0
    Page-Says "walk box a2w" 180

    # A BOX LETTER ACROSS THE SWITCH IS NOT CHECKED ON A SHIFTED CLOCK: the node names the minute it took a letter by its own real
    # clock and the reader opens by that minute -- a client counted days ahead never finds the sender's minute there. It is
    # checked on 29.10 itself (docs/NEXT.md); here the shifted days ride the live road, which opens by the reader's own minute.
    $s = $anchor - $today
    "28.10 (day $anchor, the anchor -- no step yet): both ways, live"
    Droid-Day $s; Win-Day $s
    Exchange "d$anchor"

    "29.10 (day $($anchor + 1), the first step)"
    Droid-Day ($s + 1); Win-Day ($s + 1)
    Exchange "d$($anchor + 1)"
    Snap "walk-29-win"; DSnap "walk-29-android"

    "03.11 (day $($anchor + 6), six steps on, the days between missed)"
    Droid-Day ($s + 6); Win-Day ($s + 6)
    Exchange "d$($anchor + 6)"
    "the old letters still stand on both sides"
    Page-Says "walk d$today a2w" 10
    Droid-Seek "walk d$today w2a"
    Snap "walk-0311-win"; DSnap "walk-0311-android"
    "done in $([int]((Get-Date) - $t0).TotalSeconds) s"
} finally {
    # the emulator's clock given back to the network's time, the windows closed, the emulator off
    try { Droid-Adb shell settings put global auto_time 1 | Out-Null; Droid-Adb shell ("date -u " + [DateTime]::UtcNow.ToString("MMddHHmmyyyy.ss")) | Out-Null } catch {}
    $env:MONTANA_CLOCK_SHIFT_DAYS = $null
    try { Stop-Montana } catch {}
    Droid-Off "emulator-5554"
}
