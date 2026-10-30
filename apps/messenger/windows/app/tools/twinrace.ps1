# BOTH OF ONE PERSON'S DEVICES ON LINE TAKE THE SAME LETTERS (D3, the owner's scenarios 6 and 8a, plan 07-android-twin-mirror.md
# 12): AliceTest's Windows sits in Bob's chat and her Android on its chat list, both on line, both fetching the same box; Bob
# (MontanaC) writes ten letters as fast as his phone sends them. Whichever device takes a letter -- or both of them before the
# node's /box-del, the mirror's words then crossing -- every one must stand exactly once on Windows and on Android, and Windows
# reading them must leave the Android nothing unread. Texts only (no photo). Test identities, test folders and the emulators only.
# usage: tools\twinrace.ps1 -Root DIR   (-Root\P: Alice's Windows folder, made by tools\twin3.ps1)
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
    $end = (Get-Date).AddSeconds(120)
    while (-not (Droid-Nodes | Where-Object { @("Чаты", "Chats", "Все", "All", "Поиск", "Search") -contains $_.Text })) {
        if ((Get-Date) -gt $end) { Droid-Shot "$env:TEMP\twinrace-$($script:Droid).png"; throw "android $($script:Droid): no chat list (its picture: %TEMP%\twinrace-$($script:Droid).png)" }
        Start-Sleep -Seconds 1
    }
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
# the unread count the chat list wears on a row (Conversation.kt: the white number at the row's end); 0 when it wears none
function Droid-Unread([string]$name) {
    $nodes = @(Droid-Nodes)
    $row = $nodes | Where-Object { $_.Text -like "*$name*" } | Select-Object -First 1
    if (-not $row) { return -1 }
    $badge = $nodes | Where-Object { $_.Text -match '^\d{1,3}$' -and [math]::Abs($_.Y - $row.Y) -lt 120 -and $_.X -gt 700 } | Select-Object -First 1
    if ($badge) { [int]$badge.Text } else { 0 }
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
    Use-Droid $A; Droid-Adb logcat -c | Out-Null
    $script:proc = Start-Montana -DataDir "$Root\P"; Front-Montana -X 0 -Y 40 -Width 1100 -Height 900
    Start-Sleep -Seconds 4
    try { Click-Named "Не сейчас" 3 } catch {}
    $n = Get-Texts | Where-Object { $_ -like "*Irbis*" -or $_ -like "*BobTest*" } | Select-Object -First 1
    Click-Named $n 15
    "Alice's Windows in Bob's chat, her Android on its chat list; both on line"
    Start-Sleep -Seconds 6

    "Bob writes ten letters as fast as his phone sends them"
    $bl = 1..10 | ForEach-Object { "race b$_ $stamp" }
    Use-Droid $C; Open-Chat "AliceTest"
    $sent = Get-Date
    foreach ($b in $bl) { Droid-Write $b }
    "  sent in $([int]((Get-Date) - $sent).TotalSeconds) s"

    "every letter once on Alice's Windows"
    $end = (Get-Date).AddSeconds(240)
    do { $page = Page-Text; $missing = @($bl | Where-Object { -not $page.Contains($_) }); if ($missing.Count) { Start-Sleep -Seconds 3 } } while ($missing.Count -and (Get-Date) -lt $end)
    if ($missing.Count) { throw "Windows lacks: $($missing -join ', ')" }
    $named = @(All-Named | ForEach-Object { try { $_.Current.Name } catch {} })
    $twice = @($bl | Where-Object { $t = $_; @($named | Where-Object { $_ -eq $t }).Count -gt 1 })
    if ($twice.Count) { throw "Windows shows twice: $($twice -join ', ')" }
    "  10 of 10 once on Windows, $([int]((Get-Date) - $sent).TotalSeconds) s after the first was sent"

    "Windows read them: the Android's list must wear nothing unread for Bob"
    Use-Droid $A
    $end = (Get-Date).AddSeconds(240); $most = 0
    do { $u = Droid-Unread "Irbis"; if ($u -gt $most) { $most = $u }; if ($u -ne 0) { Start-Sleep -Seconds 4 } } while ($u -ne 0 -and (Get-Date) -lt $end)
    if ($u -ne 0) { throw "Android still wears $u unread for Bob (the most seen $most)" }
    "  nothing unread on Android (the most it wore on the way: $most), $([int]((Get-Date) - $sent).TotalSeconds) s after the first was sent"

    "every letter once on Alice's Android"
    Open-Chat "Irbis"   # the counting steps back to the list first: from the list itself a step back would leave the app
    $end = (Get-Date).AddSeconds(240)
    do { $cnt = Droid-Counts "Irbis" $bl; $bad = @($bl | Where-Object { $cnt[$_] -ne 1 }); if ($bad.Count) { Start-Sleep -Seconds 6 } } while ($bad.Count -and (Get-Date) -lt $end)
    if ($bad.Count) { throw "Android: " + (($bad | ForEach-Object { "$_ x$($cnt[$_])" }) -join ', ') }
    "  10 of 10 once on Android"

    "who took what (the Android's log)"
    $log = @(Droid-Adb logcat -d -v time -s Montana:V)
    $quiet = @($log | Where-Object { $_ -match "twin_rx mid=.*another device took" }).Count
    $takes = @($log | Where-Object { $_ -match "twin_lt taken" }).Count
    "  Bob's words heard by the mirror (each laid quietly or found standing): $quiet; the mirror's takes: $takes"
    $log | Where-Object { $_ -match "twin_|rx_" } | Select-Object -Last 12 | ForEach-Object { "  log: $_" }
    "done in $([int]((Get-Date) - $t0).TotalSeconds) s"
} finally {
    try { Stop-Montana } catch {}
    foreach ($d in @($A, $C)) { try { Use-Droid $d; if (((Droid-Adb get-state) -join "") -match "^device") { Droid-Off $d } } catch {} }
}
