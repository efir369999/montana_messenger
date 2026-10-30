# FILES BETWEEN TWO WINDOWS, LIVE (after tools\ab.ps1 with the same -Root): B picks a picture (the field's words its caption)
# and then a document in Windows' Open dialog, as a person does; A sees the picture drawn and the document's plate.
# usage: tools\files.ps1 -Root DIR [-Shots DIR]
param([Parameter(Mandatory = $true)][string]$Root, [string]$Shots = "")
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ui.ps1"
Add-Type -AssemblyName System.Windows.Forms
function Snap($name) { if ($Shots) { Shot-Montana (Join-Path $Shots "$name.png") } }
function Says([string]$text, [int]$timeout = 60) { Find-Named $text $timeout | Out-Null; "  sees: $text" }
$t0 = Get-Date
# a picture of its own: gradients and words, so a broken decode shows
$bmp = New-Object System.Drawing.Bitmap 1200, 800
$g = [System.Drawing.Graphics]::FromImage($bmp)
$brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush ((New-Object System.Drawing.Point 0, 0), (New-Object System.Drawing.Point 1200, 800), [System.Drawing.Color]::DarkRed, [System.Drawing.Color]::Gold)
$g.FillRectangle($brush, 0, 0, 1200, 800)
$g.DrawString("Montana Windows", (New-Object System.Drawing.Font "Segoe UI", 72), [System.Drawing.Brushes]::White, 60, 300)
$pic = Join-Path $Root "montana-test.png"; $bmp.Save($pic, [System.Drawing.Imaging.ImageFormat]::Png)
$doc = Join-Path $Root "Отчёт о проверке.txt"
[IO.File]::WriteAllText($doc, ("Montana: файл через узлы.`r`n" * 2000), (New-Object Text.UTF8Encoding $false))

$A = Start-Montana -DataDir "$Root\A"; Front-Montana -X 0 -Y 40 -Width 900 -Height 900
$B = Start-Montana -DataDir "$Root\B"; Front-Montana -X 920 -Y 40 -Width 900 -Height 900
"B picks a picture with a caption"
Click-Named "Алиса Тест"
Type-Into "Сообщение..." "Картинка с Windows"
Files-Key; Pick-File $pic
Says "Картинка с Windows"
Says "Отправлено" 60
"B picks a document"
Files-Key; Pick-File $doc
Says "Отчёт о проверке.txt" 30
Start-Sleep -Seconds 3
Snap "11-B-files"

"A receives both"
Use-Montana $A; Front-Montana
Click-Named "Борис Тест"
Says "Картинка с Windows" 90
Says "Отчёт о проверке.txt" 90
Start-Sleep -Seconds 8
Snap "12-A-files"
$texts = Get-Texts
if ($texts -contains "Не получено") { throw "a file was not received" }
"done in $([int]((Get-Date) - $t0).TotalSeconds) s"
Use-Montana $A; Stop-Montana; Use-Montana $B; Stop-Montana
