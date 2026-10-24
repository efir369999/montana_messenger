# THE LETTER'S MENU, LIVE: two windows of tools\ab.ps1's people (run it first with the same -Root): B writes and edits a letter,
# A sees «edited» and answers it with a reaction and a reply, B sees both and deletes the reply for everyone, A loses it.
# usage: tools\deeds.ps1 -Root DIR [-Shots DIR]
param([Parameter(Mandatory = $true)][string]$Root, [string]$Shots = "")
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ui.ps1"
function Snap($name) { if ($Shots) { Shot-Montana (Join-Path $Shots "$name.png") } }
function Says([string]$text, [int]$timeout = 60) { Find-Named $text $timeout | Out-Null; "  sees: $text" }
$t0 = Get-Date
$A = Start-Montana -DataDir "$Root\A"; Front-Montana -X 0 -Y 40 -Width 900 -Height 900
$B = Start-Montana -DataDir "$Root\B"; Front-Montana -X 920 -Y 40 -Width 900 -Height 900

"B writes, then edits"
Click-Named "Алиса Тест"
Type-Into "Сообщение..." "Письмо для правки"; Click-Named "Отправить"; Says "Отправлено" 30 | Out-Null
RightClick-Named "Письмо для правки"; Click-Named "Изменить"
Type-Into "Сообщение..." "Письмо после правки"; Click-Named "Отправить"
Says "Письмо после правки"; Says "изменено"

"A sees the edit, answers with a reaction and a reply"
Use-Montana $A; Front-Montana
Click-Named "Борис Тест"
Says "Письмо после правки" 90; Says "изменено"
RightClick-Named "Письмо после правки"; Click-Named "🔥"
Says "🔥"
RightClick-Named "Письмо после правки"; Click-Named "Ответ"
Type-Into "Сообщение..." "Ответ на правку"; Click-Named "Отправить"
Says "Ответ на правку"
Snap "9-A-reply"

"B sees both, deletes the reply for everyone"
Use-Montana $B; Front-Montana
Says "🔥" 90; Says "Ответ на правку" 90
Snap "10-B-reaction"
RightClick-Named "Ответ на правку"; Click-Named "Удалить"; Click-Named "Удалить у всех"
Gone-Named "Ответ на правку" 10; "  B: gone here"

"A loses the reply"
Use-Montana $A; Front-Montana
Gone-Named "Ответ на правку" 90; "  A: gone there"
"done in $([int]((Get-Date) - $t0).TotalSeconds) s"
Use-Montana $A; Stop-Montana; Use-Montana $B; Stop-Montana
