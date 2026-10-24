# A GROUP'S RIGHTS, LIVE (after tools\groups.ps1 with the same -Root): A, the owner, takes «Отправлять сообщения» from the
# members on the group's «Разрешения»; B's field says why his words do not go; A gives the words back and names B an
# administrator on «Права администратора» -- the title «Модератор», without «Удалять сообщения» -- and B's page of the group
# shows him «Модератор». The windows are narrow: the conversation stands alone, and its title opens the group's page.
# usage: tools\grights.ps1 -Root DIR [-Shots DIR]
param([Parameter(Mandatory = $true)][string]$Root, [string]$Shots = "")
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ui.ps1"
function Snap($name) { if ($Shots) { Shot-Montana (Join-Path $Shots "$name.png") } }
function Says([string]$text, [int]$timeout = 60) { Find-Named $text $timeout | Out-Null; "  sees: $text" }
function Group-Title { $t = $null; for ($i = 0; $i -lt 40 -and -not $t; $i++) { $t = Get-Texts | Where-Object { $_ -like "Группа *" } | Select-Object -First 1; Start-Sleep -Milliseconds 300 }; if (-not $t) { throw "no group in the list" }; $t }
$t0 = Get-Date
$A = Start-Montana -DataDir "$Root\A"; Front-Montana -X 0 -Y 40 -Width 700 -Height 950
Start-Sleep -Seconds 2
$title = Group-Title
"A takes the words from the members of «$title»"
Click-Named $title; Start-Sleep -Seconds 1; Click-Named $title
Click-Named "Разрешения"
Says "Что могут участники этой группы?" 10
Click-Named "Отправлять сообщения"
Snap "44-A-rights"
Click-Named "Назад"   # the page goes, and what the owner left goes with it
Start-Sleep -Seconds 15   # the owner's machine carries the new invitation to every member before it closes
Stop-Montana

"B's words do not go"
$B = Start-Montana -DataDir "$Root\B"; Front-Montana -X 0 -Y 40 -Width 1500 -Height 950
Start-Sleep -Seconds 2
Click-Named $title
$deadline = (Get-Date).AddSeconds(90); $refused = $false
while (-not $refused -and (Get-Date) -lt $deadline) {
    Type-Into "Сообщение..." "Можно мне сказать?"; Click-Named "Отправить"
    Start-Sleep -Seconds 1
    if ((Get-Texts) -contains "Отправка сообщений в этой группе запрещена") { $refused = $true } else { Start-Sleep -Seconds 4 }
}
if (-not $refused) { throw "B's field never said the words are taken" }
"  sees: Отправка сообщений в этой группе запрещена"
Snap "45-B-refused"
Stop-Montana

"A gives the words back and names B an administrator"
$A = Start-Montana -DataDir "$Root\A"; Front-Montana -X 0 -Y 40 -Width 700 -Height 950
Start-Sleep -Seconds 2
Click-Named $title; Start-Sleep -Seconds 1; Click-Named $title
Click-Named "Разрешения"; Click-Named "Отправлять сообщения"; Click-Named "Назад"
Start-Sleep -Seconds 3
Click-Named $title; Start-Sleep -Seconds 1; Click-Named $title
Says "12/12" 15
Click-Named "Назначить администратором"
Says "Что может этот администратор?" 10
Type-Into "Своя подпись" "Модератор"
Click-Named "Удалять сообщения"
Click-Named "Готово"
Says "Разжаловать администратора" 15
Says "Модератор" 10
$Aon = $A   # the owner's machine stays on: what a node did not take goes again with its walks

"B names A with «@»"
$B = Start-Montana -DataDir "$Root\B"; Front-Montana -X 720 -Y 40 -Width 1100 -Height 950
Start-Sleep -Seconds 2
Click-Named $title
# B's machine may not have heard yet that the words are given back: its field refuses, and B tries again
$sent = $false
for ($i = 0; $i -lt 12 -and -not $sent; $i++) {
    Type-Into "Сообщение..." "@Ал"
    Says "@Алиса Тест" 15
    Click-Named "@Алиса Тест"; Click-Named "Отправить"
    Start-Sleep -Seconds 1
    if ((Get-Texts) -contains "Отправка сообщений в этой группе запрещена") { Start-Sleep -Seconds 4 } else { $sent = $true }
}
if (-not $sent) { throw "B's field kept refusing" }
# the ladder under the letter: the owner's machine is on, so «Отправлено» may turn «Доставлено» between two looks
$gone = $false
for ($i = 0; $i -lt 60 -and -not $gone; $i++) { $x = Get-Texts; $gone = ($x -contains "Отправлено") -or ($x -contains "Доставлено"); if (-not $gone) { Start-Sleep -Seconds 1 } }
if (-not $gone) { throw "B's letter never left" }
"  sees: the letter left"
Stop-Montana

"B is an administrator"
$B = Start-Montana -DataDir "$Root\B"; Front-Montana -X 720 -Y 40 -Width 700 -Height 950
Start-Sleep -Seconds 2
Click-Named $title; Start-Sleep -Seconds 1; Click-Named $title
Says "Модератор" 90
Snap "46-B-admin"
"done in $([int]((Get-Date) - $t0).TotalSeconds) s"
Stop-Montana; Use-Montana $Aon; Stop-Montana
