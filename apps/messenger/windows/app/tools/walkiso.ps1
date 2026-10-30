# THE PIPE SECRET'S STEP OF 29.10.2026, THROUGH THE BOX, IN AN ISOLATED ROOM (the owner's word 25.10.2026 13:2x: check now all that
# iOS 2308 states, time moved by managed clocks, never the computer's date, never the network): tools\clocknode.py puts up the
# original's node with the live box's behaviour on a clock of its own; AliceTest's Windows (-Root\P) reaches it alone by
# MONTANA_TEST_DOOR and counts its day by MONTANA_CLOCK_SHIFT_DAYS; Bob's emulator (MontanaC) reaches it alone by its root-only
# test-door file and counts its day by its own clock set ahead. The node, Windows and the emulator always stand on one day: today,
# 28.10 (the anchor: the established secret), 29.10 (the first step), 03.11 (six steps on, the days between missed). On each day the
# letters go both ways; and a letter laid on 28.10 while the other side is away waits in the box and is taken after midnight, on
# 29.10, by the key of its own day -- what the live network could only show on the real date. Test identities and emulators only.
# usage: tools\walkiso.ps1 -Root DIR -Node FILE [-Apk PATH] [-Port N]
#   (-Root\P: AliceTest's Windows folder, made by tools\twin3.ps1; -Node: apps/messenger/ios/Code/Node/montana-home-node.py of main)
param([Parameter(Mandatory = $true)][string]$Root, [Parameter(Mandatory = $true)][string]$Node, [string]$Apk = "", [int]$Port = 18462,
      [int]$From = 1)   # -From 5: straight to that step (the days before skipped)
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ui.ps1"
. "$PSScriptRoot\android.ps1" -Device emulator-5560
$t0 = Get-Date
$C = "emulator-5560"
$room = "$Root\walkiso-node"
$door = "http://127.0.0.1:$Port"
$python = (Get-ChildItem "$env:LOCALAPPDATA\Programs\Python" -Recurse -Filter python.exe -ErrorAction SilentlyContinue | Select-Object -First 1).FullName
if (-not $python) { throw "no python.exe under %LOCALAPPDATA%\Programs\Python" }
if (-not (Test-Path "$Root\P")) { throw "no Alice on Windows: run tools\twin3.ps1 with the same -Root first" }
$today = [int][Math]::Floor(([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) / 86400000)
$anchor = 20754

function Field { Droid-Nodes | Where-Object { $_.Text -like "Сообщение*" -or $_.Desc -like "Сообщение*" -or $_.Text -like "Message*" -or $_.Desc -like "Message*" } | Select-Object -First 1 }
function App-Up {
    Droid-Adb shell am force-stop $script:Package | Out-Null; Droid-Start
    $end = (Get-Date).AddSeconds(120)
    while (-not (Droid-Nodes | Where-Object { @("Чаты", "Chats", "Все", "All", "Поиск", "Search") -contains $_.Text })) { if ((Get-Date) -gt $end) { throw "android: no chat list" }; Start-Sleep -Seconds 1 }
}
function Bob-Chat {
    if (-not (Field)) { Droid-Tap "AliceTest" 30; $end = (Get-Date).AddSeconds(20); while (-not (Field)) { if ((Get-Date) -gt $end) { throw "bob: no chat" }; Start-Sleep -Milliseconds 700 } }
}
function Bob-Write([string]$text) {
    Bob-Chat
    $f = Field; Droid-TapAt $f.X $f.Y; Droid-Type $text; Start-Sleep -Milliseconds 250
    $send = Droid-Nodes | Where-Object { @("Отправить", "Send") -contains $_.Desc -or @("Отправить", "Send") -contains $_.Text } | Select-Object -First 1
    Droid-TapAt $send.X $send.Y; Start-Sleep -Milliseconds 300
}
function Bob-Sees([string]$text, [int]$seconds) {
    $end = (Get-Date).AddSeconds($seconds)
    while ($true) {
        Bob-Chat
        if (Droid-Nodes | Where-Object { $_.Text -like "*$text*" }) { return }
        # the feed stands by each letter's birth: a letter of an earlier day than letters a check laid on later days (the clocks
        # moved ahead) stands above them, out of sight -- the feed is scrolled up to it and back down
        for ($i = 0; $i -lt 6; $i++) {
            Droid-Adb shell input swipe 540 700 540 1600 300 | Out-Null; Start-Sleep -Milliseconds 600
            if (Droid-Nodes | Where-Object { $_.Text -like "*$text*" }) {
                for ($j = 0; $j -le $i; $j++) { Droid-Adb shell input swipe 540 1600 540 700 300 | Out-Null }
                return
            }
        }
        for ($j = 0; $j -lt 6; $j++) { Droid-Adb shell input swipe 540 1600 540 700 300 | Out-Null }
        if ((Get-Date) -gt $end) {
            Droid-Shot "$Root\walkiso-bob.png"
            "  Bob's screen: " + ((Droid-Texts | Select-Object -First 40) -join " | ")
            throw "Bob never saw '$text' (his screen: $Root\walkiso-bob.png)"
        }
        Start-Sleep -Seconds 4
    }
}
# the room's day: the node's clock, then Bob's phone (its own clock and the test door), then Alice's Windows -- one day for all three
function Day([int]$shift, [switch]$NoBob, [switch]$NoAlice) {
    Set-Content -Path "$room\shift_days" -Value "$shift" -Encoding ascii
    Use-Droid $C
    Droid-Adb shell am force-stop $script:Package | Out-Null
    Droid-Adb shell settings put global auto_time 0 | Out-Null
    Droid-Adb shell ("date -u " + [DateTime]::UtcNow.AddDays($shift).ToString("MMddHHmmyyyy.ss")) | Out-Null
    if (-not $NoBob) { App-Up }
    try { Stop-Montana } catch {}
    if (-not $NoAlice) {
        $env:MONTANA_CLOCK_SHIFT_DAYS = "$shift"; $env:MONTANA_TEST_DOOR = $door
        $script:proc = Start-Montana -DataDir "$Root\P"; Front-Montana -X 0 -Y 40 -Width 1000 -Height 900
        Start-Sleep -Seconds 4
        try { Click-Named "Не сейчас" 3 } catch {}
        $n = Get-Texts | Where-Object { $_ -like "*Irbis*" -or $_ -like "*BobTest*" } | Where-Object { $_ -notmatch ',' } | Select-Object -First 1
        Click-Named $n 15
        Find-Named "Сообщение..." 20 | Out-Null
    }
    "  day $($today + $shift): node +$shift d, Bob's phone $(((Droid-Adb shell 'date -u +%d.%m.%Y') -join '').Trim()), Windows +$shift d"
}
# the window's text, a busy window's UI Automation timeout read as nothing yet (the next look reads it again)
function Safe-Page { try { Page-Text } catch { "" } }
function Exchange([string]$day) {
    $w = "iso $day w2b"; $b = "iso $day b2w"
    Type-Into "Сообщение..." $w; Click-Named "Отправить"
    Use-Droid $C; Bob-Sees $w 180
    Bob-Write $b
    $end = (Get-Date).AddSeconds(180)
    while (-not (Safe-Page).Contains($b)) { if ((Get-Date) -gt $end) { throw "Windows never saw '$b'" }; Start-Sleep -Seconds 3 }
    "  both ways on day $day"
}

$nodeProc = $null
try {
    "the isolated room: the original's node on a clock of its own, on the loopback"
    New-Item -ItemType Directory -Force $room | Out-Null
    Set-Content -Path "$room\shift_days" -Value "0" -Encoding ascii
    $nodeProc = Start-Process -FilePath $python -ArgumentList @("-I", "$PSScriptRoot\clocknode.py", $Node, $room, "$Port") `
        -RedirectStandardOutput "$room\node.log" -RedirectStandardError "$room\node.err" -NoNewWindow -PassThru
    Start-Sleep -Seconds 4
    if ($nodeProc.HasExited) { throw "the node did not stand: $(Get-Content "$room\node.err" -Raw)" }

    "Bob's phone: the build with the test door, the door laid by root"
    Use-Droid $C; if (((Droid-Adb get-state) -join "") -notmatch "^device") { Droid-Up "MontanaC" }
    if ($Apk) { $r = (Droid-Adb install -r $Apk) -join " "; if ($r -notmatch "Success") { throw "android: install failed: $r" } }
    Droid-Adb root | Out-Null; Start-Sleep -Seconds 3; Droid-Boot 60
    Droid-Adb shell "echo http://10.0.2.2:$Port > /data/data/$($script:Package)/no_backup/test_door" | Out-Null
    $seen = (Droid-Adb shell "cat /data/data/$($script:Package)/no_backup/test_door") -join ""
    if ($seen.Trim() -ne "http://10.0.2.2:$Port") { throw "the test door was not laid: $seen" }

    Droid-Adb logcat -c | Out-Null
    if ($From -le 1) { "1. today (day $today): both ways through the isolated node"; Day 0; Exchange "d$today" }
    if ($From -le 2) { "2. 28.10 (day $anchor, the established secret): both ways"; Day ($anchor - $today); Exchange "d$anchor" }
    if ($From -le 4) {
    "3. a letter laid on 28.10 while Bob's phone is off, taken on 29.10 (the first step) by its own day's key"
    $boxed = "iso box w2b 2810"
    Use-Droid $C; Droid-Adb shell am force-stop $script:Package | Out-Null
    Type-Into "Сообщение..." $boxed; Click-Named "Отправить"; Start-Sleep -Seconds 10
    "  and one laid by Bob while Windows is away"
    Stop-Montana
    $boxedB = "iso box b2w 2810"
    App-Up; Bob-Write $boxedB; Start-Sleep -Seconds 10
    Droid-Adb shell am force-stop $script:Package | Out-Null
    Day ($anchor + 1 - $today)
    Use-Droid $C; Bob-Sees $boxed 240
    "  Bob took on 29.10 the letter laid on 28.10"
    $end = (Get-Date).AddSeconds(240)
    while (-not (Safe-Page).Contains($boxedB)) { if ((Get-Date) -gt $end) { throw "Windows never took '$boxedB' after midnight" }; Start-Sleep -Seconds 3 }
    "  Windows took on 29.10 the letter laid on 28.10"
    "4. 29.10 (day $($anchor + 1), the first step): both ways"
    Exchange "d$($anchor + 1)"
    }
    "5. 03.11 (day $($anchor + 6), six steps on, the days between missed): both ways"
    Day ($anchor + 6 - $today); Exchange "d$($anchor + 6)"
    "done in $([int]((Get-Date) - $t0).TotalSeconds) s"
} catch {
    Use-Droid $C
    @(Droid-Adb logcat -d -v time -s Montana:V | Where-Object { $_ -match "rx|fetch|pickup|box|day|walk" }) | Select-Object -Last 25 | ForEach-Object { "  log: $_" }
    throw
} finally {
    try { Stop-Montana } catch {}
    Remove-Item Env:MONTANA_TEST_DOOR -ErrorAction SilentlyContinue; Remove-Item Env:MONTANA_CLOCK_SHIFT_DAYS -ErrorAction SilentlyContinue
    try {
        Use-Droid $C
        if (((Droid-Adb get-state) -join "") -match "^device") {
            Droid-Adb shell "rm -f /data/data/$($script:Package)/no_backup/test_door" | Out-Null
            Droid-Adb shell ("date -u " + [DateTime]::UtcNow.ToString("MMddHHmmyyyy.ss")) | Out-Null
            Droid-Adb shell settings put global auto_time 1 | Out-Null
            Droid-Off $C
        }
    } catch {}
    if ($nodeProc -and -not $nodeProc.HasExited) { try { $nodeProc.Kill() } catch {} }
}
