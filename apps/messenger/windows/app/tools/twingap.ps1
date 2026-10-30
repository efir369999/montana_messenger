# A ROW THE MIRROR NEVER CARRIED STILL REACHES THE OTHER DEVICE (D3, stage 3 of the iOS twin mirror: the archive's blocks «hist», the
# ask «TA:» and the answer «TW:»; MontanaPQ askTwin/giveTwin, ChatStore.giveTwinRows/takeTwinRow): AliceTest writes to Bob on the
# emulator MontanaA while her Windows is away, and the word of the mirror that would tell Windows is wiped from the phone before it is
# laid -- as a word is lost past the box's day. The letter can then reach Windows only by the blocks of the history and the rows asked
# of Android by their archive key. It must stand on Windows once. Test identities, test folders and the emulators only.
# usage: tools\twingap.ps1 -Root DIR [-Apk PATH]   (-Root\P: Alice's Windows folder, made by tools\twin3.ps1)
param([Parameter(Mandatory = $true)][string]$Root, [string]$Apk = "")
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ui.ps1"
. "$PSScriptRoot\android.ps1" -Device emulator-5554
$stamp = Get-Date -Format "HHmmss"
$t0 = Get-Date
$data = "/data/data/$($script:Package)"
if (-not (Test-Path "$Root\P")) { throw "no Alice on Windows: run tools\twin3.ps1 with the same -Root first" }
function Droid-Field { Droid-Nodes | Where-Object { $_.Text -like "Сообщение*" -or $_.Desc -like "Сообщение*" } | Select-Object -First 1 }
function Droid-App-Up {
    Droid-Adb shell am force-stop $script:Package | Out-Null; Droid-Start
    $end = (Get-Date).AddSeconds(60)
    while (-not (Droid-Nodes | Where-Object { $_.Text -eq "Чаты" })) { if ((Get-Date) -gt $end) { throw "android: no chat list" }; Start-Sleep -Seconds 1 }
}
function Droid-Say([string]$text) {
    if (-not (Droid-Field)) { Droid-Tap "Irbis" 30; $end = (Get-Date).AddSeconds(20); while (-not (Droid-Field)) { if ((Get-Date) -gt $end) { throw "android: no chat" }; Start-Sleep -Milliseconds 700 } }
    $f = Droid-Field; Droid-TapAt $f.X $f.Y; Droid-Type $text; Start-Sleep -Milliseconds 300
    $send = Droid-Nodes | Where-Object { $_.Desc -eq "Отправить" -or $_.Text -eq "Отправить" } | Select-Object -First 1
    Droid-TapAt $send.X $send.Y
}

try {
    if (((Droid-Adb get-state) -join "") -notmatch "^device") { Droid-Up "MontanaA" }
    Droid-Adb root | Out-Null; Start-Sleep -Seconds 3; Droid-Boot 60
    if ($Apk) { $r = (Droid-Adb install -r $Apk) -join " "; if ($r -notmatch "Success") { throw "android: install failed: $r" } }
    Droid-App-Up

    "Alice writes on Android while Windows is away; the mirror's word is wiped before it is laid"
    $gap = "gap1 $stamp"
    Droid-Say $gap
    Start-Sleep -Seconds 4
    Droid-Adb shell am force-stop $script:Package | Out-Null
    Droid-Adb shell "rm -f $data/no_backup/MontanaTwin/twin-mirror.sealed" | Out-Null
    "  the phone's mirror queue wiped (the word for '$gap' never rides)"

    "Alice writes once more: the blocks of the history ride, the new word with them"
    Droid-App-Up
    $next = "gap2 $stamp"
    Droid-Say $next
    Start-Sleep -Seconds 50   # the mirror's and the blocks' half minute
    Droid-Adb logcat -c | Out-Null

    "Windows comes back"
    $proc = Start-Montana -DataDir "$Root\P"; Front-Montana -X 0 -Y 40 -Width 1100 -Height 900
    Start-Sleep -Seconds 4
    try { Click-Named "Не сейчас" 3 } catch {}
    $n = Get-Texts | Where-Object { $_ -like "*Irbis*" -or $_ -like "*BobTest*" } | Select-Object -First 1
    Click-Named $n 15
    $end = (Get-Date).AddSeconds(240)
    while (-not (Page-Text).Contains($next)) { if ((Get-Date) -gt $end) { throw "the letter the mirror carried never stood on Windows" }; Start-Sleep -Seconds 3 }
    "  '$next' stands (by the mirror)"
    $end = (Get-Date).AddSeconds(300)
    while (-not (Page-Text).Contains($gap)) { if ((Get-Date) -gt $end) { throw "the letter the mirror never carried did not reach Windows within 5 minutes" }; Start-Sleep -Seconds 3 }
    $s = [int]((Get-Date) - $t0).TotalSeconds
    "  '$gap' stands on Windows (by the blocks or by the ask), $s s into the scene"
    $named = @(All-Named | Where-Object { try { $_.Current.Name -eq $gap } catch { $false } }).Count
    if ($named -gt 1) { throw "'$gap' stands $named times on Windows" }
    @(Droid-Adb logcat -d -v time -s Montana:V | Where-Object { $_ -match "twin_" } | Select-Object -Last 10) | ForEach-Object { "  log: $_" }
    "done in $([int]((Get-Date) - $t0).TotalSeconds) s"
} finally {
    try { Stop-Montana } catch {}
    try { Droid-Off "emulator-5554" } catch {}
}
