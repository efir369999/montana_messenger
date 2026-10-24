# SAVED MESSAGES IS NO ONE TO PICK, YET A PLACE TO FORWARD TO (iOS ContactsTabView reads its own contacts; iOS ForwardPickerView lists
# the chats tab one to one): a fresh test identity alone -- the Contacts tab shows no «Saved Messages», under neither word; a letter
# written into Saved Messages is forwarded, and the picker offers Saved Messages under its own word, the forwarded copy standing there.
# usage: tools\savedpick.ps1 -Root DIR [-Shots DIR]
param([Parameter(Mandatory = $true)][string]$Root, [string]$Shots = "")
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ui.ps1"
function Snap($name) { if ($Shots) { New-Item -ItemType Directory -Force $Shots | Out-Null; Shot-Montana (Join-Path $Shots "$name.png") } }
$t0 = Get-Date
$stamp = Get-Date -Format "HHmmss"
$dir = Join-Path $Root "S$stamp"

"born alone"
$p = Start-Montana -DataDir $dir; Front-Montana -X 0 -Y 40 -Width 1100 -Height 900
Click-Named "Продолжить с Montana"; Click-Named "Создать"; Click-Named "Готово"
Click-Named "Я понимаю и беру ответственность на себя"; Click-Named "Показать слова"
Find-Named "Ваша сид-фраза из 24 слов" | Out-Null; Start-Sleep -Milliseconds 300
Click-Named "Я записал слова в надёжном месте"; Click-Named "Ваша личность в Montana"
Find-Named "Готово" | Out-Null; Start-Sleep -Milliseconds 500
Type-First-Field "Выбор Тест"; Click-Named "Готово"
$end = (Get-Date).AddSeconds(20)
do { $tx = Get-Texts; if ($tx -contains "Принимаю") { Click-Named "Принимаю"; break }; if ($tx -contains "Чаты") { break }; Start-Sleep -Milliseconds 400 } while ((Get-Date) -lt $end)
Start-Sleep -Seconds 2
try { Click-Named "Не сейчас" 3 } catch {}

"the Contacts tab: Saved Messages is no contact"
Click-Named "Контакты"; Start-Sleep -Milliseconds 800
$tx = Get-Texts
if ($tx -contains "Saved Messages" -or $tx -contains "Избранное") { Snap "savedpick-1-contacts"; throw "Saved Messages stands among the contacts" }
"  no Saved Messages among the contacts"
Snap "savedpick-1-contacts"

"a letter into Saved Messages, forwarded: the picker offers Saved Messages by its own word"
Click-Named "Чаты"; Start-Sleep -Milliseconds 600
Click-Named "Избранное"
$t = "в избранное $stamp"
Type-Into "Сообщение..." $t; Click-Named "Отправить"
Find-Named $t 10 | Out-Null
Start-Sleep -Seconds 1
$before = ([regex]::Matches((Page-Text), [regex]::Escape($t))).Count   # the bubble, and the list's preview where the list stands beside
RightClick-Named $t; Click-Named "Переслать"
$rows = Get-Texts | Where-Object { $_ -like "Переслать: *" }
"  the picker: " + ($rows -join " | ")
if ($rows -contains "Переслать: Saved Messages") { Snap "savedpick-2-picker"; throw "the picker names the room by its key, not its word" }
if (-not ($rows -contains "Переслать: Избранное")) { Snap "savedpick-2-picker"; throw "the picker does not offer Saved Messages" }
Snap "savedpick-2-picker"
Click-Named "Переслать: Избранное"
$end = (Get-Date).AddSeconds(20)
while (([regex]::Matches((Page-Text), [regex]::Escape($t))).Count -le $before) { if ((Get-Date) -gt $end) { throw "the forwarded copy does not stand in Saved Messages" }; Start-Sleep -Milliseconds 500 }
"  the forwarded copy stands in Saved Messages"
"done in $([int]((Get-Date) - $t0).TotalSeconds) s"
Stop-Montana
