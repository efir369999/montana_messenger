# ONE OF THE PERSON'S DEVICES AWAY FOR AN HOUR (D3, the owner's scenario 5, 24.10.2026 18:1x): Alice's Android (MontanaA) is off;
# meanwhile Alice writes twenty letters to Bob on Windows, Bob writes twenty to Alice (MontanaC), and Windows reads them. An hour after
# the Android went off it comes back: all forty letters must stand on it, each once -- by the box (what Windows did not take), the
# mirror (what Windows took and wrote) and the twin's blocks. Test identities, test folders and the emulators only.
# usage: tools\twinhour.ps1 -Root DIR [-Minutes 60]   (-Root\P: Alice's Windows folder, made by tools\twin3.ps1)
param([Parameter(Mandatory = $true)][string]$Root, [int]$Minutes = 60)
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ui.ps1"
. "$PSScriptRoot\android.ps1" -Device emulator-5554
$stamp = Get-Date -Format "HHmmss"
$t0 = Get-Date
$A = "emulator-5554"; $C = "emulator-5560"
if (-not (Test-Path "$Root\P")) { throw "no Alice on Windows: run tools\twin3.ps1 with the same -Root first" }
function Field { Droid-Nodes | Where-Object { $_.Text -like "Сообщение*" -or $_.Desc -like "Сообщение*" -or $_.Text -like "Message*" -or $_.Desc -like "Message*" } | Select-Object -First 1 }
function App-Up {
    Droid-Adb shell am force-stop $script:Package | Out-Null; Droid-Start
    $end = (Get-Date).AddSeconds(60)
    while (-not (Droid-Nodes | Where-Object { @("Чаты", "Chats") -contains $_.Text })) { if ((Get-Date) -gt $end) { throw "android: no chat list" }; Start-Sleep -Seconds 1 }
}
function Open-Chat([string]$name) {
    if (Field) { return }
    Droid-Tap $name 30
    $end = (Get-Date).AddSeconds(20); while (-not (Field)) { if ((Get-Date) -gt $end) { throw "android: no chat $name" }; Start-Sleep -Milliseconds 700 }
}
function Droid-Write([string]$text) {
    $f = Field; Droid-TapAt $f.X $f.Y; Droid-Type $text; Start-Sleep -Milliseconds 250
    $send = Droid-Nodes | Where-Object { @("Отправить", "Send") -contains $_.Desc -or @("Отправить", "Send") -contains $_.Text } | Select-Object -First 1
    Droid-TapAt $send.X $send.Y; Start-Sleep -Milliseconds 300
}
# every letter's count among the feed's words on Android (the feed scrolled through from its foot; the list beneath read apart)
function Droid-Counts([string]$name, [string[]]$texts) {
    Droid-Back; Start-Sleep -Milliseconds 600
    $onList = @{}; foreach ($t in $texts) { $onList[$t] = @(Droid-Nodes | Where-Object { $_.Text -eq $t }).Count }
    Open-Chat $name
    $best = @{}; foreach ($t in $texts) { $best[$t] = 0 }
    for ($i = 0; $i -lt 14; $i++) {
        $screen = @(Droid-Nodes | ForEach-Object { $_.Text })
        foreach ($t in $texts) { $n = @($screen | Where-Object { $_ -eq $t }).Count - $onList[$t]; if ($n -gt $best[$t]) { $best[$t] = $n } }
        Droid-Adb shell input swipe 540 700 540 1500 300 | Out-Null; Start-Sleep -Milliseconds 600
    }
    $best
}

try {
    Use-Droid $A; if (((Droid-Adb get-state) -join "") -match "^device") { Droid-Off $A; Start-Sleep -Seconds 15 }
    $away = Get-Date
    "Alice's Android off at $($away.ToString('HH:mm:ss'))"
    Use-Droid $C; if (((Droid-Adb get-state) -join "") -notmatch "^device") { Droid-Up "MontanaC" }; App-Up
    $script:proc = Start-Montana -DataDir "$Root\P"; Front-Montana -X 0 -Y 40 -Width 1100 -Height 900
    Start-Sleep -Seconds 4
    try { Click-Named "Не сейчас" 3 } catch {}
    "Bob writes twenty to Alice"
    $bl = 1..20 | ForEach-Object { "hour bob $_ $stamp" }
    Use-Droid $C; Open-Chat "AliceTest"
    foreach ($t in $bl) { Droid-Write $t }
    "Alice writes twenty to Bob on Windows, and reads his"
    $n = Get-Texts | Where-Object { $_ -like "*Irbis*" -or $_ -like "*BobTest*" } | Select-Object -First 1
    Click-Named $n 15
    $wl = 1..20 | ForEach-Object { "hour win $_ $stamp" }
    foreach ($t in $wl) { Type-Into "Сообщение..." $t; Click-Named "Отправить"; Start-Sleep -Milliseconds 300 }
    $end = (Get-Date).AddSeconds(240)
    do { $page = Page-Text; $missing = @($bl | Where-Object { -not $page.Contains($_) }); if ($missing.Count) { Start-Sleep -Seconds 4 } } while ($missing.Count -and (Get-Date) -lt $end)
    if ($missing.Count) { throw "Windows lacks Bob's: $($missing -join ', ')" }
    "  Windows holds Bob's twenty and has read them"
    Use-Droid $C; Droid-Off $C

    $left = $away.AddMinutes($Minutes) - (Get-Date)
    if ($left.TotalSeconds -gt 0) { "the Android stays away $([int]$left.TotalMinutes) min more"; Start-Sleep -Seconds ([int]$left.TotalSeconds) }

    "Alice's Android comes back"
    Use-Droid $A; Droid-Up "MontanaA"; App-Up
    $all = $bl + $wl
    $end = (Get-Date).AddSeconds(420)
    do { Open-Chat "Irbis"; $cnt = Droid-Counts "Irbis" $all; $bad = @($all | Where-Object { $cnt[$_] -ne 1 }); if ($bad.Count) { Start-Sleep -Seconds 10 } } while ($bad.Count -and (Get-Date) -lt $end)
    if ($bad.Count) { throw "Android after the hour: " + (($bad | ForEach-Object { "$_ x$($cnt[$_])" }) -join ', ') }
    "  40 of 40 once on Android after $Minutes min away"
    "done in $([int]((Get-Date) - $t0).TotalSeconds) s"
} finally {
    try { Stop-Montana } catch {}
    foreach ($d in @($A, $C)) { try { Use-Droid $d; if (((Droid-Adb get-state) -join "") -match "^device") { Droid-Off $d } } catch {} }
}
