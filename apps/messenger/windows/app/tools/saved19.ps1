# ANDROID'S SAVED MESSAGES CARRIED INTO THE ARCHIVE (D19, the owner's word 24.10.2026 18:1x: a backup first, no loss, no doubles,
# the original kept): on the test emulator MontanaA (AliceTest) the installed build writes letters to Saved Messages the old way
# (saved_messages.json alone); the new build is laid over it (adb install -r keeps the app's data); at its first launch it copies
# the file with its manifest into no_backup/migrate, seals every letter into the folder «Saved Messages» and checks the count. The
# scene reads the log, the backup, the manifest and the room: every letter once, the original file still there, a letter written
# after the carrying stands once across a restart. Test identity only; the emulator is switched off at the end.
# usage: tools\saved19.ps1 -Apk PATH [-Shots DIR] [-Before N]   (-Before 0: the old build's letters are already written)
#        tools\saved19.ps1 -Apk PATH -After   (the new build is in and has carried: the room's letters counted, one more, a restart)
param([Parameter(Mandatory = $true)][string]$Apk, [string]$Shots = "", [int]$Before = 3, [switch]$After)
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\android.ps1" -Device emulator-5554
if ($Shots) { New-Item -ItemType Directory -Force $Shots | Out-Null }
function DSnap($name) { if ($Shots) { Droid-Shot (Join-Path $Shots "$name.png") } }
$stamp = Get-Date -Format "HHmmss"
$data = "/data/data/$($script:Package)"

function Saved-Open {
    if (Droid-Nodes | Where-Object { $_.Text -like "Сообщение*" -or $_.Desc -like "Сообщение*" }) { return }
    Droid-Tap "Избранное" 30
    Droid-Wait "Сообщение" 20 | Out-Null
}
function Saved-Send([string]$text) {
    Saved-Open
    Droid-Tap "Сообщение"; Droid-Type $text; Start-Sleep -Milliseconds 400
    $send = Droid-Nodes | Where-Object { $_.Desc -eq "Отправить" -or $_.Text -eq "Отправить" } | Select-Object -First 1
    if (-not $send) { throw "android: no send key" }
    Droid-TapAt $send.X $send.Y; Start-Sleep -Milliseconds 800
}
# how many times each letter stands in the room (the feed scrolled from its foot up, every view in sight read once a screen):
# one's own bubbles stand at the right; the chat list under the room keeps its row's preview in the tree, at the left
function Saved-Count([string[]]$texts) {
    Saved-Open
    $seen = @{}
    foreach ($t in $texts) { $seen[$t] = 0 }
    for ($i = 0; $i -lt 6; $i++) {
        $screen = @(Droid-Nodes | Where-Object { $_.X -ge 700 } | ForEach-Object { $_.Text } | Where-Object { $_ })
        foreach ($t in $texts) { $n = @($screen | Where-Object { $_ -eq $t }).Count; if ($n -gt $seen[$t]) { $seen[$t] = $n } }
        Droid-Adb shell input swipe 540 700 540 1500 300 | Out-Null; Start-Sleep -Milliseconds 600
    }
    $seen
}
function Room-File { (Droid-Adb shell "cat $data/files/saved_messages.json 2>/dev/null") -join "" }

try {
    "the emulator MontanaA"
    if (((Droid-Adb get-state) -join "") -notmatch "^device") { Droid-Up "MontanaA" }   # already up: taken as it stands
    Droid-Adb root | Out-Null; Start-Sleep -Seconds 3; Droid-Boot 60
    $old = (Droid-Adb shell dumpsys package $script:Package | Select-String "versionName|lastUpdateTime" | ForEach-Object { $_.Line.Trim() }) -join "; "
    "  installed: $old"
    Droid-Start; Droid-Wait "Чаты" 60

    $letters = @()
    if ($After) {
        $letters = @(((Room-File) | ConvertFrom-Json) | ForEach-Object { $_.text } | Where-Object { $_ -like "d19 before *" })
        $count0 = ([regex]::Matches((Room-File), '"id"')).Count
        "the carried room: $($letters.Count) letters of the old build, $count0 in the file"
    }
    if (-not $After -and $Before -gt 0) {
        "the old build writes $Before letters to Saved Messages"
        for ($i = 1; $i -le $Before; $i++) { $t = "d19 before $i $stamp"; Saved-Send $t; $letters += $t }
        DSnap "1-old-room"
    }
    if (-not $After) {
    $file0 = Room-File
    $count0 = ([regex]::Matches($file0, '"id"')).Count
    "  the room's file holds $count0 letters"
    Droid-Back; Droid-Back

    "the new build laid over it"
    Droid-Adb shell am force-stop $script:Package | Out-Null
    Droid-Adb logcat -c | Out-Null
    $r = (Droid-Adb install -r $Apk) -join " "
    if ($r -notmatch "Success") { throw "android: install failed: $r" }
    Droid-Start; Droid-Wait "Чаты" 60; Start-Sleep -Seconds 8
    $log = @(Droid-Adb logcat -d -v time -s Montana:V | Where-Object { $_ -match "saved_" })
    $log | ForEach-Object { "  log: $_" }
    if (-not ($log -match "saved_migrate backup=")) { throw "no backup was made" }
    if (-not ($log -match "saved_migrate check ok")) { throw "the carrying's count did not hold" }

    "the backup and its manifest beside the original"
    $dir = @(Droid-Adb shell "ls $data/no_backup/migrate")
    $dir | ForEach-Object { "  migrate/$_" }
    $manifest = (Droid-Adb shell "cat $data/no_backup/migrate/$(@($dir | Where-Object { $_ -like '*.manifest.json' })[-1])") -join ""
    $m = $manifest | ConvertFrom-Json
    "  manifest: count $($m.count), sha256 $($m.sha256.Substring(0, 12))…"
    $file1 = Room-File
    if ($file1 -ne $file0) { throw "the original file changed in the carrying" }
    if ($m.count -ne $count0) { throw "the manifest counts $($m.count), the file held $count0" }
    "  the original file stands unchanged"
    }

    "every letter once in the room"
    $later = "d19 after $stamp"
    $seen = Saved-Count $letters
    foreach ($t in $letters) { if ($seen[$t] -ne 1) { throw "'$t' stands $($seen[$t]) times" } }
    "  $($letters.Count) of $($letters.Count) once"
    Saved-Send $later
    DSnap "2-new-room"

    "a restart lays nothing twice"
    Droid-Adb shell am force-stop $script:Package | Out-Null
    Droid-Start; Droid-Wait "Чаты" 60; Start-Sleep -Seconds 6
    $seen = Saved-Count ($letters + $later)
    foreach ($t in ($letters + $later)) { if ($seen[$t] -ne 1) { throw "'$t' stands $($seen[$t]) times after the restart" } }
    $count2 = ([regex]::Matches((Room-File), '"id"')).Count
    if ($count2 -ne $count0 + 1) { throw "the room's file holds $count2 letters, $($count0 + 1) awaited" }
    "  $($letters.Count + 1) letters once each; the file holds $count2"
    DSnap "3-after-restart"
    "done"
} finally {
    try { Droid-Off "emulator-5554" } catch {}
}
