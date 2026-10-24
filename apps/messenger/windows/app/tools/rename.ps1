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
"done in $([int]((Get-Date) - $t0).TotalSeconds) s"
Stop-Montana
