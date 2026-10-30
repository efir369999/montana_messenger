# ONE PERSON'S GROUP ON WINDOWS AND ON ANDROID (D3, stage 2 of the iOS twin mirror: MTGroup.mirrors, carry -> enqueue, handleOwn;
# Windows groups.rs group_own, group_heard_by_twin): AliceTest on Windows (the test folder of tools\twin3.ps1) and on the emulator
# MontanaA, BobTest on MontanaC. Alice makes a group with Bob on Windows: it stands on Android as hers; what Alice writes into it on
# either device stands once on the other as hers; what Bob writes stands once on both of Alice's devices.
# Real nodes, test identities only; the emulators are switched off at the end.
# usage: tools\twingroup.ps1 -Root DIR [-Apk PATH] [-Shots DIR]   (-Root\P: Alice's Windows folder, made by tools\twin3.ps1)
param([Parameter(Mandatory = $true)][string]$Root, [string]$Apk = "", [string]$Shots = "")
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ui.ps1"
. "$PSScriptRoot\android.ps1" -Device emulator-5554
if ($Shots) { New-Item -ItemType Directory -Force $Shots | Out-Null }
function Snap($name) { if ($Shots) { Shot-Montana (Join-Path $Shots "$name.png") } }
function DSnap($name) { if ($Shots) { Droid-Shot (Join-Path $Shots "$name.png") } }
$stamp = Get-Date -Format "HHmmss"
$title = "TwinG $stamp"
$A = "emulator-5554"; $C = "emulator-5560"
$t0 = Get-Date
if (-not (Test-Path "$Root\P")) { throw "no Alice on Windows: run tools\twin3.ps1 with the same -Root first" }

function Win-Named([string]$text) { @(All-Named | Where-Object { try { $_.Current.Name -eq $text } catch { $false } }).Count }
function Win-Count([string]$text, [int]$Seconds) {
    $end = (Get-Date).AddSeconds($Seconds)
    do {
        if ((Page-Text).Contains($text)) { Start-Sleep -Seconds 3; return Win-Named $text }
        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $end)
    0
}
function Win-Send([string]$text) { Type-Into "Сообщение..." $text; Click-Named "Отправить"; Start-Sleep -Milliseconds 500 }
function Droid-Field { Droid-Nodes | Where-Object { $_.Text -like "Сообщение*" -or $_.Desc -like "Сообщение*" -or $_.Text -like "Message*" -or $_.Desc -like "Message*" } | Select-Object -First 1 }
function Droid-Chat-With([string]$name) {
    if (Droid-Field) {
        if (Droid-Nodes | Where-Object { $_.Text -like "*$name*" }) { return }
        Droid-Back; Start-Sleep -Milliseconds 600
    }
    Droid-Tap $name 30
    $end = (Get-Date).AddSeconds(20)
    while (-not (Droid-Field)) { if ((Get-Date) -gt $end) { throw "android: the chat $name has no field" }; Start-Sleep -Milliseconds 700 }
}
function Droid-Send([string]$name, [string]$text) {
    Droid-Chat-With $name
    $f = Droid-Field; Droid-TapAt $f.X $f.Y; Droid-Type $text; Start-Sleep -Milliseconds 400
    $send = Droid-Nodes | Where-Object { @("Отправить", "Send") -contains $_.Desc -or @("Отправить", "Send") -contains $_.Text } | Select-Object -First 1
    if (-not $send) { throw "android: no send key" }
    Droid-TapAt $send.X $send.Y; Start-Sleep -Milliseconds 800
}
function Droid-Named([string]$text) { @(Droid-Nodes | Where-Object { $_.Text -eq $text }).Count }
# the bubbles: the nodes bearing the words in the chat, less those the list beneath keeps as its row's preview
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
function Droid-Has([string]$text, [int]$Seconds) {
    $end = (Get-Date).AddSeconds($Seconds)
    do { if (Droid-Nodes | Where-Object { $_.Text -like "*$text*" }) { return $true }; Start-Sleep -Seconds 4 } while ((Get-Date) -lt $end)
    $false
}

try {
    "the emulators: MontanaA (Alice), MontanaC (Bob)"
    Use-Droid $A; if (((Droid-Adb get-state) -join "") -notmatch "^device") { Droid-Up "MontanaA" }
    Use-Droid $C; if (((Droid-Adb get-state) -join "") -notmatch "^device") { Droid-Up "MontanaC" }
    if ($Apk) {
        foreach ($d in @($A, $C)) { Use-Droid $d; $r = (Droid-Adb install -r $Apk) -join " "; if ($r -notmatch "Success") { throw "android: install on $d failed: $r" } }
        "  the build laid on both"
    }
    foreach ($d in @($A, $C)) { Use-Droid $d; Droid-App-Up }
    $script:proc = Start-Montana -DataDir "$Root\P"; Front-Montana -X 0 -Y 40 -Width 1100 -Height 900
    Start-Sleep -Seconds 4

    "1. Alice makes the group on Windows: it stands on Android as hers"
    try { Click-Named "Не сейчас" 3 } catch {}   # the keeping's question (iOS: «Keep your copy with your contacts?») is the person's to answer
    Click-Named "Чаты"; Start-Sleep -Milliseconds 600
    Click-Named "Написать"; Click-Named "Новая группа"
    $end = (Get-Date).AddSeconds(15)
    do { $pick = Get-Texts | Where-Object { $_ -like "Выбрать:*Irbis*" -or $_ -like "Выбрать:*BobTest*" } | Select-Object -First 1; if (-not $pick) { Start-Sleep -Milliseconds 500 } } while (-not $pick -and (Get-Date) -lt $end)
    if (-not $pick) { throw "1: Bob is not among the people to choose on Windows" }
    Click-Named $pick; Click-Named "Готово"
    Type-Into "Название группы" $title; Click-Named "Готово"
    Find-Named "Вы создали группу «$title»" 20 | Out-Null
    Use-Droid $A; Droid-App-Up
    if (-not (Droid-Has $title 180)) { throw "1: the group made on Windows does not stand on Android" }
    "  the group stands on Android"
    DSnap "tg-1-android"

    "2. Alice writes into it on Windows (one bubble measured): Android shows it once"
    $w = "g2 w $stamp"
    Win-Send $w
    $unit = Win-Count $w 20
    if ($unit -lt 1) { throw "2: Windows does not show its own group letter" }
    $n = Droid-Count $title $w 180
    if ($n -ne 1) { throw "2: Alice's Windows group letter stands $n times on Android" }
    "  on Android once"

    "3. Alice writes into it on Android: Windows shows it once"
    $ga = "g3 a $stamp"
    Droid-Send $title $ga
    $n = Win-Count $ga 180
    if ($n -ne $unit) { throw "3: Alice's Android group letter stands as $n elements on Windows (one bubble: $unit)" }
    "  on Windows once"

    "4. Bob writes into the group: both of Alice's devices show it once"
    Use-Droid $C; Droid-App-Up
    if (-not (Droid-Has $title 120)) { throw "4: the group does not stand on Bob's phone" }
    $gb = "g4 bob $stamp"
    Droid-Send $title $gb
    $n = Win-Count $gb 180
    if ($n -ne $unit) { throw "4: Bob's group letter stands as $n elements on Windows (one bubble: $unit)" }
    # an Android on the screen takes the twin's pipe when the app opens or at its five-minute round (its live lane holds the pairs'
    # pipes alone, docs/identity-sync/07 4.5): the app is opened, as the person opens it
    Start-Sleep -Seconds 40
    Use-Droid $A; Droid-App-Up
    $n = Droid-Count $title $gb 180
    if ($n -ne 1) { throw "4: Bob's group letter stands $n times on Alice's Android" }
    "  on both once"
    Snap "tg-4-windows"; DSnap "tg-4-android"
    "done in $([int]((Get-Date) - $t0).TotalSeconds) s"
} finally {
    # the log only from a device that stands (adb waits for an absent one for ever)
    try { Use-Droid $A; if (((Droid-Adb get-state) -join "") -match "^device") { @(Droid-Adb logcat -d -v time -s Montana:V | Where-Object { $_ -match "twin_|group" } | Select-Object -Last 25) | ForEach-Object { "  log: $_" } } } catch {}
    try { Stop-Montana } catch {}
    foreach ($d in @($A, $C)) { try { Droid-Off $d } catch {} }
}
