# THE APPLICATIONS' ICONS, LIVE (iOS MTLibraryIconStyleView, MTApplicationIcon, MTLibrarySearch; after tools\ab.ps1 with the
# same -Root): A opens Settings → «Оформление» → «Иконки приложений», takes the view «Иконки» and «Золотой стиль»; after a
# restart the drawer is the icons' grid -- «Избранные» first, then the groups -- and its tiles are the author's gold atlas
# (the tile's mean colour, read off the window's own pixels, is warm: red over blue); «Музыка»'s menu pins it, and it stands
# among the favourites, above «Медиа». «Montana OS» draws it cool (blue over red), «Белые иконки» grey. Then the note's
# quality: «Макс» stays across a restart. A puts every choice back as it found it: the list, the white icons, «Сред».
# usage: tools\library.ps1 -Root DIR [-Shots DIR]
param([Parameter(Mandatory = $true)][string]$Root, [string]$Shots = "")
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ui.ps1"
function Snap($name) { if ($Shots) { Shot-Montana (Join-Path $Shots "$name.png") } }
function Says([string]$text, [int]$timeout = 60) { Find-Named $text $timeout | Out-Null; "  sees: $text" }
function Chosen([string]$name) { $p = $null; (Find-Named $name 10).TryGetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern, [ref]$p) -and $p.Current.IsSelected }
function Open-Look { Open-Drawer; Click-Named "Настройки"; Click-Named "Оформление"; Says "Стиль сообщений" 10 }
function Open-Icons { Open-Look; Click-Named "Иконки приложений"; Says "Вид" 10 }
function Restart {
    Stop-Montana
    $script:A = Start-Montana -DataDir "$Root\A"; Front-Montana -X 0 -Y 40 -Width 1200 -Height 1000
    Start-Sleep -Seconds 2
}
# the mean colour of a tile's icon in the drawer's grid: the window's own pixels (PrintWindow), the tile's top 56 around its middle
function Tint([string]$name) {
    $file = Join-Path $env:TEMP "montana-library-tint.png"
    Find-Named $name 10 | Out-Null
    # the drawer's own tile (the leftmost of that name), scrolled into the drawer's sight
    $e = All-Named | Where-Object { try { $_.Current.Name -eq $name -and $_.Current.ControlType -eq [System.Windows.Automation.ControlType]::Button } catch { $false } } |
        Sort-Object { $_.Current.BoundingRectangle.X } | Select-Object -First 1
    $p = $null
    if ($e.TryGetCurrentPattern([System.Windows.Automation.ScrollItemPattern]::Pattern, [ref]$p)) { $p.ScrollIntoView() }
    Start-Sleep -Milliseconds 700
    $er = $e.Current.BoundingRectangle
    Shot-Montana $file
    $r = New-Object MontanaWin+Rect; [MontanaWin]::GetWindowRect((Handle), [ref]$r) | Out-Null
    $bmp = [System.Drawing.Bitmap]::FromFile($file)
    $cx = [int]($er.X + $er.Width / 2 - $r.Left); $top = [int]($er.Y - $r.Top)
    $sr = 0; $sg = 0; $sb = 0; $n = 0
    for ($y = $top + 6; $y -lt $top + 56; $y += 2) { for ($x = $cx - 24; $x -lt $cx + 24; $x += 2) { $c = $bmp.GetPixel($x, $y); $sr += $c.R; $sg += $c.G; $sb += $c.B; $n++ } }
    $bmp.Dispose(); Remove-Item $file -ErrorAction SilentlyContinue
    [pscustomobject]@{ R = [int]($sr / $n); G = [int]($sg / $n); B = [int]($sb / $n) }
}
$t0 = Get-Date
$A = Start-Montana -DataDir "$Root\A"; Front-Montana -X 0 -Y 40 -Width 1200 -Height 1000
Start-Sleep -Seconds 2
"A takes the icons' grid and the gold style"
Open-Icons
Click-Named "Иконки"
Click-Named "Золотой стиль"
if (-not (Chosen "Золотой стиль")) { throw "the gold style is not marked chosen" }
Snap "150-A-library-page"
Restart
"after a restart the drawer is the grid, in gold"
Open-Drawer
Says "Избранные" 10; Says "Медиа" 5; Says "Утилиты" 5
$gold = Tint "Музыка"
"  gold: rgb($($gold.R), $($gold.G), $($gold.B))"
if (-not ($gold.R -gt $gold.B + 15)) { throw "the gold tile is not warm" }
Snap "151-A-grid-gold"
"A pins «Музыка» from its menu"
$media = (Find-Named "Медиа" 5).Current.BoundingRectangle.Y
if ((Find-Named "Музыка" 5).Current.BoundingRectangle.Y -lt $media) { throw "«Музыка» stood above «Медиа» before the pin" }
RightClick-Named "Музыка"
Click-Named "Закрепить" 5
Start-Sleep -Milliseconds 600
$media = (Find-Named "Медиа" 5).Current.BoundingRectangle.Y
if (-not ((Find-Named "Музыка" 5).Current.BoundingRectangle.Y -lt $media)) { throw "the pinned «Музыка» is not among the favourites" }
"  «Музыка» stands among the favourites"
"Montana OS and the white icons"
Restart
Open-Icons
Click-Named "Montana OS"
Restart
Open-Drawer
$native = Tint "Музыка"
"  Montana OS: rgb($($native.R), $($native.G), $($native.B))"
if (-not ($native.B -gt $native.R + 10)) { throw "the Montana OS tile is not cool" }
Restart
Open-Icons
Click-Named "Белые иконки"
Restart
Open-Drawer
$white = Tint "Музыка"
"  white: rgb($($white.R), $($white.G), $($white.B))"
if ([Math]::Abs($white.R - $white.B) -gt 12) { throw "the white icon is not grey" }
"the note's quality stays across a restart"
RightClick-Named "Музыка"
Click-Named "Открепить" 5
Restart
Open-Look
if (-not (Chosen "Сред")) { throw "the note's quality does not start at medium" }
Click-Named "Макс"
Restart
Open-Look
if (-not (Chosen "Макс")) { throw "«Макс» did not stay" }
"  «Макс» stayed"
Click-Named "Сред"
Click-Named "Иконки приложений"; Says "Вид" 10
Click-Named "Лента"
if (-not (Chosen "Лента")) { throw "the list is not back" }
"done in $([int]((Get-Date) - $t0).TotalSeconds) s"
Stop-Montana
