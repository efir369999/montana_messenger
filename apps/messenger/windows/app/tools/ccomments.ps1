# A CHANNEL'S COMMENTS, LIVE (after tools\channel.ps1 with the same -Root): A, the owner, turns «Разрешить комментарии» on;
# B leaves a comment under the post in its thread; A's machine, on all the while, shows «Комментарии: 1» under the post.
# Then A takes 👍 out of the channel's «Реакции», and B's menu of the post offers the channel's list (😀 stands in it).
# usage: tools\ccomments.ps1 -Root DIR [-Shots DIR]
param([Parameter(Mandatory = $true)][string]$Root, [string]$Shots = "")
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ui.ps1"
function Snap($name) { if ($Shots) { Shot-Montana (Join-Path $Shots "$name.png") } }
function Says([string]$text, [int]$timeout = 60) { Find-Named $text $timeout | Out-Null; "  sees: $text" }
$t0 = Get-Date
$A = Start-Montana -DataDir "$Root\A"; Front-Montana -X 0 -Y 40 -Width 700 -Height 950
Start-Sleep -Seconds 2
$title = $null
for ($i = 0; $i -lt 40 -and -not $title; $i++) { $title = Get-Texts | Where-Object { $_ -like "Канал *" } | Select-Object -First 1; Start-Sleep -Milliseconds 300 }
if (-not $title) { throw "no channel in A's list" }
"A lets the subscribers of «$title» talk"
Click-Named $title; Start-Sleep -Seconds 1; Click-Named $title
Click-Named "Разрешить комментарии"
Click-Named "Назад"
Start-Sleep -Seconds 1
"B comments the post"
$B = Start-Montana -DataDir "$Root\B"; Front-Montana -X 720 -Y 40 -Width 1100 -Height 950
Start-Sleep -Seconds 2
Click-Named $title
Click-Named "Оставить комментарий" 90
Says "Здесь пока нет комментариев" 10
Type-Into "Комментарий" "Хороший пост с Windows"
Click-Named "Отправить"
Says "Хороший пост с Windows" 15
Snap "47-B-comment"
"A sees it counted"
Use-Montana $A; Front-Montana
try { Click-Named "Назад" 3 } catch {}   # back to the list, if a page stands
Start-Sleep -Seconds 1
Click-Named $title
Says "Комментарии: 1" 90
Snap "48-A-comments"
"A takes 👍 out of the channel's reactions"
Click-Named $title   # narrow: the conversation's title opens the channel's page
Click-Named "Реакции"
Says "ДОСТУПНЫЕ РЕАКЦИИ" 10
Click-Named "👍"
Click-Named "Назад"   # narrow: the conversation's own back goes to the list, and the pages go with their choice
"B's menu offers the list"
Use-Montana $B; Front-Montana
Click-Named "Закрыть"   # the thread
$post = $null
for ($i = 0; $i -lt 40 -and -not $post; $i++) { $post = Get-Texts | Where-Object { $_ -like "Пост канала *" } | Select-Object -First 1; Start-Sleep -Milliseconds 300 }
if (-not $post) { throw "no post in B's feed" }
$listed = $false
for ($i = 0; $i -lt 12 -and -not $listed; $i++) {
    RightClick-Named $post   # the menu opens (or a menu that stood closes)
    try { Find-Named "😀" 3 | Out-Null; $listed = $true } catch { RightClick-Named $post; Start-Sleep -Seconds 4 }
}
if (-not $listed) { throw "B's menu never offered the channel's list" }
"  sees: 😀 in the menu's strip"
Snap "49-B-reactions"
"done in $([int]((Get-Date) - $t0).TotalSeconds) s"
Use-Montana $B; Stop-Montana; Use-Montana $A; Stop-Montana
