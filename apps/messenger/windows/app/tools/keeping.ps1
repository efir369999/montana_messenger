# THE COPY KEPT BY A CORRESPONDENT, IN THE WINDOWS (after tools\ab.ps1 with the same -Root): A turns «Хранить мою копию у
# собеседников» on in Data and Storage -- «Спрашиваю ваших собеседников…»; B, keeping parts for its contacts by default, says yes,
# takes the sixteen parts of A's sealed copy from the nodes and says «held» for each -- A shows «Хранят 1 из 1», and B lists
# «Алиса Тест» with the size of what it keeps; B lets the part go and A turns the keeping off. The ten minutes a renewal waits
# for more keepers are five seconds here (MONTANA_KEEP_WAIT, a check's own).
# usage: tools\keeping.ps1 -Root DIR [-Shots DIR]
param([Parameter(Mandatory = $true)][string]$Root, [string]$Shots = "")
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ui.ps1"
function Snap($name) { if ($Shots) { Shot-Montana (Join-Path $Shots "$name.png") } }
function Says([string]$text, [int]$timeout = 60) { Find-Named $text $timeout | Out-Null; "  sees: $text" }
function Data-Page { Open-Drawer; Click-Named "Настройки"; Click-Named "Данные и память"; Says "КОПИЯ У СОБЕСЕДНИКОВ" 10 }
$env:MONTANA_KEEP_WAIT = "5"
$env:MONTANA_TRACE = "1"
$t0 = Get-Date
$B = Start-Montana -DataDir "$Root\B"; Front-Montana -X 920 -Y 40 -Width 900 -Height 900
Start-Sleep -Seconds 2
$A = Start-Montana -DataDir "$Root\A"; Front-Montana -X 0 -Y 40 -Width 900 -Height 900
Start-Sleep -Seconds 2
"A keeps its copy with its contacts"
Data-Page
Click-Named "Хранить мою копию у собеседников"
Says "Спрашиваю ваших собеседников…" 20
Snap "80-A-asking"
"B says yes and takes the parts; A sees them held"
Says "Хранят 1 из 1" 240
Snap "81-A-kept"
Use-Montana $B; Front-Montana
Data-Page
Says "Больше не хранить эту часть: Алиса Тест" 30
$size = Get-Texts | Where-Object { $_ -match "^\d+(,\d+)? (байт|байта|кБ|МБ|ГБ)$" } | Select-Object -First 1   # as iOS says a size (mtSize)
if (-not $size) { throw "B shows no size of what it keeps" }
"  B keeps A's parts: $size"
Snap "82-B-keeps"
"B lets the part go; A turns the keeping off"
Click-Named "Больше не хранить эту часть: Алиса Тест"
Gone-Named "Больше не хранить эту часть: Алиса Тест" 15
Use-Montana $A; Front-Montana
Click-Named "Хранить мою копию у собеседников"
Gone-Named "Хранят 1 из 1" 15
"done in $([int]((Get-Date) - $t0).TotalSeconds) s"
Use-Montana $A; Stop-Montana; Use-Montana $B; Stop-Montana
