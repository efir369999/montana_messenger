# EVERY LINK OF MY PAGE'S FIELD, IN THE WINDOW (iOS 2304 MTPeerAbout.links, MTFaceHeader.links; the author's word 21.10 16:37): a
# fresh throw-away identity writes «dreamdepartment.io /// montana.xxx» in its page's link field -- the page shows two bubbles,
# «dreamdepartment.io» and «montana.xxx», and nothing for «///».
# usage: tools\pagelinks.ps1 -Root DIR [-Shots DIR]
param([Parameter(Mandatory = $true)][string]$Root, [string]$Shots = "")
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ui.ps1"
if (Test-Path $Root) { Remove-Item -Recurse -Force $Root }
function Snap($name) { if ($Shots) { Shot-Montana (Join-Path $Shots "$name.png") } }
function Says([string]$text, [int]$timeout = 20) { Find-Named $text $timeout | Out-Null; "  sees: $text" }
$p = Start-Montana -DataDir (Join-Path $Root "A")
try {
    Front-Montana -X 40 -Y 40 -Width 900 -Height 900
    Click-Named "Продолжить с Montana"; Click-Named "Создать"; Click-Named "Готово"
    Click-Named "Я понимаю и беру ответственность на себя"; Click-Named "Показать слова"
    Click-Named "Я записал слова в надёжном месте"; Click-Named "Ваша личность в Montana"
    Find-Named "Готово" | Out-Null; Start-Sleep -Milliseconds 500
    Type-First-Field "Анна Тест"; Click-Named "Готово"; Click-Named "Принимаю"
    Find-Named "Поиск" 30 | Out-Null
    "my page: two links in one field"
    Open-Drawer; Click-Named "Анна Тест"
    Click-Named "Изменить"
    Type-Into "Ссылка" "dreamdepartment.io /// montana.xxx"
    Click-Named "Готово"
    Says "dreamdepartment.io"
    Says "montana.xxx"
    if ((Get-Texts) -contains "///") { throw "«///» stands on the page" }
    Snap "page-links"
    "pagelinks: ok"
} finally { Stop-Montana }
