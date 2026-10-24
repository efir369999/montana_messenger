# THE OTHER DEVICE'S WORD HEARD AT ONCE (Android's ear on the twin's pipe; iOS: the node's silent push wakes every device of the pipe
# but the one that spoke): AliceTest on Windows (tools\twin3.ps1's test folder) and on the emulator MontanaA, the app left open on the
# conversation with Bob. Windows writes three letters to Bob; each must stand on Android within a minute and a half without the app
# being opened again -- the mirror's half minute, then the box's hint on the lane, never the five-minute round.
# usage: tools\twinlane.ps1 -Root DIR [-Apk PATH] [-Shots DIR]
param([Parameter(Mandatory = $true)][string]$Root, [string]$Apk = "", [string]$Shots = "")
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ui.ps1"
. "$PSScriptRoot\android.ps1" -Device emulator-5554
if ($Shots) { New-Item -ItemType Directory -Force $Shots | Out-Null }
$stamp = Get-Date -Format "HHmmss"
$t0 = Get-Date
if (-not (Test-Path "$Root\P")) { throw "no Alice on Windows: run tools\twin3.ps1 with the same -Root first" }
function Droid-Field { Droid-Nodes | Where-Object { $_.Text -like "Сообщение*" -or $_.Desc -like "Сообщение*" } | Select-Object -First 1 }

try {
    foreach ($p in @(@("MontanaA", "emulator-5554"), @("MontanaC", "emulator-5560"))) {
        Use-Droid $p[1]
        if (((Droid-Adb get-state) -join "") -notmatch "^device") { Droid-Up $p[0] }
        if ($Apk) { $r = (Droid-Adb install -r $Apk) -join " "; if ($r -notmatch "Success") { throw "android: install on $($p[1]) failed: $r" } }
        Droid-Adb shell am force-stop $script:Package | Out-Null; Droid-Start
        $end = (Get-Date).AddSeconds(60)
        while (-not (Droid-Nodes | Where-Object { @("Чаты", "Chats") -contains $_.Text })) { if ((Get-Date) -gt $end) { throw "android: no chat list" }; Start-Sleep -Seconds 1 }
    }
    Use-Droid "emulator-5554"; Start-Sleep -Seconds 8   # Alice's ear stands on the list: the lanes of the conversations and of the twin's pipe
    $proc = Start-Montana -DataDir "$Root\P"; Front-Montana -X 0 -Y 40 -Width 1100 -Height 900
    Start-Sleep -Seconds 4
    try { Click-Named "Не сейчас" 3 } catch {}
    Click-Named "Чаты"; Start-Sleep -Milliseconds 600

    "Bob writes; both of Alice's devices hold it unread"
    $t = "lane read $stamp"
    Use-Droid "emulator-5560"
    Droid-Tap "AliceTest" 30
    $end = (Get-Date).AddSeconds(20); while (-not (Droid-Nodes | Where-Object { $_.Text -like "Message*" -or $_.Desc -like "Message*" -or $_.Text -like "Сообщение*" })) { if ((Get-Date) -gt $end) { throw "bob: no chat" }; Start-Sleep -Milliseconds 700 }
    $f = Droid-Nodes | Where-Object { $_.Text -like "Message*" -or $_.Desc -like "Message*" -or $_.Text -like "Сообщение*" } | Select-Object -First 1
    Droid-TapAt $f.X $f.Y; Droid-Type $t; Start-Sleep -Milliseconds 400
    $send = Droid-Nodes | Where-Object { @("Отправить", "Send") -contains $_.Desc -or @("Отправить", "Send") -contains $_.Text } | Select-Object -First 1
    Droid-TapAt $send.X $send.Y
    $end = (Get-Date).AddSeconds(120)
    while (-not (Page-Text).Contains($t)) { if ((Get-Date) -gt $end) { throw "Windows never shows Bob's letter in the list" }; Start-Sleep -Seconds 2 }
    "  Windows has it"
    Use-Droid "emulator-5554"
    $end = (Get-Date).AddSeconds(120)
    while (-not (Droid-Nodes | Where-Object { $_.Text -like "*$t*" })) { if ((Get-Date) -gt $end) { throw "Android never shows Bob's letter in the list" }; Start-Sleep -Seconds 3 }
    "  Android has it"
    Start-Sleep -Seconds 35   # any word already on its way rides out first
    Droid-Adb logcat -c | Out-Null

    "Alice reads on Windows: the open Android takes the reading by the mirror"
    $n = Get-Texts | Where-Object { $_ -like "*Irbis*" -or $_ -like "*BobTest*" } | Select-Object -First 1
    Click-Named $n 10
    $read = Get-Date
    $end = $read.AddSeconds(150)
    while (-not (@(Droid-Adb logcat -d -v time -s Montana:V) -match "twin_read")) {
        if ((Get-Date) -gt $end) { throw "the reading on Windows did not reach the open Android within 150 s" }
        Start-Sleep -Seconds 2
    }
    $s = [int]((Get-Date) - $read).TotalSeconds
    "  Android took the reading in $s s"
    @(Droid-Adb logcat -d -v time -s Montana:V | Where-Object { $_ -match "twin_|box" } | Select-Object -Last 8) | ForEach-Object { "  log: $_" }
    if ($s -gt 100) { throw "the reading came by the five-minute round ($s s), not by the lane" }
    "done in $([int]((Get-Date) - $t0).TotalSeconds) s"
} finally {
    try { Stop-Montana } catch {}
    foreach ($d in @("emulator-5554", "emulator-5560")) { try { Droid-Off $d } catch {} }
}
