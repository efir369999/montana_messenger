# Drives Montana on a device or emulator over adb, for the functional checks (README.md, Tests):
# find a view by its text (uiautomator), tap it, wait for it, take a screenshot.
#   . tools\ui.ps1            # then: Ui-Texts; Ui-Tap "Create"; Ui-Wait "Show Words"; Ui-Shot "02-create"
# The device is MONTANA_DEVICE, or emulator-5554.
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$script:Adb = Join-Path $env:LOCALAPPDATA "Android\Sdk\platform-tools\adb.exe"
$script:Dev = if ($env:MONTANA_DEVICE) { $env:MONTANA_DEVICE } else { "emulator-5554" }
$script:Shots = Join-Path (Split-Path $PSScriptRoot) "out\test"

function Ui-Adb { & $script:Adb -s $script:Dev @args }

function Ui-Nodes {
    Ui-Adb shell uiautomator dump /sdcard/ui.xml | Out-Null
    $x = [xml]((Ui-Adb shell cat /sdcard/ui.xml) -join "`n")
    $x.SelectNodes("//node") | ForEach-Object {
        if ($_.bounds -match '\[(\d+),(\d+)\]\[(\d+),(\d+)\]') {
            [pscustomobject]@{
                Text = $_.text; Desc = $_.'content-desc'; Class = $_.class; Checked = $_.checked
                X = [int](([int]$Matches[1] + [int]$Matches[3]) / 2); Y = [int](([int]$Matches[2] + [int]$Matches[4]) / 2)
                Bounds = $_.bounds
            }
        }
    }
}

function Ui-Texts {
    Ui-Nodes | Where-Object { $_.Text -or $_.Desc } | ForEach-Object { "{0} | {1} | ({2},{3})" -f $_.Text, $_.Desc, $_.X, $_.Y }
}

function Ui-Tap([string]$Text, [int]$Index = 0) {
    $n = @(Ui-Nodes | Where-Object { $_.Text -eq $Text -or $_.Desc -eq $Text })
    if ($n.Count -le $Index) { throw "no view with text '$Text'" }
    Ui-Adb shell input tap $n[$Index].X $n[$Index].Y
    "tapped '$Text' at ($($n[$Index].X),$($n[$Index].Y))"
}

function Ui-Wait([string]$Text, [int]$Seconds = 30) {
    $t0 = Get-Date
    while (((Get-Date) - $t0).TotalSeconds -lt $Seconds) {
        if (Ui-Nodes | Where-Object { $_.Text -like "*$Text*" -or $_.Desc -like "*$Text*" }) { return "found '$Text'" }
        Start-Sleep -Milliseconds 700
    }
    throw "timeout waiting for '$Text'"
}

function Ui-Shot([string]$Name) {
    New-Item -ItemType Directory -Force $script:Shots | Out-Null
    Ui-Adb shell screencap -p /sdcard/shot.png
    Ui-Adb pull /sdcard/shot.png (Join-Path $script:Shots "$Name.png") 2>&1 | Out-Null
    Join-Path $script:Shots "$Name.png"
}

function Ui-Log { Ui-Adb logcat -d -v time -s Montana:V AndroidRuntime:E }
