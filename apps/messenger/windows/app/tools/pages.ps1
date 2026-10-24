# THE PAGES, LIVE (after tools\ab.ps1 with the same -Root): A opens the drawer and Settings (the key to the 24 words is
# there; it is not pressed -- it asks Windows Hello, a manual check: tools\manual-hello.ps1 -Owner), switches the language to
# English and back; on My page A takes a photo, a bio and a link; B sees them on A's page through the network.
# usage: tools\pages.ps1 -Root DIR [-Shots DIR]
param([Parameter(Mandatory = $true)][string]$Root, [string]$Shots = "")
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ui.ps1"
function Snap($name) { if ($Shots) { Shot-Montana (Join-Path $Shots "$name.png") } }
function Says([string]$text, [int]$timeout = 30) { Find-Named $text $timeout | Out-Null; "  sees: $text" }
$t0 = Get-Date
$A = Start-Montana -DataDir "$Root\A"; Front-Montana -X 0 -Y 40 -Width 1500 -Height 950

"A: the drawer"
Open-Drawer; Says "Стена Мыслей"; Says "Настройки"
Snap "13-A-drawer"
"A: Settings (the key to the words stands; Windows Hello is a manual check)"
Click-Named "Настройки"; Says "Сохранить 24 слова"
Snap "14-A-settings"
# the window opened again from its first page, as the next step expects
Stop-Montana
$A = Start-Montana -DataDir "$Root\A"; Front-Montana -X 0 -Y 40 -Width 1500 -Height 950

"A: the language to English and back"
Open-Drawer; Click-Named "Настройки"; Click-Named "Язык"; Click-Named "English"
try {
    Start-Sleep -Seconds 2; Says "Search"
} finally {
    # Russian comes back whatever happened: A and B are the next scenes' identities, and every scene reads Russian words
    Open-Drawer; Click-Named "Settings"; Click-Named "Language"; Click-Named "Русский"
}
Start-Sleep -Seconds 2; Says "Поиск"

"A: My page -- a photo, a bio, a link"
$pic = Join-Path $Root "face.png"
$bmp = New-Object System.Drawing.Bitmap 900, 700
$g = [System.Drawing.Graphics]::FromImage($bmp); $g.Clear([System.Drawing.Color]::SteelBlue)
$g.FillEllipse([System.Drawing.Brushes]::Gold, 250, 150, 400, 400); $bmp.Save($pic, [System.Drawing.Imaging.ImageFormat]::Png)
Open-Drawer; Click-Named "Алиса Тест"
Click-Named "Изменить"
# a person who already wears a photo (a root used before) takes it off first: the row then offers to choose one
Start-Sleep -Milliseconds 500
if ((Get-Texts) -contains "Изменить фотографию") { Click-Named "Изменить фотографию"; Click-Named "Удалить фотографию"; Start-Sleep -Seconds 1 }
Click-Named "Выбрать фотографию"; Pick-File $pic
Click-Named "Готово"
Start-Sleep -Seconds 1
Type-Into "О себе" "Пишу с Windows, проверяю Montana."
Type-Into "Ссылка" "montana.quest"
Click-Named "Готово"
Says "Пишу с Windows, проверяю Montana."; Says "montana.quest"   # a page's link stands by its address without its scheme (iOS 2304 MTPageLinks)
Snap "16-A-mypage"
Click-Named "Назад"

"B: A's page through the network"
$B = Start-Montana -DataDir "$Root\B"; Front-Montana -X 0 -Y 40 -Width 1500 -Height 950
Click-Named "Контакты"
$deadline = (Get-Date).AddSeconds(90); $ok = $false
while (-not $ok -and (Get-Date) -lt $deadline) {
    RightClick-Named "Алиса Тест"
    if ((Get-Texts) -contains "Пишу с Windows, проверяю Montana.") { $ok = $true } else { Click-Named "Назад"; Start-Sleep -Seconds 5 }
}
if (-not $ok) { throw "B never saw A's bio" }
"  sees: A's bio and link"
Snap "17-B-peer"
"done in $([int]((Get-Date) - $t0).TotalSeconds) s"
Use-Montana $A; Stop-Montana; Use-Montana $B; Stop-Montana
