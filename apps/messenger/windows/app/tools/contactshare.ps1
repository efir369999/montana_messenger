# THE CONTACTS' SHARE, LIVE (iOS ContactsTabView mtPageAction + MontanaCardShare): a fresh throw-away identity opens «Контакты»;
# bottom right stands the chats' compose door with the share glyph on it, «Поделиться» -- my card's link of the kind the code page
# chose, in the system's share sheet (pressing it is not part of this check: the sheet is Windows' own window).
# usage: tools\contactshare.ps1 -Root DIR [-Shots DIR]
param([Parameter(Mandatory = $true)][string]$Root, [string]$Shots = "")
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ui.ps1"
if (Test-Path $Root) { Remove-Item -Recurse -Force $Root }
function Snap($name) { if ($Shots) { Shot-Montana (Join-Path $Shots "$name.png") } }
$p = Start-Montana -DataDir (Join-Path $Root "A")
try {
    Front-Montana -X 40 -Y 40 -Width 900 -Height 900
    Click-Named "Продолжить с Montana"; Click-Named "Создать"; Click-Named "Готово"
    Click-Named "Я понимаю и беру ответственность на себя"; Click-Named "Показать слова"
    Click-Named "Я записал слова в надёжном месте"; Click-Named "Ваша личность в Montana"
    Find-Named "Готово" | Out-Null; Start-Sleep -Milliseconds 500
    Type-First-Field "Анна Тест"; Click-Named "Готово"; Click-Named "Принимаю"
    Click-Named "Контакты"
    Find-Named "Поделиться" 20 | Out-Null
    "  sees: «Поделиться» bottom right of the contacts"
    Snap "contacts-share"
    "contactshare: ok"
} finally { Stop-Montana }
