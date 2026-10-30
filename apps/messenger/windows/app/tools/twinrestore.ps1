# A CLEAN INSTALL OPENED BY THE SAME WORDS TAKES THE HISTORY AND THE DAY'S MIRROR (D3, the owner's scenario 9b, plan
# 07-android-twin-mirror.md 12): AliceTest's Android MontanaA is off, so nobody takes the word of the mirror her Windows lays for a
# letter to Bob; the second emulator MontanaB is wiped clean (pm clear) and opened by Alice's test words, as a new phone is. The
# conversation with Bob must come back, the letter Windows wrote must stand by the mirror the box still holds, and no letter may
# stand twice -- a row the history gave back under the archive's own name («arc:») takes its wire name when the same letter comes
# again. Test identities, test words, test folders and the emulators only; the words are read into memory and typed, never written.
# usage: tools\twinrestore.ps1 -Root DIR -Words FILE [-Apk PATH]   (-Root\P: Alice's Windows folder, made by tools\twin3.ps1)
param([Parameter(Mandatory = $true)][string]$Root, [Parameter(Mandatory = $true)][string]$Words, [string]$Apk = "")
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ui.ps1"
. "$PSScriptRoot\android.ps1" -Device emulator-5556
$stamp = Get-Date -Format "HHmmss"
$t0 = Get-Date
$A = "emulator-5554"; $B = "emulator-5556"
if (-not (Test-Path "$Root\P")) { throw "no Alice on Windows: run tools\twin3.ps1 with the same -Root first" }
function Field { Droid-Nodes | Where-Object { $_.Text -like "Сообщение*" -or $_.Desc -like "Сообщение*" -or $_.Text -like "Message*" -or $_.Desc -like "Message*" } | Select-Object -First 1 }
function Named([string[]]$names) { Droid-Nodes | Where-Object { $names -contains $_.Text -or $names -contains $_.Desc } | Select-Object -First 1 }
function Tap-Named([string[]]$names, [int]$seconds = 30) {
    $end = (Get-Date).AddSeconds($seconds)
    while (-not ($n = Named $names)) { if ((Get-Date) -gt $end) { throw "android: nothing named $($names -join ' / ')" }; Start-Sleep -Milliseconds 700 }
    Droid-TapAt $n.X $n.Y
}
# the letters of the tests (each bears a six-digit stamp) seen more than once on one screen of the feed, scrolled from its foot
# (the chat list keeps its rows' previews in the tree under an open chat: what the list showed is taken off)
function Feed-Twice([hashtable]$onList) {
    $twice = @{}
    for ($i = 0; $i -lt 8; $i++) {
        $screen = @(Droid-Nodes | Where-Object { $_.Text -match '\b\d{6}\b' -and $_.Class -like "*TextView*" } | ForEach-Object { $_.Text })
        $screen | Group-Object | ForEach-Object { $k = $_.Count - [int]$onList[$_.Name]; if ($k -gt 1) { $twice[$_.Name] = $k } }
        Droid-Adb shell input swipe 540 700 540 1500 300 | Out-Null; Start-Sleep -Milliseconds 700
    }
    $twice
}

try {
    "Alice's Android MontanaA off: nobody takes the mirror's word"
    Use-Droid $A; if (((Droid-Adb get-state) -join "") -match "^device") { Droid-Off $A }

    "Alice's Windows writes to Bob; its word of the mirror is laid and left in the box"
    $script:proc = Start-Montana -DataDir "$Root\P"; Front-Montana -X 0 -Y 40 -Width 1100 -Height 900
    Start-Sleep -Seconds 4
    try { Click-Named "Не сейчас" 3 } catch {}
    $n = Get-Texts | Where-Object { $_ -like "*Irbis*" -or $_ -like "*BobTest*" } | Select-Object -First 1
    Click-Named $n 15
    $q = "rst w $stamp"
    Type-Into "Сообщение..." $q; Click-Named "Отправить"
    Start-Sleep -Seconds 50   # the mirror's half minute, and its road
    Stop-Montana; Start-Sleep -Seconds 1
    "  Windows wrote '$q' and stopped"

    "MontanaB wiped clean and opened by Alice's test words"
    Use-Droid $B; if (((Droid-Adb get-state) -join "") -notmatch "^device") { Droid-Up "MontanaB" }
    if ($Apk) { $r = (Droid-Adb install -r $Apk) -join " "; if ($r -notmatch "Success") { throw "android: install failed: $r" } }
    $r = (Droid-Adb shell pm clear $script:Package) -join " "
    if ($r -notmatch "Success") { throw "android: pm clear failed: $r" }
    Droid-Adb logcat -c | Out-Null
    Droid-Start
    Tap-Named @("Продолжить с Montana", "Continue with Montana") 60
    Tap-Named @("Открыть личность", "Open identity")
    $end = (Get-Date).AddSeconds(20)
    while (-not ($f = Droid-Nodes | Where-Object { $_.Class -like "*EditText*" } | Select-Object -First 1)) { if ((Get-Date) -gt $end) { throw "android: no field for the words" }; Start-Sleep -Milliseconds 700 }
    Droid-TapAt $f.X $f.Y
    $w = (Get-Content $Words -Raw).Trim() -split '\s+'
    if ($w.Count -ne 24) { throw "the test words file holds $($w.Count) words" }
    Droid-Type ($w -join " "); $w = $null
    Droid-Adb shell input keyevent 111 | Out-Null; Start-Sleep -Milliseconds 400   # the keyboard down
    Tap-Named @("Восстановить", "Restore")
    $end = (Get-Date).AddSeconds(300); $noCopy = $false
    while ($true) {
        $tx = @(Droid-Texts)
        # the platform asks for notifications again on a wiped app (its window stands over the list): allowed, as a person allows it
        if ($tx | Where-Object { @("Allow", "ALLOW", "Разрешить", "РАЗРЕШИТЬ") -contains $_ }) { Tap-Named @("Allow", "ALLOW", "Разрешить", "РАЗРЕШИТЬ"); continue }
        # the keeping question (Keeping.ask) over the list: not now, as every scene answers it
        if ($tx | Where-Object { @("Not now", "NOT NOW", "Не сейчас", "НЕ СЕЙЧАС") -contains $_ }) { Tap-Named @("Not now", "NOT NOW", "Не сейчас", "НЕ СЕЙЧАС"); continue }
        if ($tx | Where-Object { @("Чаты", "Chats", "Все", "All", "All Chats", "Все чаты", "Поиск", "Search") -contains $_ }) { break }
        if ($tx | Where-Object { @("Принимаю", "I agree") -contains $_ }) { Tap-Named @("Принимаю", "I agree"); continue }
        if ($tx | Where-Object { @("Продолжить без копии", "Continue without the copy") -contains $_ }) { $noCopy = $true; Tap-Named @("Продолжить без копии", "Continue without the copy"); continue }
        if ((Get-Date) -gt $end) { Droid-Shot "$env:TEMP\twinrestore-onboarding.png"; throw "android: no chat list 5 minutes after the words (picture: %TEMP%\twinrestore-onboarding.png)" }
        Start-Sleep -Seconds 2
    }
    "  opened$(if ($noCopy) { ' -- no copy came back from the keepers (went on without it)' } else { '' }), $([int]((Get-Date) - $t0).TotalSeconds) s into the scene"

    "the conversation with Bob comes back"
    $end = (Get-Date).AddSeconds(300)
    while (-not (Droid-Nodes | Where-Object { $_.Text -like "*Irbis*" -or $_.Text -like "*BobTest*" })) { if ((Get-Date) -gt $end) { throw "the conversation with Bob never came back" }; Start-Sleep -Seconds 4 }
    $bob = (Droid-Nodes | Where-Object { $_.Text -like "*Irbis*" -or $_.Text -like "*BobTest*" } | Select-Object -First 1).Text
    "  '$bob' stands on the list"

    "the letter Windows wrote stands by the day's mirror"
    $onList = @{}; Droid-Nodes | Where-Object { $_.Text -match '\b\d{6}\b' } | ForEach-Object { $onList[$_.Text] = 1 + [int]$onList[$_.Text] }
    Droid-Tap $bob 30
    $end = (Get-Date).AddSeconds(20); while (-not (Field)) { if ((Get-Date) -gt $end) { throw "android: no chat $bob" }; Start-Sleep -Milliseconds 700 }
    $end = (Get-Date).AddSeconds(300)
    while (-not (Droid-Nodes | Where-Object { $_.Text -eq $q })) { if ((Get-Date) -gt $end) { break }; Start-Sleep -Seconds 4 }
    $log = @(Droid-Adb logcat -d -v time -s Montana:V | Where-Object { $_ -match "twin_|archive_|rx_own|holed" })
    $log | Select-Object -Last 20 | ForEach-Object { "  log: $_" }
    if (-not (Droid-Nodes | Where-Object { $_.Text -eq $q })) { throw "'$q' never stood on the restored phone" }
    "  '$q' stands"

    "no letter twice"
    $twice = Feed-Twice $onList
    if ($twice.Count) { throw "twice on the restored phone: " + (($twice.Keys | ForEach-Object { "$_ x$($twice[$_])" }) -join ', ') }
    $renamed = @($log | Where-Object { $_ -match "takes its wire name" }).Count
    "  no letter twice on eight screens of the feed; rows of the history renamed to their wire names: $renamed"
    "done in $([int]((Get-Date) - $t0).TotalSeconds) s"
} finally {
    $w = $null
    try { Stop-Montana } catch {}
    foreach ($d in @($A, $B)) { try { Use-Droid $d; if (((Droid-Adb get-state) -join "") -match "^device") { Droid-Off $d } } catch {} }
}
