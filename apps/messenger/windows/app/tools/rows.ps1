# THE ROW'S MENU (after tools\ab.ps1 with the same -Root): A pins B's chat, mutes it, archives it (the «Archive» row appears
# and opens the archive), brings it back, unmutes and unpins it -- the person's own order of the list, said to nobody. It
# begins by undoing what an earlier run may have left, and leaves the chat as it found it.
# usage: tools\rows.ps1 -Root DIR [-Shots DIR]
param([Parameter(Mandatory = $true)][string]$Root, [string]$Shots = "")
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ui.ps1"
function Snap($name) { if ($Shots) { Shot-Montana (Join-Path $Shots "$name.png") } }
function Says([string]$text, [int]$timeout = 15) { Find-Named $text $timeout | Out-Null; "  sees: $text" }
function Menu([string]$item) { RightClick-Named "Борис Тест"; Click-Named $item; Start-Sleep -Milliseconds 400 }
function Offers([string]$item) {   # whether the row's menu offers it; the menu then closes by a click on the shade far from it
    RightClick-Named "Борис Тест"; $has = (Get-Texts) -contains $item
    $r = New-Object MontanaWin+Rect; [MontanaWin]::GetWindowRect($script:proc.MainWindowHandle, [ref]$r) | Out-Null
    [MontanaMouse]::SetCursorPos($r.Right - 40, $r.Bottom - 40) | Out-Null
    [MontanaMouse]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero); [MontanaMouse]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 400; $has
}
# THE ARCHIVE'S ROW IS SUMMONED (iOS onPull > 25): one notch of the wheel up over the list's top brings it -- short of the coin's
# 140, the panel stays as it stands
function Pull-Archive {
    $e = Find-Named "Поиск" 10
    $r = $e.Current.BoundingRectangle
    [MontanaMouse]::SetCursorPos([int]($r.X + $r.Width / 2), [int]($r.Y + $r.Height / 2)) | Out-Null
    Start-Sleep -Milliseconds 150
    [MontanaMouse]::mouse_event(0x0800, 0, 0, 120, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 700
}
$A = Start-Montana -DataDir "$Root\A"; Front-Montana -X 0 -Y 40 -Width 1500 -Height 950
Start-Sleep -Seconds 2
"A: the chat as an earlier run may have left it, undone"
Pull-Archive
if ((Get-Texts) -contains "Архив") { Click-Named "Архив"; Menu "Из архива"; Click-Named "Назад" }   # the archive is a page pushed over the chats: its way back
Find-Named "Борис Тест" 20 | Out-Null
if (Offers "Вкл. звук") { Menu "Вкл. звук" }
if (Offers "Открепить") { Menu "Открепить" }
"A: pin, mute, archive"
Menu "Закрепить"
RightClick-Named "Борис Тест"; Says "Открепить"; Click-Named "Выкл. звук"
RightClick-Named "Борис Тест"; Says "Вкл. звук"; Click-Named "Архив"
Start-Sleep -Milliseconds 600
Pull-Archive
Says "Архив"
Snap "18-A-archive-row"
"A: the archive, and back"
Click-Named "Архив"; Says "Борис Тест"
Menu "Из архива"
Click-Named "Назад"
Says "Борис Тест"
Menu "Вкл. звук"
Menu "Открепить"   # the archive keeps the pin (iOS archiveChat): the chat comes back pinned, and is unpinned by hand
"done"
Stop-Montana
