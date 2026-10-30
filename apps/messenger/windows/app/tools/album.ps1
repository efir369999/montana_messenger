# THE ONE ALBUM, LIVE (after tools\ab.ps1 with the same -Root; iOS MontanaPhotoViewer, PhotoPresenter.present(_:among:)): B sends
# two pictures; A taps the first in the chat -- the album opens on it among the chat's pictures; the arrow turns the page, a click
# at the right edge turns it back, the wheel zooms, Esc closes; opened again, a pull down closes it as the finger's pull does.
# usage: tools\album.ps1 -Root DIR [-Shots DIR]
param([Parameter(Mandatory = $true)][string]$Root, [string]$Shots = "")
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ui.ps1"
Add-Type -AssemblyName System.Windows.Forms
function Snap($name) { if ($Shots) { Shot-Montana (Join-Path $Shots "$name.png") } }
function Says([string]$text, [int]$timeout = 60) { Find-Named $text $timeout | Out-Null; "  sees: $text" }
function Picture([string]$path, $from, $to, [string]$words) {
    $bmp = New-Object System.Drawing.Bitmap 1200, 800
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush ((New-Object System.Drawing.Point 0, 0), (New-Object System.Drawing.Point 1200, 800), $from, $to)
    $g.FillRectangle($brush, 0, 0, 1200, 800)
    $g.DrawString($words, (New-Object System.Drawing.Font "Segoe UI", 72), [System.Drawing.Brushes]::White, 60, 300)
    $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
}
# a press of the mouse at a share of the window (0..1 each way), or a drag from one share to another
function Press([double]$fx, [double]$fy, [double]$tx = -1, [double]$ty = -1) {
    $r = New-Object MontanaWin+Rect; [MontanaWin]::GetWindowRect($script:proc.MainWindowHandle, [ref]$r) | Out-Null
    $x = [int]($r.Left + ($r.Right - $r.Left) * $fx); $y = [int]($r.Top + ($r.Bottom - $r.Top) * $fy)
    [MontanaMouse]::SetCursorPos($x, $y) | Out-Null; Start-Sleep -Milliseconds 100
    [MontanaMouse]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
    if ($tx -ge 0) {
        $x2 = [int]($r.Left + ($r.Right - $r.Left) * $tx); $y2 = [int]($r.Top + ($r.Bottom - $r.Top) * $ty)
        for ($i = 1; $i -le 12; $i++) { [MontanaMouse]::SetCursorPos([int]($x + ($x2 - $x) * $i / 12), [int]($y + ($y2 - $y) * $i / 12)) | Out-Null; Start-Sleep -Milliseconds 25 }
    }
    [MontanaMouse]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
}
$t0 = Get-Date
$one = Join-Path $Root "album-one.png"; Picture $one ([System.Drawing.Color]::DarkBlue) ([System.Drawing.Color]::Teal) "Первая"
$two = Join-Path $Root "album-two.png"; Picture $two ([System.Drawing.Color]::DarkGreen) ([System.Drawing.Color]::Gold) "Вторая"

$A = Start-Montana -DataDir "$Root\A"; Front-Montana -X 0 -Y 40 -Width 900 -Height 900
$B = Start-Montana -DataDir "$Root\B"; Front-Montana -X 920 -Y 40 -Width 900 -Height 900
"B sends two pictures"
Click-Named "Алиса Тест"
Files-Key; Pick-File $one; Start-Sleep -Seconds 2
Files-Key; Pick-File $two
# the pictures left: A's window is on, so the ladder under the newest walks on to «Доставлено» -- in a triage of 25.10.2026 its
# «Отправлено» stood 0.2 s and 1.7 s, less than a look at the whole window may take; the newest leaves (no «Отправка…» twice running),
# then the ladder says it left, at whichever rung
Sent-Settle 60
$x = Get-Texts
if (-not (($x -contains "Отправлено") -or ($x -contains "Доставлено") -or ($x -contains "Прочитано"))) { throw "the pictures never left" }
"  sees: the pictures left"

"A taps the first: the album opens on it among the chat's pictures"
Use-Montana $A; Front-Montana
Click-Named "Борис Тест"
# the album's own words say where it stands: «Фото N / M»
function Album-At {
    foreach ($e in (All-Named)) { try { if ($e.Current.Name -match '^Фото (\d+) / (\d+)$') { return @([int]$Matches[1], [int]$Matches[2]) } } catch {} }
    $null
}
function Album-Says([int]$n, [int]$timeout = 5) {
    $end = (Get-Date).AddSeconds($timeout)
    do { $w = Album-At; if ($w -and $w[0] -eq $n) { "  album at $($w[0]) / $($w[1])"; return }; Start-Sleep -Milliseconds 200 } while ((Get-Date) -lt $end)
    throw "the album stands at $w, not $n"
}
function Newest-Picture {
    $end = (Get-Date).AddSeconds(90)
    do {
        $shots = @(All-Named | Where-Object { try { $_.Current.Name -eq "Фото" } catch { $false } })
        if ($shots.Count -ge 1) { $shots[$shots.Count - 1].GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke(); return }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $end)
    throw "no picture came"
}
Start-Sleep -Seconds 5
Newest-Picture
Start-Sleep -Milliseconds 800
$w = Album-At
if (-not $w -or $w[0] -ne $w[1] -or $w[1] -lt 2) { throw "the album did not open on the newest of the chat's pictures ($w)" }
$last = $w[1]
"  the album opened on the newest: $last / $last"
Start-Sleep -Seconds 1
Snap "album-1-open"
"the arrow turns the page back; a click at the right edge turns it forward"
[System.Windows.Forms.SendKeys]::SendWait("{LEFT}"); Album-Says ($last - 1)
Press 0.96 0.4; Album-Says $last
"the wheel zooms the page"
$r = New-Object MontanaWin+Rect; [MontanaWin]::GetWindowRect($script:proc.MainWindowHandle, [ref]$r) | Out-Null
[MontanaMouse]::SetCursorPos([int](($r.Left + $r.Right) / 2), [int](($r.Top + $r.Bottom) / 2)) | Out-Null
for ($i = 0; $i -lt 4; $i++) { [MontanaMouse]::mouse_event(0x0800, 0, 0, 120, [UIntPtr]::Zero); Start-Sleep -Milliseconds 80 }
Start-Sleep -Milliseconds 500
Snap "album-2-zoomed"
"Esc closes"
[System.Windows.Forms.SendKeys]::SendWait("{ESC}"); Start-Sleep -Milliseconds 500
if (Album-At) { throw "Esc did not close the album" }
"opened again, a pull down closes it"
Newest-Picture; Album-Says $last
Press 0.5 0.35 0.5 0.75; Start-Sleep -Milliseconds 600
if (Album-At) { throw "the pull did not close the album" }
"done in $([int]((Get-Date) - $t0).TotalSeconds) s"
Use-Montana $A; Stop-Montana; Use-Montana $B; Stop-Montana
