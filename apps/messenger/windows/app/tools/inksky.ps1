# THE INK FOLLOWS THE GROUND, IN THE WINDOW (after tools\ab.ps1 with the same -Root; iOS 2304 MTWallpaper.Ink): A's page ground is
# set to «Небо» -- the chats, the contacts and the chat with B stand on the light sky and their words turn black, the bubbles
# keep their dark plates; the window's root says «data-ink=light»; then A's page goes back to the default ground and the white
# ink returns. Snapshots for the eye: -Shots.
# usage: tools\inksky.ps1 -Root DIR [-Shots DIR]
param([Parameter(Mandatory = $true)][string]$Root, [string]$Shots = "")
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ui.ps1"
function Snap($name) { if ($Shots) { Shot-Montana (Join-Path $Shots "$name.png") } }
function Says([string]$text, [int]$timeout = 30) { Find-Named $text $timeout | Out-Null; "  sees: $text" }
function Page-Ground([string]$tile) {
    Open-Drawer; Click-Named "Алиса Тест"
    Click-Named "Изменить"; Click-Named "Изменить фон страницы"
    Click-Named $tile; Find-Named "Предпросмотр" 10 | Out-Null; Click-Named "Готово"; Gone-Named "Предпросмотр" 10
    Click-Named "Готово"; Click-Named "Готово"; Click-Named "Назад"
}
$A = Start-Montana -DataDir "$Root\A"; Front-Montana -X 0 -Y 40 -Width 1400 -Height 900
try {
    Start-Sleep -Seconds 2
    "A's page on the sky"
    Page-Ground "Небо"
    Click-Named "Чаты"; Start-Sleep -Milliseconds 800
    Snap "ink-1-chats-sky"
    Click-Named "Борис Тест"; Find-Named "Сообщение..." 15 | Out-Null; Start-Sleep -Milliseconds 800
    Snap "ink-2-chat-sky"
    Click-Named "Контакты"; Start-Sleep -Milliseconds 800
    Snap "ink-3-contacts-sky"
    Open-Drawer; Click-Named "Настройки"; Start-Sleep -Milliseconds 800
    Snap "ink-5-settings-sky"
    Click-Named "Уведомления"; Start-Sleep -Milliseconds 600
    Snap "ink-6-notifications-sky"
    Stop-Montana; Start-Sleep -Seconds 2   # the pages left by a fresh start, not by their own keys
    $A = Start-Montana -DataDir "$Root\A"; Front-Montana -X 0 -Y 40 -Width 1400 -Height 900; Start-Sleep -Seconds 2
    "A's page back to the default"
    Page-Ground "По умолчанию"
    Click-Named "Чаты"; Start-Sleep -Milliseconds 800
    Snap "ink-4-chats-default"
    "inksky: done"
} finally { Stop-Montana }
