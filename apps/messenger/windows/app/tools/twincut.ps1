# THE ROAD CUT WHILE THE MIRROR'S WORDS ARE TAKEN (D3, the owner's scenario 8c, plan 07-android-twin-mirror.md 12): AliceTest's
# Windows writes to Bob; its word of the mirror rides to her Android (MontanaA), whose pickup reads the twin's row from the box and
# goes for the words' road -- and in that instant the phone is put into airplane mode, by a watcher on the phone itself reading the
# log («twin_lt fetching»). The road does not come whole, so the row must not be confirmed («twin_take ... fails=1 -- left in the
# box»); with the network back the next pickup takes it («twin_lt taken») and the letter stands on the Android once.
# Test identities, test folders and the emulator only.
# usage: tools\twincut.ps1 -Root DIR [-Apk PATH]   (-Root\P: Alice's Windows folder, made by tools\twin3.ps1)
param([Parameter(Mandatory = $true)][string]$Root, [string]$Apk = "")
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ui.ps1"
. "$PSScriptRoot\android.ps1" -Device emulator-5554
$stamp = Get-Date -Format "HHmmss"
$t0 = Get-Date
$A = "emulator-5554"
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
function Twin-Log { @(Droid-Adb logcat -d -v time -s Montana:V | Where-Object { $_ -match "twin_lt|twin_take" }) }

$watch = $null
$cutOut = "$env:TEMP\twincut-$stamp.out"
try {
    if (((Droid-Adb get-state) -join "") -notmatch "^device") { Droid-Up "MontanaA" }
    Droid-Adb shell cmd connectivity airplane-mode disable | Out-Null
    if ($Apk) { $r = (Droid-Adb install -r $Apk) -join " "; if ($r -notmatch "Success") { throw "android: install failed: $r" } }
    App-Up
    Start-Sleep -Seconds 6
    "the watcher on the phone: airplane mode the instant the mirror's words are fetched"
    $sh = Join-Path $env:TEMP "twincut-$stamp.sh"
    [IO.File]::WriteAllText($sh, (@(
        'logcat -T 1 -s Montana:D | while read -r l; do',
        '  case "$l" in *"twin_lt fetching"*) cmd connectivity airplane-mode enable; echo "cut $l"; exit 0;; esac',
        'done') -join "`n") + "`n")
    Droid-Adb push $sh /data/local/tmp/twincut.sh | Out-Null
    Droid-Adb logcat -c | Out-Null
    $watch = Start-Process -FilePath $script:Adb -ArgumentList @("-s", $A, "shell", "sh", "/data/local/tmp/twincut.sh") -RedirectStandardOutput $cutOut -RedirectStandardError "$cutOut.err" -NoNewWindow -PassThru

    "Alice's Windows writes to Bob: its word of the mirror rides"
    $script:proc = Start-Montana -DataDir "$Root\P"; Front-Montana -X 0 -Y 40 -Width 1100 -Height 900
    Start-Sleep -Seconds 4
    try { Click-Named "Не сейчас" 3 } catch {}
    $n = Get-Texts | Where-Object { $_ -like "*Irbis*" -or $_ -like "*BobTest*" } | Select-Object -First 1
    Click-Named $n 15
    $q = "cut1 $stamp"
    Type-Into "Сообщение..." $q; Click-Named "Отправить"
    $sent = Get-Date

    $end = (Get-Date).AddSeconds(180)
    while (-not ((Test-Path $cutOut) -and (Get-Content $cutOut -Raw) -match "cut")) { if ((Get-Date) -gt $end) { throw "the Android never went for the mirror's words within 3 minutes" }; Start-Sleep -Milliseconds 500 }
    "  cut $([int]((Get-Date) - $sent).TotalSeconds) s after Windows sent: $((Get-Content $cutOut -Raw).Trim())"
    Start-Sleep -Seconds 12
    $cutLog = Twin-Log
    $cutLog | ForEach-Object { "  log: $_" }
    $failed = @($cutLog | Where-Object { $_ -match "twin_take .*fails=1 -- left in the box" }).Count
    $tooLate = @($cutLog | Where-Object { $_ -match "twin_lt taken" }).Count
    if ($tooLate -and -not $failed) { throw "the cut came too late: the words were taken before the road went down" }
    if (-not $failed) { throw "no 'fails=1 -- left in the box' after the cut" }
    "  the road did not come whole: the row left in the box (fails=1)"

    "the network back: the next pickup takes the words"
    Droid-Adb shell cmd connectivity airplane-mode disable | Out-Null
    $back = Get-Date
    $end = (Get-Date).AddSeconds(300)
    while (-not (Twin-Log | Where-Object { $_ -match "twin_lt taken" })) { if ((Get-Date) -gt $end) { throw "the words were never taken after the network came back" }; Start-Sleep -Seconds 3 }
    "  taken $([int]((Get-Date) - $back).TotalSeconds) s after the network came back"
    Twin-Log | Select-Object -Last 8 | ForEach-Object { "  log: $_" }

    "the letter once on Alice's Android"
    Open-Chat "Irbis"   # the counting steps back to the list first: from the list itself a step back would leave the app
    $cnt = Droid-Counts "Irbis" @($q)
    if ($cnt[$q] -ne 1) { throw "Android shows '$q' x$($cnt[$q])" }
    "  '$q' once on Android"
    "done in $([int]((Get-Date) - $t0).TotalSeconds) s"
} finally {
    try { Droid-Adb shell cmd connectivity airplane-mode disable | Out-Null } catch {}
    if ($watch -and -not $watch.HasExited) { try { $watch.Kill() } catch {} }
    try { Droid-Adb shell "pkill -f twincut.sh; rm -f /data/local/tmp/twincut.sh" | Out-Null } catch {}
    Remove-Item "$env:TEMP\twincut-$stamp.*" -ErrorAction SilentlyContinue
    try { Stop-Montana } catch {}
    try { if (((Droid-Adb get-state) -join "") -match "^device") { Droid-Off $A } } catch {}
}
