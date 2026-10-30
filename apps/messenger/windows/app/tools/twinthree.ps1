# THREE DEVICES OF ONE PERSON -- THE ORIGINAL'S LIMIT, MEASURED (D3, the owner's scenario 10; docs/identity-sync/07 5.1): AliceTest on
# Windows and on two emulators (MontanaA and its twin MontanaB, the same test words). Windows writes three letters to Bob; the mirror's
# words ride one row of the twin's pipe each round, and the first device to take a row confirms it -- the node erases it for every
# device (iOS MontanaPQ, node.py /box-del). The scene says on which of the two Androids each letter stands: by the original, one only,
# the other by the box's own road or not at all -- the case Dinet Device Sync is for. A measurement, not a pass.
# Since iOS 2306 each device marks a row taken by its own name (/box-del «taken»), so the row stays for the others: -Strict then
# fails the scene unless every letter stands on both Androids.
# usage: tools\twinthree.ps1 -Root DIR [-Apk PATH] [-Strict]   (-Root\P: Alice's Windows folder, made by tools\twin3.ps1)
param([Parameter(Mandatory = $true)][string]$Root, [string]$Apk = "", [switch]$Strict)
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ui.ps1"
. "$PSScriptRoot\android.ps1" -Device emulator-5554
$script:Mine["MontanaB"] = 5556
$stamp = Get-Date -Format "HHmmss"
$t0 = Get-Date
$A = "emulator-5554"; $B = "emulator-5556"
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
    foreach ($p in @(@("MontanaA", $A), @("MontanaB", $B))) {
        Use-Droid $p[1]; if (((Droid-Adb get-state) -join "") -notmatch "^device") { Droid-Up $p[0] }
        if ($Apk) { $r = (Droid-Adb install -r $Apk) -join " "; if ($r -notmatch "Success") { throw "android: install on $($p[1]) failed: $r" } }
        App-Up
    }
    Start-Sleep -Seconds 8
    $script:proc = Start-Montana -DataDir "$Root\P"; Front-Montana -X 0 -Y 40 -Width 1100 -Height 900
    Start-Sleep -Seconds 4
    try { Click-Named "Не сейчас" 3 } catch {}
    $n = Get-Texts | Where-Object { $_ -like "*Irbis*" -or $_ -like "*BobTest*" } | Select-Object -First 1
    Click-Named $n 15
    "Windows writes three letters to Bob"
    $wl = 1..3 | ForEach-Object { "three w$_ $stamp" }
    foreach ($t in $wl) { Type-Into "Сообщение..." $t; Click-Named "Отправить"; Start-Sleep -Seconds 1 }
    Start-Sleep -Seconds 150
    $where = @{}
    foreach ($d in @($A, $B)) {
        Use-Droid $d
        foreach ($name in @("Irbis", "BobTest")) { try { if (-not (Field)) { Droid-Tap $name 5 }; break } catch {} }
        Start-Sleep -Seconds 2
        $screen = @(Droid-Nodes | ForEach-Object { $_.Text })
        $where[$d] = @($wl | Where-Object { $screen -contains $_ })
        "  $d holds: $(if ($where[$d].Count) { $where[$d] -join ', ' } else { 'none' })"
    }
    foreach ($t in $wl) {
        $on = @(@($A, $B) | Where-Object { $where[$_] -contains $t })
        "  '$t' -> $(if ($on.Count -eq 2) { 'both' } elseif ($on.Count -eq 1) { 'one only (' + $on[0] + ')' } else { 'neither' })"
    }
    if ($Strict) {
        $short = @($wl | Where-Object { $t = $_; @(@($A, $B) | Where-Object { $where[$_] -contains $t }).Count -lt 2 })
        if ($short.Count) { throw "not on both Androids: $($short -join ', ')" }
        "  every letter on both Androids (each device took it on its own)"
    }
    "done in $([int]((Get-Date) - $t0).TotalSeconds) s"
} finally {
    try { Stop-Montana } catch {}
    foreach ($d in @($A, $B)) { try { Use-Droid $d; if (((Droid-Adb get-state) -join "") -match "^device") { & $script:Adb -s $d emu kill 2>&1 | Out-Null } } catch {} }
}
