# THE FABRIC OF TIME, LIVE (iOS MTFabric; after tools\ab.ps1 with the same -Root): A writes to B, B answers, A writes again. A
# heard B after speaking to B, so A signs a testimony of the exchange (ML-DSA-65 under the key its words derive for this
# correspondence) and gives it by the pair's own road as the fabric's word; B checks its length, its addressee (the hash the
# pair's secret gives), its window and its signature, and keeps it -- and the same the other way at A's second letter. Each
# TimeChain page then shows «Подписи: 1» and the fabric's level standing at the ceiling (the first τ₂). One testimony a day to one
# correspondent: run again the same day on the same root, the scene sees «given this segment» and the signatures already held.
# usage: tools\fabric.ps1 -Root DIR [-Shots DIR]
param([Parameter(Mandatory = $true)][string]$Root, [string]$Shots = "")
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ui.ps1"
function Snap($name) { if ($Shots) { Shot-Montana (Join-Path $Shots "$name.png") } }
function Says([string]$text, [int]$timeout = 60) { Find-Named $text $timeout | Out-Null; "  sees: $text" }
function Wrote([string]$who, [string]$line, [int]$timeout = 60) {
    $end = (Get-Date).AddSeconds($timeout)
    do { $hit = Get-Content "$Root\$who\trace.log" -Encoding UTF8 -ErrorAction SilentlyContinue | Where-Object { $_ -like "*$line*" -or ($line -eq "fabric_tx signed" -and $_ -like "*fabric_tx given this segment*") } | Select-Object -Last 1; if ($hit) { "  ${who}: $($hit -replace '^\d+ ', '')"; return }; Start-Sleep -Milliseconds 500 } while ((Get-Date) -lt $end)
    throw "$who never wrote '$line'"
}
function Send([string]$words) { Type-Into "Сообщение..." $words; [System.Windows.Forms.SendKeys]::SendWait("{ENTER}"); Says $words 20 | Out-Null }
function Signatures {
    Open-Drawer; Click-Named "Монета Времени"; Says "Баланс Времени" 15 | Out-Null; Click-Named "TimeChain"
    Says "Глобальный уровень" 10 | Out-Null
    $row = Get-Texts | Where-Object { $_ -match "^Подписи: \d+$" } | Select-Object -First 1
    $lvl = Get-Texts | Where-Object { $_ -match "^Уровень: " } | Select-Object -Last 1
    Click-Named "Назад"; Click-Named "Чаты"
    "$row; ткань — $lvl"
}
Add-Type -AssemblyName System.Windows.Forms
$env:MONTANA_TRACE = "1"
Remove-Item "$Root\A\trace.log", "$Root\B\trace.log" -ErrorAction SilentlyContinue
$t0 = Get-Date
$A = Start-Montana -DataDir "$Root\A"; Front-Montana -X 0 -Y 40 -Width 1200 -Height 950
$B = Start-Montana -DataDir "$Root\B"; Front-Montana -X 920 -Y 40 -Width 1200 -Height 950
# the levels are read once a node answered: the fabric's ceiling stands before any testimony is given
Use-Montana $A; Front-Montana; Start-Sleep -Seconds 12
Use-Montana $B; Front-Montana; Start-Sleep -Seconds 12
"A writes, B answers, A writes again"
Use-Montana $A; Front-Montana
Click-Named "Борис Тест"; Send "ткань времени 1"
Use-Montana $B; Front-Montana
Click-Named "Алиса Тест"; Says "ткань времени 1" 90
Send "ткань времени 2"
Use-Montana $A; Front-Montana
Says "ткань времени 2" 90
Wrote "A" "fabric_tx signed" 60
Send "ткань времени 3"
Use-Montana $B; Front-Montana
if (-not (Get-Content "$Root\A\trace.log" -Encoding UTF8 | Where-Object { $_ -like "*fabric_tx given this segment*" })) { Wrote "B" "fabric_rx ceiling=" 120 }
Says "ткань времени 3" 90
Wrote "B" "fabric_tx signed" 60
Use-Montana $A; Front-Montana
if (-not (Get-Content "$Root\B\trace.log" -Encoding UTF8 | Where-Object { $_ -like "*fabric_tx given this segment*" })) { Wrote "A" "fabric_rx ceiling=" 120 }
"each holds the other's signature"
$sa = Signatures; "  A: $sa"
Snap "160-A-fabric"
if ($sa -notmatch "Подписи: [1-9]") { throw "A holds no signature: $sa" }
Use-Montana $B; Front-Montana
$sb = Signatures; "  B: $sb"
if ($sb -notmatch "Подписи: [1-9]") { throw "B holds no signature: $sb" }
"B sees the balance and the Global Level at the faces (iOS MTAvatarBadgePair): A's told and capped by A's chain, and its own"
$end = (Get-Date).AddSeconds(40); $told = $null
do { $told = Get-Texts | Where-Object { $_ -match '^(Баланс \d+, )?Глобальный уровень \d+$' } | Select-Object -First 1; if (-not $told) { Start-Sleep -Seconds 3 } } while (-not $told -and (Get-Date) -lt $end)
if ($told) { "  A's face: $told" }
elseif (Get-Content "$Root\B\trace.log" -Encoding UTF8 | Where-Object { $_ -like "*coin_board chain read=false*" }) {
    "  A's face wears nothing: A's coin chain is not on its node (a check's folder writes none) -- as iOS, nothing told is shown unproven"
} else { throw "no badge at A's face, and A's chain was never asked" }
Open-Drawer; Start-Sleep -Seconds 1
$mine = Get-Texts | Where-Object { $_ -match '^(Баланс \d+, )?Глобальный уровень \d+$' } | Select-Object -Last 1
if (-not $mine) { throw "no badge at B's own face" }
"  B's own face: $mine"
Snap "163-B-badges"
[System.Windows.Forms.SendKeys]::SendWait("{ESC}")
"B's Access by level (iOS MTLevelAccessPage): the Global Level, and the functions of levels 7 and 8 standing closed below them"
Open-Drawer; Click-Named "Настройки"; Click-Named "Доступ по уровню"
Says "Глобальный уровень" 15 | Out-Null
$g = Get-Texts | Where-Object { $_ -match "^Глобальный уровень \d+$" } | Select-Object -First 1
if (-not $g) { throw "no Global Level on the page" }
Says "Запрет удаления у меня" 10
$closed = Get-Texts | Where-Object { $_ -match "^Открывается на уровне 7\. Ваш уровень — \d+\.$" } | Select-Object -First 1
if (-not $closed) { throw "level 7 does not say it is closed" }
"  $g; $closed"
Snap "161-B-levels"
"B's Questions (iOS MTQuestionsPage): a question opens its answer"
Click-Named "Назад"; Click-Named "Вопросы"
Click-Named "Что такое Глобальный уровень?"
Says "Ваш Глобальный уровень — наименьший из трёх уровней" 10
Snap "162-B-answer"
"done in $([int]((Get-Date) - $t0).TotalSeconds) s"
Use-Montana $A; Stop-Montana; Use-Montana $B; Stop-Montana
