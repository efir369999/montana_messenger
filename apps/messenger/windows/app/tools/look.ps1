# THE MESSAGE STYLE, LIVE (after tools\ab.ps1 with the same -Root): A opens Settings → «Оформление»; the preview's own
# bubble is the platform's blue under «Монтана»; «Свой» with its first colours (a fill at a fifth) turns it dark, and the
# choice stays across a restart; A sets «Монтана» back. The colour is read off the screen beside the bubble's words. Then the
# feed's motion: its two sliders start at iOS's own, stay across a restart, and the reset gives them back.
# usage: tools\look.ps1 -Root DIR [-Shots DIR]
param([Parameter(Mandatory = $true)][string]$Root, [string]$Shots = "")
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ui.ps1"
function Snap($name) { if ($Shots) { Shot-Montana (Join-Path $Shots "$name.png") } }
function Says([string]$text, [int]$timeout = 60) { Find-Named $text $timeout | Out-Null; "  sees: $text" }
# THE BUBBLE'S FILL: the colour most of a strip through the words' middle wears, the words' white and the page's black left out --
# read once the page stands still. A point beside the words lied twice: a page slides in from the right as iOS pushes one, and the
# preview is drawn transformed, so the tree's box of the words stands some fifty points off what the eye sees
function Fill([string]$words) {
    Front-Montana; Start-Sleep -Milliseconds 400
    $r = (Find-Named $words 10).Current.BoundingRectangle
    $end = (Get-Date).AddSeconds(5)
    do {
        Start-Sleep -Milliseconds 250
        $was = $r; $r = (Find-Named $words 10).Current.BoundingRectangle
    } while (($r.X -ne $was.X -or $r.Y -ne $was.Y) -and (Get-Date) -lt $end)
    $x0 = [int][Math]::Max(0, $r.X - 120); $w = [int]($r.Width + 240); $y = [int]($r.Y + $r.Height / 2)
    $bmp = New-Object System.Drawing.Bitmap $w, 1
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($x0, $y, 0, 0, (New-Object System.Drawing.Size $w, 1))
    $count = @{}
    for ($i = 0; $i -lt $w; $i++) {
        $c = $bmp.GetPixel($i, 0)
        $hi = [Math]::Max($c.R, [Math]::Max($c.G, $c.B)); $lo = [Math]::Min($c.R, [Math]::Min($c.G, $c.B))
        if ($hi -lt 40 -or $lo -gt 200) { continue }   # the page's black, the words' white
        $k = "$($c.R),$($c.G),$($c.B)"; $count[$k] = 1 + [int]$count[$k]
    }
    $top = ($count.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 1).Key
    if (-not $top) { $bmp.Save((Join-Path $env:TEMP "montana-look-strip.png")); "  strip at x=$x0 y=$y w=$w (rect $r)" }
    $g.Dispose(); $bmp.Dispose()
    if (-not $top) { throw "no fill under '$words'" }
    $v = $top -split ','
    [System.Drawing.Color]::FromArgb([int]$v[0], [int]$v[1], [int]$v[2])
}
function Open-Look { Open-Drawer; Click-Named "Настройки"; Click-Named "Оформление"; Says "Стиль сообщений" 10 }
# a slider of the page by its name: its value read, or set as a hand would set it
function Range([string]$name, [double]$set = [double]::NaN) {
    Find-Named $name 10 | Out-Null
    $e = All-Named | Where-Object { try { $_.Current.Name -eq $name -and $_.Current.ControlType -eq [System.Windows.Automation.ControlType]::Slider } catch { $false } } | Select-Object -First 1
    if (-not $e) { throw "no slider named '$name'" }
    $p = $null
    if (-not $e.TryGetCurrentPattern([System.Windows.Automation.RangeValuePattern]::Pattern, [ref]$p)) { throw "'$name' is no slider" }
    if (-not [double]::IsNaN($set)) { $p.SetValue($set); Start-Sleep -Milliseconds 300 }
    [Math]::Round($p.Current.Value, 2)
}
$env:MONTANA_TRACE = "1"
Remove-Item "$Root\A\trace.log" -ErrorAction SilentlyContinue
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class MontanaIcon { [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, IntPtr l); }
"@
# the window's own big icon, as Windows hands it to the taskbar (WM_GETICON, ICON_BIG)
function BigIcon { [MontanaIcon]::SendMessage((Handle), 0x007F, [IntPtr]1, [IntPtr]::Zero) }
function Wrote([string]$line, [int]$timeout = 15) {
    $end = (Get-Date).AddSeconds($timeout)
    do { if (Get-Content "$Root\A\trace.log" -Encoding UTF8 -ErrorAction SilentlyContinue | Where-Object { $_ -like "*$line*" }) { "  A: $line"; return }; Start-Sleep -Milliseconds 400 } while ((Get-Date) -lt $end)
    throw "A never wrote '$line'"
}
function Chosen([string]$name) { $p = $null; (Find-Named $name 10).TryGetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern, [ref]$p) -and $p.Current.IsSelected }
$t0 = Get-Date
$A = Start-Montana -DataDir "$Root\A"; Front-Montana -X 0 -Y 40 -Width 1200 -Height 1000
Start-Sleep -Seconds 2
Open-Look
$c = Fill "Ваше сообщение"
"  Montana: rgb($($c.R), $($c.G), $($c.B))"
if (-not ($c.B -gt 180 -and $c.R -lt 80)) { throw "Montana's bubble is not the platform's blue" }
Click-Named "Свой"
Says "Ваш пузырёк" 5
$c = Fill "Ваше сообщение"
"  Custom: rgb($($c.R), $($c.G), $($c.B))"
if (-not ($c.B -lt 130)) { throw "the custom fill at a fifth is not dark" }
Snap "59-A-look"
Stop-Montana
"the choice stays across a restart"
$A = Start-Montana -DataDir "$Root\A"; Front-Montana -X 0 -Y 40 -Width 1200 -Height 1000
Start-Sleep -Seconds 2
Open-Look
Says "Ваш пузырёк" 5
$c = Fill "Ваше сообщение"
if (-not ($c.B -lt 130)) { throw "the custom fill did not stay" }
"  still custom: rgb($($c.R), $($c.G), $($c.B))"
Click-Named "Монтана (по умолчанию)"
$c = Fill "Ваше сообщение"
if (-not ($c.B -gt 180)) { throw "Montana did not come back" }
"  Montana again"
"the feed's motion (iOS MTLetterMotion): springiness and duration stay across a restart, and the reset gives iOS's own"
if ((Range "Упругость") -ne 0.18 -or (Range "Длительность анимации") -ne 0.55) { throw "the motion does not start at iOS's own 0.18 and 0.55" }
Range "Упругость" 0.3 | Out-Null; Range "Длительность анимации" 0.7 | Out-Null
Stop-Montana
$A = Start-Montana -DataDir "$Root\A"; Front-Montana -X 0 -Y 40 -Width 1200 -Height 1000
Start-Sleep -Seconds 2
Open-Look
$b = Range "Упругость"; $d = Range "Длительность анимации"
if ($b -ne 0.3 -or $d -ne 0.7) { throw "the motion did not stay: $b, $d" }
"  stayed: springiness $b, duration $d"
Click-Named "Сбросить движение"
$b = Range "Упругость"; $d = Range "Длительность анимации"
if ($b -ne 0.18 -or $d -ne 0.55) { throw "the reset gave $b, $d" }
"  reset: springiness $b, duration $d"
"the app's icon (iOS setAlternateIconName): «Золото на чёрном» worn by the window, kept across a restart, the glass back"
$before = BigIcon
Click-Named "Золото на чёрном"
Wrote "app_icon set gold ok"
Start-Sleep -Milliseconds 500
$after = BigIcon
if ($after -eq $before) { throw "the window's icon did not change" }
"  the window's icon changed ($before -> $after)"
Stop-Montana
Remove-Item "$Root\A\trace.log" -ErrorAction SilentlyContinue
$A = Start-Montana -DataDir "$Root\A"; Front-Montana -X 0 -Y 40 -Width 1200 -Height 1000
Wrote "app_icon set gold ok" 20
Open-Look
if (-not (Chosen "Золото на чёрном")) { throw "the gold icon is not marked chosen after the restart" }
"  still gold after the restart"
Click-Named "Жидкое стекло"
Wrote "app_icon set glass ok"
"done in $([int]((Get-Date) - $t0).TotalSeconds) s"
Stop-Montana
