# SAVED MESSAGES ON TWO DEVICES OF ONE IDENTITY, LIVE (iOS: the room rides the archive's blocks alone, the twin's pipe
# «twin:history»; no mirror, no wire to anyone). A is born on a fresh folder and writes a note to itself; B opens the same
# words on a folder of its own and holds no Saved Messages yet: the blocks stand the room with A's note. Then B writes a
# note while A holds its room: A measures the gap, asks the twin by the archive's key, and B gives the row back -- the note
# stands on A. The words go from window to window inside this check alone -- never into a file, a log or a shot.
# usage: tools\savedtwin.ps1 -Root DIR [-Shots DIR]
param([Parameter(Mandatory = $true)][string]$Root, [string]$Shots = "")
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ui.ps1"
if (Test-Path $Root) { Remove-Item -Recurse -Force $Root }
if ($Shots) { New-Item -ItemType Directory -Force $Shots | Out-Null }
function Snap($name) { if ($Shots) { Shot-Montana (Join-Path $Shots "$name.png") } }
function Says([string]$text, [int]$timeout = 60) { Find-Named $text $timeout | Out-Null; "  sees: $text" }
function Note([string]$words) {
    Click-Named "Избранное"
    Type-Into "Сообщение..." $words
    Click-Named "Отправить"
    Start-Sleep -Milliseconds 700
    try { Click-Named "Назад" 3 } catch {}   # a narrow window shows the chat over the list; a wide one beside it
}
$t0 = Get-Date
$noteA = "Заметка с A " + (Get-Random -Maximum 99999)
$noteB = "Заметка с B " + (Get-Random -Maximum 99999)

"A: a new identity; its words are read off the grid for B"
$A = Start-Montana -DataDir "$Root\A"; Front-Montana -X 0 -Y 40 -Width 900 -Height 900
Click-Named "Продолжить с Montana"; Click-Named "Создать"; Click-Named "Готово"
Click-Named "Я понимаю и беру ответственность на себя"; Click-Named "Показать слова"
Find-Named "Ваша сид-фраза из 24 слов" | Out-Null; Start-Sleep -Milliseconds 500
$words = New-Object string[] 24
$n = $null
foreach ($e in (All-Named)) {
    $s = $e.Current.Name
    if ($s -match '^(\d{1,2})\.?$' -and [int]$Matches[1] -ge 1 -and [int]$Matches[1] -le 24) { $n = [int]$Matches[1]; continue }
    if ($s -eq ".") { continue }
    if ($n -and $s -match '^[a-z]{3,8}$') { $words[$n - 1] = $s }
    $n = $null
}
if (@($words | Where-Object { $_ }).Count -ne 24) { throw "the grid gave $(@($words | Where-Object { $_ }).Count) of 24 words" }
"  the grid gave 24 words (kept in this check's memory only)"
Click-Named "Я записал слова в надёжном месте"; Click-Named "Ваша личность в Montana"
Find-Named "Готово" | Out-Null; Start-Sleep -Milliseconds 500
Type-First-Field "Алиса Тест"; Click-Named "Готово"; Click-Named "Принимаю"

"A: Saved Messages stands in the list before anything is written; a note to itself"
Says "Избранное" 30
Note $noteA
Page-Says $noteA
Snap "savedtwin-1-A"

"B: the same words on a folder of its own -- no Saved Messages here yet: the blocks stand it with A's note"
$B = Start-Montana -DataDir "$Root\B"; Front-Montana -X 920 -Y 40 -Width 900 -Height 900
Click-Named "Продолжить с Montana"; Click-Named "Открыть личность"
$end = (Get-Date).AddSeconds(15)
while ($true) { try { Type-First-Field ($words -join " "); break } catch { if ((Get-Date) -gt $end) { throw }; Start-Sleep -Milliseconds 300 } }
$words = $null
Click-Named "Восстановить"
$end = (Get-Date).AddSeconds(60)
do { $tx = Get-Texts; if ($tx -contains "Принимаю") { Click-Named "Принимаю"; break }; if ($tx -contains "Чаты") { break }; Start-Sleep -Milliseconds 500 } while ((Get-Date) -lt $end)
Page-Says $noteA 240
Snap "savedtwin-2-B"

"B writes while A holds its room: A asks the twin by the archive's key, B gives the row back"
Note $noteB
Use-Montana $A; Front-Montana
Page-Says $noteB 300
Snap "savedtwin-3-A"
"done in $([int]((Get-Date) - $t0).TotalSeconds) s"
Use-Montana $A; Stop-Montana; Use-Montana $B; Stop-Montana
