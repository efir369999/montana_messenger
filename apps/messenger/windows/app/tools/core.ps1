# THE PROTOCOL CORE, LIVE (iOS MTNetworkNode, MTWalletCore; after tools\ab.ps1 with the same -Root): A opens the TimeChain page;
# the node of the core (montana_core.dll, core/Montana-Core unchanged) is opened once in A's folder «Core» and every machine of the
# genesis is reached by the lines iOS 2251 carries; the observer's rows say how many answered and what the core says of the
# wallet -- the person is not opened in the core, so «Ядро ещё не открыло ваш кошелёк.», as on the telephone. A post's TimeChain
# page says the same under «Участие».
# usage: tools\core.ps1 -Root DIR [-Shots DIR]
param([Parameter(Mandatory = $true)][string]$Root, [string]$Shots = "")
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ui.ps1"
function Snap($name) { if ($Shots) { Shot-Montana (Join-Path $Shots "$name.png") } }
function Says([string]$text, [int]$timeout = 60) { Find-Named $text $timeout | Out-Null; "  sees: $text" }
function Wrote([string]$who, [string]$line, [int]$timeout = 60) {
    $end = (Get-Date).AddSeconds($timeout)
    do { $hit = Get-Content "$Root\$who\trace.log" -Encoding UTF8 -ErrorAction SilentlyContinue | Where-Object { $_ -like "*$line*" } | Select-Object -Last 1; if ($hit) { "  ${who}: $($hit -replace '^\d+ ', '')"; return }; Start-Sleep -Milliseconds 500 } while ((Get-Date) -lt $end)
    throw "$who never wrote '$line'"
}
$env:MONTANA_TRACE = "1"
Remove-Item "$Root\A\trace.log" -ErrorAction SilentlyContinue
$t0 = Get-Date
$A = Start-Montana -DataDir "$Root\A"; Front-Montana -X 0 -Y 40 -Width 1100 -Height 950
"A opens the TimeChain page: the node of the core opens and reaches the genesis"
Open-Drawer; Click-Named "Монета Времени"; Says "Баланс Времени" 15; Click-Named "TimeChain"
Says "Машины генезиса на связи" 20
Says "Ядро ещё не открыло ваш кошелёк." 30
$open = Get-Content "$Root\A\trace.log" -Encoding UTF8 -ErrorAction SilentlyContinue | Where-Object { $_ -like "*core_node open*" } | Select-Object -Last 1
"  A: $(if ($open) { $open -replace '^\d+ ', '' } else { 'the node stood already (opened in an earlier run)' })"
if ($open -and $open -notlike "*rc=0*") { throw "the node of the core did not open: $open" }
if (-not (Test-Path "$Root\A\Core")) { throw "no folder of the core's machine" }
Wrote "A" "core_node reach 2" 180   # the genesis holds three machines (iOS 2304, П11): the last asked is the third
$reach = @(Get-Content "$Root\A\trace.log" -Encoding UTF8 | Where-Object { $_ -like "*core_node reach*" })
$reach | ForEach-Object { "  A: $($_ -replace '^\d+ ', '')" }
$held = @($reach | Where-Object { $_ -like "*rc=0*" }).Count
Says "Машины генезиса на связи: $held / 3" 15
Snap "190-A-core"
"A's wallet: the Top 13 (iOS MTCoinTop13) -- the nodes' table when a node keeps it, else A among the pairs who told their balance"
Click-Named "Назад"
# the Top 13 stands open on the wallet's page (iOS walletPage: the section open by default); a press would fold it
Start-Sleep -Seconds 1
if (-not (Get-Texts | Where-Object { $_ -match '^\d+\. ' })) { Click-Named "Топ 13" }
# the state before a node answers lasts only until the nodes' table comes -- on a quick network it is never seen
try { Says ". Алиса Тест:" 8; "  before a node answers: A among the pairs who told their balance" } catch { "  the nodes' table came before the pairs' one could be seen" }
# the wallet standing open reads the one table of the nodes (iOS MTTopNet.read, every three seconds)
Wrote "A" "top_get rows=" 90
Says "1. " 20
"  the nodes' table stands: its first row in place 1"
Snap "191-A-top13"
Click-Named "TimeChain"
Says "Показывают свои монеты" 20
Says "Показано монет" 10
Click-Named "Назад"
"done in $([int]((Get-Date) - $t0).TotalSeconds) s"
Stop-Montana
