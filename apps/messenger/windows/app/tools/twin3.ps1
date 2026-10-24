# ONE PERSON ON WINDOWS AND ON ANDROID, THE MIRROR BETWEEN THEM (D3, the owner's word 24.10.2026 18:1x; docs/identity-sync/07, stage 1;
# iOS MontanaPQ 872-1155): the test identity AliceTest stands on the emulator MontanaA and, by the same test words, in a Windows test
# folder; BobTest on MontanaC is the correspondent. The node's box gives a letter to whichever device takes it first and erases it for
# the rest, and a letter one device sends the box never gives the other: so each scene below can pass only by the mirror's words.
#   1. Alice's letter written on Android stands on Windows as hers;     2. written on Windows, it stands on Android;
#   3. Bob's letter Android took (Windows away) stands on Windows;      4. Bob's letter Windows took (Android stopped) stands on Android.
# Every letter once. Real nodes, test identities and test words only; the emulators are switched off at the end.
# usage: tools\twin3.ps1 -Root DIR -Words FILE [-Apk PATH] [-Shots DIR]   (-Root\P: Alice's Windows folder, restored when absent)
param([Parameter(Mandatory = $true)][string]$Root, [Parameter(Mandatory = $true)][string]$Words, [string]$Apk = "", [string]$Shots = "")
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ui.ps1"
. "$PSScriptRoot\android.ps1" -Device emulator-5554
if ($Shots) { New-Item -ItemType Directory -Force $Shots | Out-Null }
function Snap($name) { if ($Shots) { Shot-Montana (Join-Path $Shots "$name.png") } }
function DSnap($name) { if ($Shots) { Droid-Shot (Join-Path $Shots "$name.png") } }
$stamp = Get-Date -Format "HHmmss"
$A = "emulator-5554"; $C = "emulator-5560"
$t0 = Get-Date

function Win-Up {
    $script:proc = Start-Montana -DataDir "$Root\P"; Front-Montana -X 0 -Y 40 -Width 900 -Height 900
    Start-Sleep -Seconds 3
}
# Bob's conversation by whatever name it wears here: his own (BobTest) or the one the book gave him (a callsign, «🐆 Irbis»)
function Win-Bob([int]$Seconds = 240) {
    $end = (Get-Date).AddSeconds($Seconds)
    while ($true) {
        $n = Get-Texts | Where-Object { $_ -like "*BobTest*" -or $_ -like "*Irbis*" } | Select-Object -First 1
        if ($n) { Click-Named $n 5; return }
        if ((Get-Date) -gt $end) { throw "Windows holds no chat with Bob" }
        try { Click-Named "Назад" 1 } catch {}
        Start-Sleep -Seconds 5
    }
}
function Win-Send([string]$text) { Type-Into "Сообщение..." $text; Click-Named "Отправить"; Start-Sleep -Milliseconds 500 }
# how many elements of the open page bear the letter's words, within the time given for it to come (Get-Texts folds repeats: never
# used for a count); one bubble's own count is measured on a letter Windows wrote itself ($script:unit)
function Win-Named([string]$text) { @(All-Named | Where-Object { try { $_.Current.Name -eq $text } catch { $false } }).Count }
function Win-Count([string]$text, [int]$Seconds) {
    $end = (Get-Date).AddSeconds($Seconds)
    do {
        if ((Page-Text).Contains($text)) { Start-Sleep -Seconds 3; return Win-Named $text }
        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $end)
    0
}
$script:unit = 1
# an emulator speaks the language it was set to (MontanaC: English): the field and the keys are looked for in both
function Droid-Field { Droid-Nodes | Where-Object { $_.Text -like "Сообщение*" -or $_.Desc -like "Сообщение*" -or $_.Text -like "Message*" -or $_.Desc -like "Message*" } | Select-Object -First 1 }
function Droid-Chat-With([string]$name) {
    if (Droid-Field) { return }
    Droid-Tap $name 30
    $end = (Get-Date).AddSeconds(20)
    while (-not (Droid-Field)) { if ((Get-Date) -gt $end) { throw "android: the chat with $name has no field" }; Start-Sleep -Milliseconds 700 }
}
function Droid-Send([string]$name, [string]$text) {
    Droid-Chat-With $name
    $f = Droid-Field; Droid-TapAt $f.X $f.Y; Droid-Type $text; Start-Sleep -Milliseconds 400
    $send = Droid-Nodes | Where-Object { @("Отправить", "Send") -contains $_.Desc -or @("Отправить", "Send") -contains $_.Text } | Select-Object -First 1
    if (-not $send) { throw "android: no send key" }
    Droid-TapAt $send.X $send.Y; Start-Sleep -Milliseconds 800
}
# the letter's bubbles on Android: the chat list keeps its row's preview in the tree under an open chat, so the nodes bearing the words
# are counted on the list alone and in the chat, and the bubbles are the difference
function Droid-Named([string]$text) { @(Droid-Nodes | Where-Object { $_.Text -eq $text }).Count }
function Droid-Count([string]$name, [string]$text, [int]$Seconds) {
    $end = (Get-Date).AddSeconds($Seconds)
    do {
        Droid-Chat-With $name
        if ((Droid-Named $text) -gt 0) {
            Droid-Back; Start-Sleep -Milliseconds 800
            $onList = Droid-Named $text
            Droid-Chat-With $name; Start-Sleep -Milliseconds 800
            return (Droid-Named $text) - $onList
        }
        Start-Sleep -Seconds 4
    } while ((Get-Date) -lt $end)
    0
}
function Droid-App-Up {
    Droid-Adb shell am force-stop $script:Package | Out-Null; Droid-Start
    $end = (Get-Date).AddSeconds(60)
    while (-not (Droid-Nodes | Where-Object { @("Чаты", "Chats") -contains $_.Text -or @("Чаты", "Chats") -contains $_.Desc })) {
        if ((Get-Date) -gt $end) { throw "android: the app shows no chat list" }; Start-Sleep -Seconds 1
    }
}

try {
    "the emulators: MontanaA (Alice), MontanaC (Bob)"
    Use-Droid $A; if (((Droid-Adb get-state) -join "") -notmatch "^device") { Droid-Up "MontanaA" }
    Use-Droid $C; if (((Droid-Adb get-state) -join "") -notmatch "^device") { Droid-Up "MontanaC" }
    if ($Apk) {
        foreach ($d in @($A, $C)) {
            Use-Droid $d
            $r = (Droid-Adb install -r $Apk) -join " "
            if ($r -notmatch "Success") { throw "android: install on $d failed: $r" }
        }
        "  the build laid on both"
    }
    foreach ($d in @($A, $C)) { Use-Droid $d; Droid-App-Up }

    "Alice on Windows (test folder P)"
    if (-not (Test-Path "$Root\P")) {
        Win-Up
        Click-Named "Продолжить с Montana"; Click-Named "Открыть личность"
        $w = (Get-Content $Words -Raw).Trim() -split '\s+'
        if ($w.Count -ne 24) { throw "the test words file holds $($w.Count) words" }
        $end = (Get-Date).AddSeconds(15)
        while ($true) { try { Type-First-Field ($w -join " "); break } catch { if ((Get-Date) -gt $end) { throw }; Start-Sleep -Milliseconds 300 } }
        $w = $null
        Click-Named "Восстановить"
        $end = (Get-Date).AddSeconds(60)
        do { $tx = Get-Texts; if ($tx -contains "Принимаю") { Click-Named "Принимаю"; break }; if ($tx -contains "Чаты") { break }; Start-Sleep -Milliseconds 500 } while ((Get-Date) -lt $end)
        "  restored; the conversation with Bob comes back from the copy"
    } else { Win-Up }
    Win-Bob 300
    Snap "twin3-0-windows"

    "0. one bubble on Windows: a letter it writes itself"
    $w0 = "tw0 w $stamp"
    Win-Send $w0
    $script:unit = Win-Count $w0 20
    if ($script:unit -lt 1) { throw "0: Windows does not show its own letter" }
    "  one bubble = $($script:unit) named element(s)"

    "1. Alice writes on Android: Windows shows it as hers"
    $a2w = "tw1 a2w $stamp"
    Use-Droid $A; Droid-Send "Irbis" $a2w
    $n = Win-Count $a2w 150
    if ($n -ne $script:unit) { throw "1: the Android letter stands as $n elements on Windows (one bubble: $($script:unit))" }
    "  on Windows once"

    "2. Alice writes on Windows: Android shows it as hers"
    $w2a = "tw2 w2a $stamp"
    Win-Send $w2a
    Use-Droid $A; Droid-Back; Droid-App-Up
    $n = Droid-Count "Irbis" $w2a 150
    if ($n -ne 1) { throw "2: the Windows letter stands $n times on Android" }
    "  on Android once"
    DSnap "twin3-2-android"

    "3. Bob writes while Windows is away; Android takes it; Windows shows it"
    Stop-Montana
    $q3 = "tw3 bob $stamp"
    Use-Droid $C; Droid-Send "AliceTest" $q3
    Use-Droid $A; $n = Droid-Count "Irbis" $q3 120
    if ($n -ne 1) { throw "3: Android did not take Bob's letter ($n)" }
    Start-Sleep -Seconds 40   # the mirror's half minute
    Win-Up; Win-Bob 60
    $n = Win-Count $q3 150
    if ($n -ne $script:unit) { throw "3: Bob's letter Android took stands as $n elements on Windows (one bubble: $($script:unit))" }
    "  on Windows once"
    Snap "twin3-3-windows"

    "4. Bob writes while Android is stopped; Windows takes it; Android shows it"
    Use-Droid $A; Droid-Adb shell am force-stop $script:Package | Out-Null
    $q4 = "tw4 bob $stamp"
    Use-Droid $C; Droid-Send "AliceTest" $q4
    $n = Win-Count $q4 120
    if ($n -ne $script:unit) { throw "4: Windows shows Bob's letter as $n elements (one bubble: $($script:unit))" }
    Start-Sleep -Seconds 40
    Use-Droid $A; Droid-App-Up
    $n = Droid-Count "Irbis" $q4 180
    if ($n -ne 1) { throw "4: Bob's letter Windows took stands $n times on Android" }
    "  on Android once"
    DSnap "twin3-4-android"
    $log = @(Droid-Adb logcat -d -v time -s Montana:V | Where-Object { $_ -match "twin_" } | Select-Object -Last 12)
    $log | ForEach-Object { "  log: $_" }
    "done in $([int]((Get-Date) - $t0).TotalSeconds) s"
} finally {
    try { Stop-Montana } catch {}
    foreach ($d in @($A, $C)) { try { Droid-Off $d } catch {} }
}
