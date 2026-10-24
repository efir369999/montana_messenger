# THE HOUSE'S MOVING PICTURES, IN THE WINDOWS (after tools\ab.ps1 with the same -Root): A opens the emoji panel's «GIF» -- the
# doors answer an empty word with what is popular; A picks the first picture, it leaves as a moving picture (a document named
# gif_…), and B gets it drawn as a GIF.
# usage: tools\gif.ps1 -Root DIR [-Shots DIR]
param([Parameter(Mandatory = $true)][string]$Root, [string]$Shots = "")
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ui.ps1"
function Snap($name) { if ($Shots) { Shot-Montana (Join-Path $Shots "$name.png") } }
function Says([string]$text, [int]$timeout = 60) { Find-Named $text $timeout | Out-Null; "  sees: $text" }
function Gifs { @(Get-Texts | Where-Object { $_ -eq "GIF" }).Count }
$t0 = Get-Date
$B = Start-Montana -DataDir "$Root\B"; Front-Montana -X 920 -Y 40 -Width 900 -Height 900
Start-Sleep -Seconds 2
$A = Start-Montana -DataDir "$Root\A"; Front-Montana -X 0 -Y 40 -Width 900 -Height 900
Start-Sleep -Seconds 2
"A picks a moving picture"
Click-Named "Борис Тест"
$before = Gifs
Click-Named "Эмодзи"; Click-Named "GIF"
Says "GIF 1" 30
Snap "86-A-gifs"
Click-Named "GIF 1"
Sent-Settle 60
$end = (Get-Date).AddSeconds(30)
while ((Get-Date) -lt $end -and (Gifs) -le $before) { Start-Sleep -Milliseconds 500 }
if ((Gifs) -le $before) { throw "A's letter is no GIF" }
"  A: the letter is a moving picture"
"B gets it as a GIF"
Use-Montana $B; Front-Montana
$seen = Gifs
Click-Named "Алиса Тест"
$end = (Get-Date).AddSeconds(90)
while ((Get-Date) -lt $end -and (Gifs) -le $seen) { Start-Sleep -Milliseconds 500 }
if ((Gifs) -le $seen) { throw "B never got the GIF" }
"  B: a GIF in the conversation"
Snap "87-B-gif"
"done in $([int]((Get-Date) - $t0).TotalSeconds) s"
Use-Montana $A; Stop-Montana; Use-Montana $B; Stop-Montana
