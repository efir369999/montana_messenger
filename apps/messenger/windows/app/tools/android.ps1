# THE ANDROID SIDE OF A CHECK (Montana Android on an emulator, over adb): find a view by its text, tap it, wait for it, type,
# shoot -- the same moves as the Android repository's tools\ui.ps1, which this does not change. Shots go to -Shots or the
# temp folder, never into the Android repository. Only the test emulators MontanaA (5554), MontanaB (5556), MontanaC (5560).
#   . tools\android.ps1 -Device emulator-5560; Droid-Texts; Droid-Tap "Write"; Droid-Wait "Delivered"
param([string]$Device = "emulator-5560")
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$script:Adb = Join-Path $env:LOCALAPPDATA "Android\Sdk\platform-tools\adb.exe"
$script:Droid = $Device
$script:Package = "quest.montana.app.dev"

function Use-Droid([string]$d) { $script:Droid = $d }
# adb's own complaints («device not found» while an emulator boots) are words to read, never a stop of the check
function Droid-Adb { $ErrorActionPreference = "Continue"; & $script:Adb -s $script:Droid @args 2>&1 | ForEach-Object { "$_" } }

function Droid-Nodes {
    for ($try = 0; $try -lt 3; $try++) {
        Droid-Adb shell uiautomator dump /sdcard/ui.xml 2>$null | Out-Null
        $raw = (Droid-Adb shell cat /sdcard/ui.xml) -join "`n"
        try { $x = [xml]$raw; break } catch { Start-Sleep -Milliseconds 500 }   # an animation leaves no tree: once more
    }
    if (-not $x) { return @() }
    $x.SelectNodes("//node") | ForEach-Object {
        if ($_.bounds -match '\[(\d+),(\d+)\]\[(\d+),(\d+)\]') {
            [pscustomobject]@{ Text = $_.text; Desc = $_.'content-desc'; Class = $_.class
                X = [int](([int]$Matches[1] + [int]$Matches[3]) / 2); Y = [int](([int]$Matches[2] + [int]$Matches[4]) / 2) }
        }
    }
}
function Droid-Texts { Droid-Nodes | Where-Object { $_.Text -or $_.Desc } | ForEach-Object { if ($_.Text) { $_.Text } else { $_.Desc } } }
function Droid-Find([string]$Text, [int]$Seconds = 30, [switch]$Exact) {
    $end = (Get-Date).AddSeconds($Seconds)
    do {
        $n = @(Droid-Nodes | Where-Object { if ($Exact) { $_.Text -eq $Text -or $_.Desc -eq $Text } else { $_.Text -like "*$Text*" -or $_.Desc -like "*$Text*" } })
        if ($n.Count) { return $n[0] }
        Start-Sleep -Milliseconds 700
    } while ((Get-Date) -lt $end)
    throw "android: nothing named '$Text'"
}
function Droid-Wait([string]$Text, [int]$Seconds = 60) { Droid-Find $Text $Seconds | Out-Null; "  android sees: $Text" }
function Droid-Tap([string]$Text, [int]$Seconds = 15, [switch]$Exact) {
    $n = Droid-Find $Text $Seconds -Exact:$Exact
    Droid-Adb shell input tap $n.X $n.Y
    Start-Sleep -Milliseconds 400
}
function Droid-TapAt([int]$X, [int]$Y) { Droid-Adb shell input tap $X $Y; Start-Sleep -Milliseconds 400 }
# a long press (a letter's menu): the finger held still for most of a second
function Droid-Hold([string]$Text, [int]$Seconds = 15) {
    $n = Droid-Find $Text $Seconds
    Droid-Adb shell input swipe $n.X $n.Y $n.X $n.Y 900
    Start-Sleep -Milliseconds 700
}
# words into the focused field: latin and digits by «input text»; anything else (Cyrillic, emoji) is not typed here
function Droid-Type([string]$Text) {
    if ($Text -notmatch '^[A-Za-z0-9 .,!?:/_=-]*$') { throw "android: «input text» takes latin words only" }
    Droid-Adb shell input text ($Text -replace ' ', '%s')
    Start-Sleep -Milliseconds 300
}
function Droid-Back { Droid-Adb shell input keyevent 4; Start-Sleep -Milliseconds 400 }
function Droid-Open([string]$Url) { Droid-Adb shell am start -a android.intent.action.VIEW -d "'$Url'" $script:Package | Out-Null; Start-Sleep -Seconds 2 }
function Droid-Start { Droid-Adb shell am start -n "$($script:Package)/quest.montana.app.MainActivity" | Out-Null; Start-Sleep -Seconds 2 }
function Droid-Shot([string]$Out) {
    Droid-Adb shell screencap -p /sdcard/shot.png
    Droid-Adb pull /sdcard/shot.png $Out 2>&1 | Out-Null
}
# THE TEST EMULATORS ONLY, AND ONLY WHILE A CHECK NEEDS THEM (the owner's word 20.10.2026: they load the computer; MontanaM and
# MontanaO are never touched): one switched on for a check, switched off when it ends -- in a finally, so an error or a time-out
# leaves none running
$script:Mine = @{ "MontanaA" = 5554; "MontanaB" = 5556; "MontanaC" = 5560 }
function Droid-Up([string]$Avd) {
    if (-not $script:Mine.ContainsKey($Avd)) { throw "android: $Avd is not a test emulator of these checks" }
    $port = $script:Mine[$Avd]
    $emu = Join-Path $env:LOCALAPPDATA "Android\Sdk\emulator\emulator.exe"
    Start-Process -FilePath $emu -ArgumentList "-avd $Avd -no-window -no-snapshot -no-audio -no-boot-anim -netdelay none -netspeed full -port $port" -WindowStyle Hidden | Out-Null
    Use-Droid "emulator-$port"
    Droid-Boot 240
}
function Droid-Off([string]$Device = $script:Droid) {
    if (@($script:Mine.Values | ForEach-Object { "emulator-$_" }) -notcontains $Device) { throw "android: $Device is not a test emulator of these checks" }
    & $script:Adb -s $Device emu kill 2>&1 | Out-Null
}
function Droid-Boot([int]$Seconds = 180) {
    $end = (Get-Date).AddSeconds($Seconds)
    do {
        $b = (Droid-Adb shell getprop sys.boot_completed 2>$null) -join ""
        if ($b.Trim() -eq "1") { return }
        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $end)
    throw "android: $script:Droid did not boot"
}
