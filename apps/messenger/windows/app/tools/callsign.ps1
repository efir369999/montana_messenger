# THE FIRST SCREEN'S FACE AND CALL SIGN, IN THE WINDOWS (no other scene needed): a new throwaway identity, on its name step, picks
# a photo (framed by the editor's crop) and a call sign from the list (searched: «Леопард»); the person's name is that call sign,
# and the profile editor offers the same list.
# usage: tools\callsign.ps1 -Root DIR [-Shots DIR]
param([Parameter(Mandatory = $true)][string]$Root, [string]$Shots = "")
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ui.ps1"
function Snap($name) { if ($Shots) { Shot-Montana (Join-Path $Shots "$name.png") } }
function Says([string]$text, [int]$timeout = 60) { Find-Named $text $timeout | Out-Null; "  sees: $text" }
Add-Type -AssemblyName System.Drawing
$pic = Join-Path $Root "face-test.png"
$bmp = New-Object System.Drawing.Bitmap 600, 600
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.Clear([System.Drawing.Color]::FromArgb(255, 120, 60, 160))
$g.FillEllipse([System.Drawing.Brushes]::Gold, 150, 150, 300, 300)
$g.Dispose(); $bmp.Save($pic, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
$dir = Join-Path $Root ("L" + (Get-Date -Format "HHmmss"))
$t0 = Get-Date
$L = Start-Montana -DataDir $dir; Front-Montana -X 0 -Y 40 -Width 900 -Height 900
"a new identity reaches its name step"
Click-Named "Продолжить с Montana"; Click-Named "Создать"; Click-Named "Готово"   # my page's ground first (gold)
Click-Named "Я понимаю и беру ответственность на себя"; Click-Named "Показать слова"
Click-Named "Я записал слова в надёжном месте"; Click-Named "Ваша личность в Montana"
Says "Выбрать позывной" 15
"a photo, framed"
Click-Named "Выбрать фото"; Pick-File $pic
Click-Named "Готово"
Says "Изменить фото" 15
"a call sign from the list"
Click-Named "Выбрать позывной"
Type-Into "Поиск" "Леопард"
Click-Named "Леопард"
Start-Sleep -Milliseconds 800
Snap "96-L-name-step"
Click-Named "Готово"; Click-Named "Принимаю"
"the person is that call sign"
Open-Drawer
Says "Леопард" 15
"done in $([int]((Get-Date) - $t0).TotalSeconds) s"
Stop-Montana
Start-Sleep -Seconds 2
Remove-Item -Recurse -Force $dir -ErrorAction SilentlyContinue
