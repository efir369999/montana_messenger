# TWO WINDOWS COMPUTERS OF ONE PERSON (D3, IDENTITY-SYNC 12: «Windows ↔ Windows: own letters, the reading, deletion for all»):
# AliceTest stands in two Windows folders by the same test words -- P (made by tools\twin3.ps1) and P2, opened here from the words
# when absent -- and Bob writes from the emulator MontanaC. P sits in Bob's chat, P2 on its chat list. P's letter must stand on
# P2 once; Bob's letter on both once; P reading it must leave P2 nothing unread; P2's letter must stand on P once; and P deleting
# its letter for all must take it off P2 and off Bob's phone. Test identities, test words, test folders and the emulator only;
# the words are read into memory and typed, never written.
# usage: tools\twinwin.ps1 -Root DIR -Words FILE   (-Root\P: Alice's Windows folder, made by tools\twin3.ps1)
param([Parameter(Mandatory = $true)][string]$Root, [Parameter(Mandatory = $true)][string]$Words)
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ui.ps1"
. "$PSScriptRoot\android.ps1" -Device emulator-5560
$stamp = Get-Date -Format "HHmmss"
$t0 = Get-Date
$C = "emulator-5560"
if (-not (Test-Path "$Root\P")) { throw "no Alice on Windows: run tools\twin3.ps1 with the same -Root first" }
function Field { Droid-Nodes | Where-Object { $_.Text -like "Сообщение*" -or $_.Desc -like "Сообщение*" -or $_.Text -like "Message*" -or $_.Desc -like "Message*" } | Select-Object -First 1 }
function App-Up {
    Droid-Adb shell am force-stop $script:Package | Out-Null; Droid-Start
    $end = (Get-Date).AddSeconds(120)
    while (-not (Droid-Nodes | Where-Object { @("Чаты", "Chats", "Все", "All", "Поиск", "Search") -contains $_.Text })) { if ((Get-Date) -gt $end) { throw "android: no chat list" }; Start-Sleep -Seconds 1 }
}
function Bob-Write([string]$text) {
    if (-not (Field)) { Droid-Tap "AliceTest" 30; $end = (Get-Date).AddSeconds(20); while (-not (Field)) { if ((Get-Date) -gt $end) { throw "bob: no chat" }; Start-Sleep -Milliseconds 700 } }
    $f = Field; Droid-TapAt $f.X $f.Y; Droid-Type $text; Start-Sleep -Milliseconds 250
    $send = Droid-Nodes | Where-Object { @("Отправить", "Send") -contains $_.Desc -or @("Отправить", "Send") -contains $_.Text } | Select-Object -First 1
    Droid-TapAt $send.X $send.Y; Start-Sleep -Milliseconds 300
}
function Bob-Row { Get-Texts | Where-Object { $_ -like "*Irbis*" -or $_ -like "*BobTest*" } | Where-Object { $_ -notmatch ',' } | Select-Object -First 1 }
# how many elements of the open window bear exactly these words
function Count-Named([string]$text) { @(All-Named | Where-Object { try { $_.Current.Name -eq $text } catch { $false } }).Count }
function Wait-Page([string]$text, [int]$seconds) {
    $end = (Get-Date).AddSeconds($seconds)
    while (-not (Page-Text).Contains($text)) { if ((Get-Date) -gt $end) { return $false }; Start-Sleep -Seconds 2 }
    $true
}
# the unread count Bob's row wears on the list (the blue capsule inside the row): 0 when it wears none. The row is a button whose
# words lie in the raw view only (the control view folds a button's children), so the row is walked there
function Row-Words([string]$name) {
    $row = Find-Named $name 10
    $walk = [System.Windows.Automation.TreeWalker]::RawViewWalker
    $c = $walk.GetFirstChild($row)
    while ($c) {
        try { if ($c.Current.ControlType -eq [System.Windows.Automation.ControlType]::Text) { $c.Current.Name } } catch {}
        $c = $walk.GetNextSibling($c)
    }
}
function Row-Unread([string]$name) { $n = @(Row-Words $name | Where-Object { $_ -match '^\d{1,3}$' }) | Select-Object -First 1; if ($n) { [int]$n } else { 0 } }

$P = $null; $P2 = $null
try {
    "Bob's phone up"
    Use-Droid $C; if (((Droid-Adb get-state) -join "") -notmatch "^device") { Droid-Up "MontanaC" }
    App-Up

    "Alice's second Windows (P2): the same words on a folder of its own"
    $fresh = -not (Test-Path "$Root\P2")
    $P2 = Start-Montana -DataDir "$Root\P2"; Front-Montana -X 800 -Y 40 -Width 900 -Height 900
    if ($fresh) {
        Click-Named "Продолжить с Montana"; Click-Named "Открыть личность"
        $w = (Get-Content $Words -Raw).Trim() -split '\s+'
        if ($w.Count -ne 24) { throw "the test words file holds $($w.Count) words" }
        $end = (Get-Date).AddSeconds(15)
        while ($true) { try { Type-First-Field ($w -join " "); break } catch { if ((Get-Date) -gt $end) { throw }; Start-Sleep -Milliseconds 300 } }
        $w = $null
        Click-Named "Восстановить"
        $end = (Get-Date).AddSeconds(60)
        do { $tx = Get-Texts; if ($tx -contains "Принимаю") { Click-Named "Принимаю"; break }; if ($tx -contains "Чаты") { break }; Start-Sleep -Milliseconds 500 } while ((Get-Date) -lt $end)
        "  opened by the words"
    }
    Start-Sleep -Seconds 4
    try { Click-Named "Не сейчас" 3 } catch {}
    $end = (Get-Date).AddSeconds(300)
    while (-not ($row2 = Bob-Row)) { if ((Get-Date) -gt $end) { throw "P2: the conversation with Bob never stood" }; Start-Sleep -Seconds 3 }
    "  P2 holds '$row2'; it stays on its list"

    "Alice's first Windows (P), on its list too"
    $P = Start-Montana -DataDir "$Root\P"; Front-Montana -X 0 -Y 40 -Width 900 -Height 900
    Start-Sleep -Seconds 4
    try { Click-Named "Не сейчас" 3 } catch {}
    $row1 = Bob-Row

    "1. Bob writes while both of Alice's computers stand on their lists: P2 wears it unread"
    $b1 = "ww bob $stamp"
    Use-Droid $C; Bob-Write $b1
    Use-Montana $P2; Front-Montana
    $end = (Get-Date).AddSeconds(240)
    while (-not ((@(Row-Words $row2) -contains $b1) -and ($u = Row-Unread $row2))) { if ((Get-Date) -gt $end) { throw "P2 never wore Bob's letter unread: its row says $((Row-Words $row2) -join ' | ')" }; Start-Sleep -Seconds 3 }
    "  P2 wears $u unread for Bob"

    "2. P opens Bob's chat and reads; P2 then wears nothing unread"
    Use-Montana $P; Front-Montana
    Click-Named $row1 15
    Find-Named "Сообщение..." 20 | Out-Null
    if (-not (Wait-Page $b1 180)) { throw "P never showed Bob's letter" }
    Start-Sleep -Seconds 3   # the open chat is read once it has stood before the eyes 0.8 s, the window in front (iOS markRead)
    Use-Montana $P2; Front-Montana
    $end = (Get-Date).AddSeconds(240)
    do { $u = Row-Unread $row2; if ($u) { Start-Sleep -Seconds 3 } } while ($u -and (Get-Date) -lt $end)
    if ($u) { throw "P2 still wears $u unread for Bob 4 minutes after P read it" }
    "  nothing unread on P2"

    "3. P writes; the letter stands on P2"
    $w1 = "ww1 $stamp"
    Use-Montana $P; Front-Montana
    Type-Into "Сообщение..." $w1; Click-Named "Отправить"

    "4. P2 in Bob's chat: P's letter and Bob's once each"
    Use-Montana $P2; Front-Montana
    Click-Named $row2 15
    try { Find-Named "Сообщение..." 20 | Out-Null } catch { "  P2 shows: " + ((Get-Texts | Select-Object -First 40) -join ' | '); throw }
    foreach ($t in @($w1, $b1)) {
        if (-not (Wait-Page $t 240)) { throw "P2 lacks '$t'" }
        $n = Count-Named $t; if ($n -gt 1) { throw "P2 shows '$t' $n times" }
    }
    "  both once on P2"

    "5. P2 writes; the letter stands on P once"
    $w2 = "ww2 $stamp"
    Type-Into "Сообщение..." $w2; Click-Named "Отправить"
    Use-Montana $P; Front-Montana
    if (-not (Wait-Page $w2 240)) { throw "P lacks P2's letter" }
    $n = Count-Named $w2; if ($n -gt 1) { throw "P shows '$w2' $n times" }
    "  once on P"

    "6. P deletes its letter for all: gone from P2 and from Bob's phone"
    RightClick-Named $w1; Click-Named "Удалить"; Click-Named "Удалить у всех"
    Start-Sleep -Seconds 2
    if ((Page-Text).Contains($w1)) { throw "P still shows '$w1' after deleting it" }
    Use-Montana $P2; Front-Montana
    $end = (Get-Date).AddSeconds(240)
    while ((Page-Text).Contains($w1)) { if ((Get-Date) -gt $end) { throw "P2 still shows '$w1' 4 minutes after it was deleted for all" }; Start-Sleep -Seconds 3 }
    "  gone from P2 $([int]((Get-Date) - $t0).TotalSeconds) s into the scene"
    Use-Droid $C
    $end = (Get-Date).AddSeconds(240)
    while (Droid-Nodes | Where-Object { $_.Text -eq $w1 }) { if ((Get-Date) -gt $end) { throw "Bob still shows '$w1' 4 minutes after it was deleted for all" }; Start-Sleep -Seconds 4 }
    "  gone from Bob's phone"
    "done in $([int]((Get-Date) - $t0).TotalSeconds) s"
} finally {
    foreach ($p in @($P, $P2)) { if ($p) { try { Use-Montana $p; Stop-Montana } catch {} } }
    try { Use-Droid $C; if (((Droid-Adb get-state) -join "") -match "^device") { Droid-Off $C } } catch {}
}
