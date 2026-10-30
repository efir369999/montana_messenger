# A ROW ASKED AND GIVEN BACK BETWEEN ONE PERSON'S DEVICES (D3, stage 3: iOS MontanaPQ askTwin/giveTwin, ChatStore.giveTwinRows/
# takeTwinRow; Windows twin.rs ask_twin/give_twin, Android Twin.ask/give/takeRow): Bob writes to Alice while her Android is off;
# her Windows takes the letter -- the node erases it for her other devices -- and is stopped before its word of the mirror is laid,
# the word wiped from its folder. The letter then lives only in Windows's archive blocks: when they reach the Android, its feed lacks
# the row, it asks Windows by the archive's key («TA:»), Windows gives the row back («TW:») and the Android lays it -- once.
# Test identities, test folders and the emulators only.
# usage: tools\twinask.ps1 -Root DIR   (-Root\P: Alice's Windows folder, made by tools\twin3.ps1)
param([Parameter(Mandatory = $true)][string]$Root, [string]$Apk = "")
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ui.ps1"
. "$PSScriptRoot\android.ps1" -Device emulator-5554
$stamp = Get-Date -Format "HHmmss"
$t0 = Get-Date
$A = "emulator-5554"; $C = "emulator-5560"
if (-not (Test-Path "$Root\P")) { throw "no Alice on Windows: run tools\twin3.ps1 with the same -Root first" }
function Bob-Field { Droid-Nodes | Where-Object { $_.Text -like "Message*" -or $_.Desc -like "Message*" -or $_.Text -like "Сообщение*" } | Select-Object -First 1 }
function App-Up {
    Droid-Adb shell am force-stop $script:Package | Out-Null; Droid-Start
    $end = (Get-Date).AddSeconds(60)
    while (-not (Droid-Nodes | Where-Object { @("Чаты", "Chats") -contains $_.Text })) { if ((Get-Date) -gt $end) { throw "android: no chat list" }; Start-Sleep -Seconds 1 }
}
function Win-Up {
    $script:proc = Start-Montana -DataDir "$Root\P"; Front-Montana -X 0 -Y 40 -Width 1100 -Height 900
    Start-Sleep -Seconds 4
    try { Click-Named "Не сейчас" 3 } catch {}
    $n = Get-Texts | Where-Object { $_ -like "*Irbis*" -or $_ -like "*BobTest*" } | Select-Object -First 1
    Click-Named $n 15
}

try {
    "Bob's phone up; Alice's Android stays off"
    Use-Droid $C; if (((Droid-Adb get-state) -join "") -notmatch "^device") { Droid-Up "MontanaC" }
    App-Up
    "Alice's Windows takes Bob's letter, then stops before its mirror word is laid"
    Win-Up
    $q = "ask $stamp"
    Use-Droid $C
    Droid-Tap "AliceTest" 30
    $end = (Get-Date).AddSeconds(20); while (-not (Bob-Field)) { if ((Get-Date) -gt $end) { throw "bob: no chat" }; Start-Sleep -Milliseconds 700 }
    $f = Bob-Field; Droid-TapAt $f.X $f.Y; Droid-Type $q; Start-Sleep -Milliseconds 300
    $send = Droid-Nodes | Where-Object { @("Отправить", "Send") -contains $_.Desc -or @("Отправить", "Send") -contains $_.Text } | Select-Object -First 1
    Droid-TapAt $send.X $send.Y
    $end = (Get-Date).AddSeconds(90)
    while (-not (Page-Text).Contains($q)) { if ((Get-Date) -gt $end) { throw "Windows never took Bob's letter" }; Start-Sleep -Milliseconds 500 }
    $took = Get-Date
    Start-Sleep -Seconds 8   # the row is written into the archive's block, as a machine that keeps running a few seconds writes it
    Stop-Montana; Start-Sleep -Seconds 1
    $left = [int]((Get-Date) - $took).TotalSeconds
    Remove-Item "$Root\P\vault\twinMirror.sealed" -ErrorAction SilentlyContinue
    "  Windows took it and stopped $left s later; its mirror queue wiped (the word for '$q' never rides)"
    if ($left -ge 25) { throw "Windows stopped too late: its mirror may have laid the word already" }
    Use-Droid $C; Droid-Off $C

    "Windows back (its blocks ride); Alice's Android on: it lacks the row, asks, and is given it"
    Win-Up
    Use-Droid $A; if (((Droid-Adb get-state) -join "") -notmatch "^device") { Droid-Up "MontanaA" }
    if ($Apk) { $r = (Droid-Adb install -r $Apk) -join " "; if ($r -notmatch "Success") { throw "android: install failed: $r" } }
    Droid-Adb logcat -c | Out-Null
    App-Up
    $end = (Get-Date).AddSeconds(420)
    while (-not (Droid-Nodes | Where-Object { $_.Text -like "*$q*" })) {
        if ((Get-Date) -gt $end) { break }
        Start-Sleep -Seconds 6
    }
    $log = @(Droid-Adb logcat -d -v time -s Montana:V | Where-Object { $_ -match "twin_|archive_|history_|saved_|rx_|holed" })
    $log | Select-Object -Last 30 | ForEach-Object { "  log: $_" }
    if (-not (Droid-Nodes | Where-Object { $_.Text -like "*$q*" })) { throw "Bob's letter never reached Alice's Android" }
    $asked = @($log | Where-Object { $_ -match "twin_ask" }).Count
    $rowed = @($log | Where-Object { $_ -match "twin_row" }).Count
    "  Bob's letter stands on Android; asks $asked, rows given back $rowed"
    if ($rowed -lt 1) { "  (it came by another road than the ask)" }
    "done in $([int]((Get-Date) - $t0).TotalSeconds) s"
} finally {
    try { Stop-Montana } catch {}
    foreach ($d in @($A, $C)) { try { if (((& $script:Adb -s $d get-state 2>$null) -join "") -match "^device") { Droid-Off $d } } catch {} }
}
