# THE P2P WALL IN THE WINDOW (iOS NetworkTabView's P2P tab; after tools\ab.ps1 with the same -Root): A opens «П2П стена» -- the
# count of the nodes this computer reaches, each machine of the network with its doors under it, every door asked now: open with
# its time, spare, lost, or no answer. The check reads what the network itself answers at the moment it runs, so it asks only that
# one node at least is held and that every door stands with a word.
# usage: tools\p2p.ps1 -Root DIR [-Shots DIR]
param([Parameter(Mandatory = $true)][string]$Root, [string]$Shots = "")
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ui.ps1"
function Snap($name) { if ($Shots) { Shot-Montana (Join-Path $Shots "$name.png") } }
function Says([string]$text, [int]$timeout = 30) { Find-Named $text $timeout | Out-Null; "  sees: $text" }
$t0 = Get-Date
$A = Start-Montana -DataDir "$Root\A"; Front-Montana -X 0 -Y 40 -Width 1500 -Height 950
Start-Sleep -Seconds 2
"A opens the P2P wall"
Open-Drawer; Click-Named "П2П стена"
Says "ДОСТИЖИМЫЕ УЗЛЫ" 15   # the section head stands in capitals
$end = (Get-Date).AddSeconds(30)
do { $rows = @(Get-Texts | Where-Object { $_ -match "^узел .+: (на связи|потерян)$" }); if ($rows.Count) { break }; Start-Sleep -Milliseconds 500 } while ((Get-Date) -lt $end)
if (-not $rows.Count) { throw "no node stands on the wall" }
foreach ($r in $rows) { "  $r" }
$doors = @(Get-Texts | Where-Object { $_ -match "^[a-z0-9.-]+\.[a-z]+: (открыт|запасной|потерян|нет ответа)" })
if (-not $doors.Count) { throw "no door stands under the nodes" }
foreach ($d in $doors) { "    $d" }
if (-not ($rows | Where-Object { $_ -like "*: на связи" })) { throw "not one node is held" }
if (-not ($doors | Where-Object { $_ -match ": открыт · \d+ ms$" })) { throw "no open door with its time" }
Snap "119-A-p2p"
"done in $([int]((Get-Date) - $t0).TotalSeconds) s"
Stop-Montana
