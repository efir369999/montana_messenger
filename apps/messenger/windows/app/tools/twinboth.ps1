# BOTH OF ONE PERSON'S DEVICES WRITE AT ONCE (D3, the owner's scenario 7, 24.10.2026 18:1x): AliceTest on Windows and on the emulator
# MontanaA each write five letters to Bob within the same seconds; Bob (MontanaC) answers once. Every one of the eleven letters must
# stand exactly once on Alice's Windows and on Alice's Android, and Alice's ten on Bob's phone -- by the box, the mirror and the
# receipts, whichever device took what. Test identities, test folders and the emulators only.
# usage: tools\twinboth.ps1 -Root DIR   (-Root\P: Alice's Windows folder, made by tools\twin3.ps1)
param([Parameter(Mandatory = $true)][string]$Root)
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
    for ($i = 0; $i -lt 5; $i++) {
        $screen = @(Droid-Nodes | ForEach-Object { $_.Text })
        foreach ($t in $texts) { $n = @($screen | Where-Object { $_ -eq $t }).Count - $onList[$t]; if ($n -gt $best[$t]) { $best[$t] = $n } }
        Droid-Adb shell input swipe 540 700 540 1500 300 | Out-Null; Start-Sleep -Milliseconds 600
    }
    $best
}

try {
    foreach ($p in @(@("MontanaA", $A), @("MontanaC", $C))) { Use-Droid $p[1]; if (((Droid-Adb get-state) -join "") -notmatch "^device") { Droid-Up $p[0] }; App-Up }
    $script:proc = Start-Montana -DataDir "$Root\P"; Front-Montana -X 0 -Y 40 -Width 1100 -Height 900
    Start-Sleep -Seconds 4
    try { Click-Named "Не сейчас" 3 } catch {}
    $n = Get-Texts | Where-Object { $_ -like "*Irbis*" -or $_ -like "*BobTest*" } | Select-Object -First 1
    Click-Named $n 15
    Use-Droid $A; Open-Chat "Irbis"

    "both of Alice's devices write five letters within the same seconds"
    $wl = 1..5 | ForEach-Object { "both w$_ $stamp" }; $al = 1..5 | ForEach-Object { "both a$_ $stamp" }
    for ($i = 0; $i -lt 5; $i++) {
        Type-Into "Сообщение..." $wl[$i]; Click-Named "Отправить"
        Use-Droid $A; Droid-Write $al[$i]
    }
    "Bob answers once"
    $b = "both bob $stamp"
    Use-Droid $C; Open-Chat "AliceTest"; Droid-Write $b
    $all = $wl + $al + $b

    "every letter once on Alice's Windows"
    $end = (Get-Date).AddSeconds(240)
    do { $page = Page-Text; $missing = @($all | Where-Object { -not $page.Contains($_) }); if ($missing.Count) { Start-Sleep -Seconds 4 } } while ($missing.Count -and (Get-Date) -lt $end)
    if ($missing.Count) { throw "Windows lacks: $($missing -join ', ')" }
    $named = @(All-Named | ForEach-Object { try { $_.Current.Name } catch {} })
    $twice = @($all | Where-Object { $t = $_; @($named | Where-Object { $_ -eq $t }).Count -gt 1 })
    if ($twice.Count) { throw "Windows shows twice: $($twice -join ', ')" }
    "  11 of 11 once on Windows"

    "every letter once on Alice's Android"
    Use-Droid $A
    $end = (Get-Date).AddSeconds(240)
    do { $cnt = Droid-Counts "Irbis" $all; $bad = @($all | Where-Object { $cnt[$_] -ne 1 }); if ($bad.Count) { Start-Sleep -Seconds 6 } } while ($bad.Count -and (Get-Date) -lt $end)
    if ($bad.Count) { throw "Android: " + (($bad | ForEach-Object { "$_ x$($cnt[$_])" }) -join ', ') }
    "  11 of 11 once on Android"

    "Alice's ten on Bob's phone, once each"
    Use-Droid $C
    $end = (Get-Date).AddSeconds(240)
    do { $cnt = Droid-Counts "AliceTest" ($wl + $al); $bad = @(($wl + $al) | Where-Object { $cnt[$_] -ne 1 }); if ($bad.Count) { Start-Sleep -Seconds 6 } } while ($bad.Count -and (Get-Date) -lt $end)
    if ($bad.Count) { throw "Bob: " + (($bad | ForEach-Object { "$_ x$($cnt[$_])" }) -join ', ') }
    "  10 of 10 once on Bob's phone"
    "done in $([int]((Get-Date) - $t0).TotalSeconds) s"
} finally {
    try { Stop-Montana } catch {}
    foreach ($d in @($A, $C)) { try { Use-Droid $d; if (((Droid-Adb get-state) -join "") -match "^device") { Droid-Off $d } } catch {} }
}
