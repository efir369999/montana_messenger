# MY NAME FOR THEM, LIVE (after tools\ab.ps1 with the same -Root): A opens B's page from «Контакты», writes «Боря» on
# «Изменить», and the chats' list says «Боря»; then A clears the name, and B's own «Борис Тест» stands again.
# usage: tools\rename.ps1 -Root DIR [-Shots DIR]
param([Parameter(Mandatory = $true)][string]$Root, [string]$Shots = "")
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ui.ps1"
function Snap($name) { if ($Shots) { Shot-Montana (Join-Path $Shots "$name.png") } }
function Says([string]$text, [int]$timeout = 60) { Find-Named $text $timeout | Out-Null; "  sees: $text" }
function Rename([string]$first, [string]$last) {
    Click-Named "Контакты"
    RightClick-Named $script:who   # the row's own menu is the person's page
    Click-Named "Изменить"
    Type-Into "Имя" $first
    Type-Into "Фамилия" $last
    Click-Named "Готово"
}
$t0 = Get-Date
$B = Start-Montana -DataDir "$Root\B"; Front-Montana -X 1000 -Y 40 -Width 900 -Height 900   # B is here: its presence is A's to read
Start-Sleep -Seconds 2
$A = Start-Montana -DataDir "$Root\A"; Front-Montana -X 0 -Y 40 -Width 1500 -Height 950
Start-Sleep -Seconds 2
"A sees B's presence under the name in «Контакты»"
Click-Named "Контакты"
$line = $null
for ($i = 0; $i -lt 250 -and -not $line; $i++) { $line = Get-Texts | Where-Object { $_ -match '^Борис Тест, (Онлайн|Недавно|На этой неделе|Очень давно|Сегодня |Вчера |\d+ мин|\d\d\.\d\d\.)' } | Select-Object -First 1; Start-Sleep -Milliseconds 300 }
if (-not $line) { throw "no presence line in «Контакты»" }
"  sees: $line"
Use-Montana $B; Stop-Montana; Use-Montana $A; Front-Montana
Click-Named "Чаты"
"A names B «Боря»"
$script:who = "Борис Тест"
Rename "Боря" ""
Says "Боря" 10
Click-Named "Назад"
Click-Named "Чаты"
Says "Боря" 10
Gone-Named "Борис Тест" 10
"  the list says «Боря»"
Snap "53-A-renamed"
"A clears it: B's own name stands again"
$script:who = "Боря"
Rename "" ""
Says "Борис Тест" 10
Click-Named "Назад"
Click-Named "Чаты"
Says "Борис Тест" 10
# «ГОТОВО» NEVER SHOWED THE WAY BACK (the freeze of 25.10.2026, Profile.jsx PeerPage: the edit is a step of B's page): left by «Назад»,
# B's page must stand again within 2 s -- not «leaving», inert under the window's foot -- and the window answer after it
"«Изменить» on B's page left by «Назад»: B's page stands again, and the window answers"
Click-Named "Контакты"
RightClick-Named "Борис Тест"   # the row's own menu is the person's page
Page-Drawn $null "Пожаловаться" 10; Start-Sleep -Milliseconds 400
Press-In-Page $null "Изменить" "Пожаловаться"
Page-Drawn "Изменить" "Фамилия"; Start-Sleep -Milliseconds 400
Press-In-Page "Изменить" "Назад"; Page-Left "Изменить" "Фамилия"
Page-Drawn $null "Пожаловаться"; Start-Sleep -Milliseconds 400
Press-In-Page $null "Назад" "Пожаловаться"; Page-Left $null "Пожаловаться"
Window-Alive "B's page → «Изменить» → «Назад» → «Назад»"
"done in $([int]((Get-Date) - $t0).TotalSeconds) s"
Stop-Montana
