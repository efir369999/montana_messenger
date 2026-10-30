# THE HISTORY THE SAME AFTER A RESTART (D3, the owner's scenario 9a, plan 07-android-twin-mirror.md 12): AliceTest's Windows and
# her Android (MontanaA), both settled, are read -- the chat list with its unread counts, then the conversation with Bob with its
# rows and their statuses --, both apps are stopped and started again, and everything is read once more: it must be the same, word
# for word and count for count. Only what lives by the second (presence, typing, the connection's word) is set aside.
# Test identities, test folders and the emulator only.
# usage: tools\twinrestart.ps1 -Root DIR   (-Root\P: Alice's Windows folder, made by tools\twin3.ps1)
param([Parameter(Mandatory = $true)][string]$Root)
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ui.ps1"
. "$PSScriptRoot\android.ps1" -Device emulator-5554
$t0 = Get-Date
$A = "emulator-5554"
if (-not (Test-Path "$Root\P")) { throw "no Alice on Windows: run tools\twin3.ps1 with the same -Root first" }
$live = 'в чате|в сети|печатает|онлайн|был[аи]? |недавно|Подключ|Отключ|Соедин|online|typing|last seen|connect'
function Field { Droid-Nodes | Where-Object { $_.Text -like "Сообщение*" -or $_.Desc -like "Сообщение*" -or $_.Text -like "Message*" -or $_.Desc -like "Message*" } | Select-Object -First 1 }
function App-Up {
    Droid-Adb shell am force-stop $script:Package | Out-Null; Droid-Start
    $end = (Get-Date).AddSeconds(120)
    while (-not (Droid-Nodes | Where-Object { @("Чаты", "Chats", "Все", "All", "Поиск", "Search") -contains $_.Text })) { if ((Get-Date) -gt $end) { throw "android: no chat list" }; Start-Sleep -Seconds 1 }
    Start-Sleep -Seconds 3
}
function Win-Up {
    $script:proc = Start-Montana -DataDir "$Root\P"; Front-Montana -X 0 -Y 40 -Width 1100 -Height 900
    Start-Sleep -Seconds 4
    try { Click-Named "Не сейчас" 3 } catch {}
    Find-Named "Чаты" 30 | Out-Null; Start-Sleep -Seconds 3
}
# a screen's words as counts (word -> how many times), what lives by the second set aside
function Counts([string[]]$words) { $h = @{}; foreach ($w in $words) { if ($w -and $w -notmatch $live) { $h[$w] = 1 + [int]$h[$w] } }; $h }
function Win-Counts { Counts @(Get-Texts) }
function Droid-Counts { Counts @(Droid-Texts) }
function Word-Diff([string]$what, [hashtable]$before, [hashtable]$after) {
    $keys = @($before.Keys) + @($after.Keys) | Sort-Object -Unique
    $d = @($keys | Where-Object { [int]$before[$_] -ne [int]$after[$_] } | ForEach-Object { "'$_' $([int]$before[$_])->$([int]$after[$_])" })
    [pscustomobject]@{ N = $d.Count; Line = $(if ($d.Count) { "  ${what}: " + ($d -join '; ') } else { "  ${what}: the same ($($before.Count) words)" }) }
}
function Open-Bob-Win { $n = Get-Texts | Where-Object { $_ -like "*Irbis*" -or $_ -like "*BobTest*" } | Select-Object -First 1; Click-Named $n 15; Find-Named "Сообщение..." 20 | Out-Null; Start-Sleep -Seconds 3 }
function Open-Bob-Droid {
    Droid-Tap "Irbis" 30
    $end = (Get-Date).AddSeconds(20); while (-not (Field)) { if ((Get-Date) -gt $end) { throw "android: no chat Irbis" }; Start-Sleep -Milliseconds 700 }
    Start-Sleep -Seconds 3
}

try {
    "both of Alice's devices up and settled"
    Use-Droid $A; if (((Droid-Adb get-state) -join "") -notmatch "^device") { Droid-Up "MontanaA" }
    App-Up
    Win-Up
    Start-Sleep -Seconds 40   # whatever was due lands before the reading
    $wl = Win-Counts; $al = Droid-Counts
    Open-Bob-Win; Open-Bob-Droid
    $wf = Win-Counts; $af = Droid-Counts
    "  read: Windows list $($wl.Count) words, chat $($wf.Count); Android list $($al.Count), chat $($af.Count)"

    "both apps stopped and started again"
    Stop-Montana; Start-Sleep -Seconds 2
    Droid-Adb shell am force-stop $script:Package | Out-Null; Start-Sleep -Seconds 2
    App-Up
    Win-Up
    Start-Sleep -Seconds 10
    $bad = 0
    $r = Word-Diff "Windows chat list" $wl (Win-Counts); $r.Line; $bad += $r.N
    $r = Word-Diff "Android chat list" $al (Droid-Counts); $r.Line; $bad += $r.N
    Open-Bob-Win; Open-Bob-Droid
    $r = Word-Diff "Windows conversation with Bob" $wf (Win-Counts); $r.Line; $bad += $r.N
    $r = Word-Diff "Android conversation with Bob" $af (Droid-Counts); $r.Line; $bad += $r.N
    if ($bad) { throw "$bad words differ after the restart" }
    "done in $([int]((Get-Date) - $t0).TotalSeconds) s"
} finally {
    try { Stop-Montana } catch {}
    try { Use-Droid $A; if (((Droid-Adb get-state) -join "") -match "^device") { Droid-Off $A } } catch {}
}
