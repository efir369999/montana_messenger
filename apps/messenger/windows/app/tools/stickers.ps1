# A STICKER SET, IN THE WINDOWS (after tools\ab.ps1 with the same -Root): A adds a picture with a transparent ground to its own set
# («Эмодзи» → «Стикеры» → «Добавить стикер»), sends the sticker to B -- a picture letter without a bubble and its passport; B
# meets A's set by it, asks for it («Получить набор») and the set's page lands: B's panel holds A's sticker.
# usage: tools\stickers.ps1 -Root DIR [-Shots DIR]
param([Parameter(Mandatory = $true)][string]$Root, [string]$Shots = "")
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ui.ps1"
function Snap($name) { if ($Shots) { Shot-Montana (Join-Path $Shots "$name.png") } }
function Says([string]$text, [int]$timeout = 60) { Find-Named $text $timeout | Out-Null; "  sees: $text" }
Add-Type -AssemblyName System.Drawing
$pic = Join-Path $Root "sticker-test.png"
$bmp = New-Object System.Drawing.Bitmap 400, 400
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.Clear([System.Drawing.Color]::Transparent)
$g.FillEllipse((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 230, 180, 60))), 40, 40, 320, 320)
$g.DrawString("M", (New-Object System.Drawing.Font("Segoe UI", [single]150, [System.Drawing.FontStyle]::Bold)), [System.Drawing.Brushes]::Black, 95, 70)
$g.DrawString((Get-Date -Format "HHmmss"), (New-Object System.Drawing.Font("Segoe UI", [single]28)), [System.Drawing.Brushes]::Black, 140, 300)   # a picture of this run's own
$g.Dispose(); $bmp.Save($pic, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
$t0 = Get-Date
$B = Start-Montana -DataDir "$Root\B"; Front-Montana -X 920 -Y 40 -Width 900 -Height 900
Start-Sleep -Seconds 2
$A = Start-Montana -DataDir "$Root\A"; Front-Montana -X 0 -Y 40 -Width 900 -Height 900
Start-Sleep -Seconds 2
"A adds a sticker to its set and sends it"
Click-Named "Борис Тест"
Click-Named "Эмодзи"; Click-Named "Стикеры"
Says "Мои стикеры" 10
$before = @(Get-Texts | Where-Object { $_ -like "Мой стикер *" }).Count
Click-Named "Добавить стикер"; Pick-File $pic
$end = (Get-Date).AddSeconds(15)
while ((Get-Date) -lt $end -and @(Get-Texts | Where-Object { $_ -like "Мой стикер *" }).Count -le $before) { Start-Sleep -Milliseconds 500 }
if (@(Get-Texts | Where-Object { $_ -like "Мой стикер *" }).Count -le $before) { throw "the sticker never joined A's set" }
"  A: the set holds it"
Snap "90-A-set"
Click-Named "Мой стикер 1"
Sent-Settle 60
"B meets A's set and asks for it"
Use-Montana $B; Front-Montana
Click-Named "Алиса Тест"
Start-Sleep -Seconds 8
Click-Named "Эмодзи"; Click-Named "Стикеры"
Says "Получить набор: Montana" 90
$had = @(Get-Texts | Where-Object { $_ -match "^Montana \d+$" }).Count
Click-Named "Получить набор: Montana"
$end = (Get-Date).AddSeconds(120)
while ((Get-Date) -lt $end -and @(Get-Texts | Where-Object { $_ -match "^Montana \d+$" }).Count -le $had) { Start-Sleep -Milliseconds 500 }
if (@(Get-Texts | Where-Object { $_ -match "^Montana \d+$" }).Count -le $had) { throw "A's set never landed at B" }
"  B: A's sticker stands in B's panel"
Snap "91-B-set"
"done in $([int]((Get-Date) - $t0).TotalSeconds) s"
Use-Montana $A; Stop-Montana; Use-Montana $B; Stop-Montana
