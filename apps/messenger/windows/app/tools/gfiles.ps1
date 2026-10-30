# A FILE IN A GROUP, IN THE WINDOWS (after tools\ab.ps1 with the same -Root): A makes a group with B and sends a picture with a
# caption into it -- it leaves as the group's word and B gets the picture in the group.
# usage: tools\gfiles.ps1 -Root DIR [-Shots DIR]
param([Parameter(Mandatory = $true)][string]$Root, [string]$Shots = "")
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ui.ps1"
function Snap($name) { if ($Shots) { Shot-Montana (Join-Path $Shots "$name.png") } }
function Says([string]$text, [int]$timeout = 60) { Find-Named $text $timeout | Out-Null; "  sees: $text" }
Add-Type -AssemblyName System.Drawing
$stamp = Get-Date -Format "HHmmss"
$title = "Файлы $stamp"
$caption = "Картинка в группу $stamp"
$pic = Join-Path $Root "group-pic.png"
$bmp = New-Object System.Drawing.Bitmap 800, 500
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.Clear([System.Drawing.Color]::FromArgb(255, 40, 90, 160))
$g.DrawString("Group $stamp", (New-Object System.Drawing.Font("Segoe UI", [single]48)), [System.Drawing.Brushes]::White, 60, 200)
$g.Dispose(); $bmp.Save($pic, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
$t0 = Get-Date
$A = Start-Montana -DataDir "$Root\A"; Front-Montana -X 0 -Y 40 -Width 900 -Height 900
Start-Sleep -Seconds 2
"A makes the group and sends a picture into it"
Click-Named "Написать"; Click-Named "Новая группа"
Click-Named "Выбрать: Борис Тест"; Click-Named "Готово"
Type-Into "Название группы" $title; Click-Named "Готово"
Says "Вы создали группу «$title»" 15
Type-Into "Сообщение..." $caption
Files-Key; Pick-File $pic
Says $caption 20
Sent-Settle 90
Snap "93-A-group-file"
$B = Start-Montana -DataDir "$Root\B"; Front-Montana -X 920 -Y 40 -Width 900 -Height 900
Start-Sleep -Seconds 2
"B gets it in the group"
Click-Named $title 90
Says $caption 90
Snap "94-B-group-file"
"done in $([int]((Get-Date) - $t0).TotalSeconds) s"
Use-Montana $A; Stop-Montana; Use-Montana $B; Stop-Montana
