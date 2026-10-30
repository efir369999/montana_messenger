# MY CODE AND LINK, LIVE (after tools\ab.ps1 with the same -Root): «Написать» → «Мой код и ссылка» opens the screen of the
# code and the link over a list that is not empty (iOS MontanaQRFullView, the compose button's own screen), with its link.
# usage: tools\qr.ps1 -Root DIR [-Shots DIR]
param([Parameter(Mandatory = $true)][string]$Root, [string]$Shots = "")
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ui.ps1"
function Snap($name) { if ($Shots) { Shot-Montana (Join-Path $Shots "$name.png") } }
function Says([string]$text, [int]$timeout = 60) { Find-Named $text $timeout | Out-Null; "  sees: $text" }
$t0 = Get-Date
$A = Start-Montana -DataDir "$Root\A"; Front-Montana -X 0 -Y 40 -Width 1200 -Height 1000
Start-Sleep -Seconds 2
Says "Борис Тест" 15   # the list is not empty: the card of the empty list does not stand
Click-Named "Написать"; Click-Named "Мой код и ссылка"
Says "Скопировать ссылку" 10
$link = $null
for ($i = 0; $i -lt 20 -and -not $link; $i++) { $link = Get-Texts | Where-Object { $_ -like "https://montana.quest/*" } | Select-Object -First 1; Start-Sleep -Milliseconds 300 }
if (-not $link) { throw "the screen shows no link" }
"  the link: $($link.Substring(0, 30))…"
Snap "60-A-qr"
Click-Named "Закрыть"
Gone-Named "Скопировать ссылку" 10
"done in $([int]((Get-Date) - $t0).TotalSeconds) s"
Stop-Montana
