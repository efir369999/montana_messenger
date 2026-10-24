# A GROUP'S PHOTO, LIVE (after tools\groups.ps1 with the same -Root): A, the owner, opens the group's page, chooses a picture
# in Windows' Open dialog, frames it and gives it; the group's feed says «Вы изменили фото группы». The members' side is the
# live test's (groups::tests: Bob and Carol hold the very JPEG).
# usage: tools\gface.ps1 -Root DIR [-Shots DIR]
param([Parameter(Mandatory = $true)][string]$Root, [string]$Shots = "")
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ui.ps1"
Add-Type -AssemblyName System.Drawing
function Snap($name) { if ($Shots) { Shot-Montana (Join-Path $Shots "$name.png") } }
function Says([string]$text, [int]$timeout = 60) { Find-Named $text $timeout | Out-Null; "  sees: $text" }
$t0 = Get-Date
$bmp = New-Object System.Drawing.Bitmap 600, 400
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.FillRectangle([System.Drawing.Brushes]::DarkGreen, 0, 0, 600, 400)
$g.FillEllipse([System.Drawing.Brushes]::Gold, 200, 100, 200, 200)
$pic = Join-Path $Root "group-face.png"; $bmp.Save($pic, [System.Drawing.Imaging.ImageFormat]::Png)

$A = Start-Montana -DataDir "$Root\A"; Front-Montana -X 0 -Y 40 -Width 700 -Height 950
Start-Sleep -Seconds 2
$title = $null
for ($i = 0; $i -lt 40 -and -not $title; $i++) { $title = Get-Texts | Where-Object { $_ -like "Группа *" } | Select-Object -First 1; Start-Sleep -Milliseconds 300 }
if (-not $title) { throw "no group in A's list" }
"A opens «$title» and its page"
Click-Named $title
Start-Sleep -Seconds 1
Click-Named $title   # the narrow window shows the conversation alone: its title opens the group's page
Click-Named "Выбрать фотографию"; Pick-File $pic
Click-Named "Готово"
Says "Изменить фотографию" 15
Snap "33-A-group-face"
Says "Вы изменили фото группы" 15   # the feed under the page holds the event row
"done in $([int]((Get-Date) - $t0).TotalSeconds) s"
Stop-Montana
