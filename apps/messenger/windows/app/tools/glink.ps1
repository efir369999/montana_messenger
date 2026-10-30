# A GROUP'S LINK, LIVE (after tools\groups.ps1 with the same -Root): A, the owner, opens the group's page and reads its link;
# C -- a fresh identity that never met A -- opens the link in «Сканировать»: C meets A's card and asks to join. A turned
# «Одобрение администратором» on, so C waits among «Заявки на вступление» until A adds C; the group stands in C's list, and
# A's feed says that C joined by the link.
# usage: tools\glink.ps1 -Root DIR [-Shots DIR]
param([Parameter(Mandatory = $true)][string]$Root, [string]$Shots = "")
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ui.ps1"
function Snap($name) { if ($Shots) { Shot-Montana (Join-Path $Shots "$name.png") } }
function Says([string]$text, [int]$timeout = 60) { Find-Named $text $timeout | Out-Null; "  sees: $text" }
$t0 = Get-Date
$A = Start-Montana -DataDir "$Root\A"; Front-Montana -X 0 -Y 40 -Width 700 -Height 900   # narrow: the conversation alone, its title opens the page
Start-Sleep -Seconds 2
$title = $null
for ($i = 0; $i -lt 40 -and -not $title; $i++) { $title = Get-Texts | Where-Object { $_ -like "Группа *" } | Select-Object -First 1; Start-Sleep -Milliseconds 300 }
if (-not $title) { throw "no group in A's list" }
"A opens «$title» and reads its link"
Click-Named $title
Start-Sleep -Seconds 1
Click-Named $title
Says "Ссылка-приглашение" 15
$link = $null
for ($i = 0; $i -lt 40 -and -not $link; $i++) { $link = Get-Texts | Where-Object { $_ -like "https://montana.quest/perp/*?jg=*" } | Select-Object -First 1; Start-Sleep -Milliseconds 300 }
if (-not $link) { throw "A's page shows no link" }
"  the link: $($link.Substring(0, 40))…"
Click-Named "Видна"   # the group shows its past to new members
Click-Named "Одобрение администратором"
Says "Новые участники смогут вступить в группу только после одобрения администратором." 10
Snap "42-A-link"   # A stays on the page: the feed under it will hold the event row

"C: a new identity opens the link"
$C = Start-Montana -DataDir "$Root\C"; Front-Montana -X 920 -Y 40 -Width 900 -Height 900
Click-Named "Продолжить с Montana"; Click-Named "Создать"; Click-Named "Готово"   # my page's ground first (gold)
Click-Named "Я понимаю и беру ответственность на себя"; Click-Named "Показать слова"
Click-Named "Я записал слова в надёжном месте"; Click-Named "Ваша личность в Montana"
Find-Named "Готово" | Out-Null; Start-Sleep -Milliseconds 500
Type-First-Field "Вера Тест"; Click-Named "Готово"; Click-Named "Принимаю"
Click-Named "Сканировать"; Type-Into "Ссылка" $link; Click-Named "Открыть"
Says "Алиса Тест" 30
"C waits for the group; A adds C from the requests"
try { Click-Named "Назад" 3 } catch {}   # a narrow window shows the conversation alone: back to the list
Use-Montana $A; Front-Montana
$added = $false
for ($i = 0; $i -lt 30 -and -not $added; $i++) {
    Click-Named "Заявки на вступление"
    try { Click-Named "Добавить в группу" 3; $added = $true } catch {
        # the page was read before the request came: back to the list, and the group's page read again
        Click-Named "Назад"; Start-Sleep -Seconds 3
        Click-Named $title; Start-Sleep -Seconds 1; Click-Named $title
    }
}
if (-not $added) { throw "C's request never stood among A's" }
"  A added C from the requests"
Use-Montana $C; Front-Montana
$t1 = Get-Date
Says $title 240
"  the group stood after $([int]((Get-Date) - $t1).TotalSeconds) s"
Snap "43-C-joined"
Click-Named $title
Says "Пишу в группу" 60   # B's letter from before C came
"A reads that C joined"
Use-Montana $A; Front-Montana
Says "вступил(а) в группу по ссылке-приглашению" 60
"done in $([int]((Get-Date) - $t0).TotalSeconds) s"
Use-Montana $C; Stop-Montana; Use-Montana $A; Stop-Montana
