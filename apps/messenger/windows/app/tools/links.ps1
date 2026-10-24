# A LINK'S CARD, LIVE (after tools\ab.ps1 with the same -Root): B types a link to Montana's code; its card -- read by B's machine
# from the page itself -- stands over the field («GitHub»), rides the letter, and stands under it at A's. The card's picture is a
# second read (iOS MTLinkCards.picture): it lands on B's own letter; a pair's envelope carries the words alone (iOS's envelope leg),
# a group's card word carries the picture -- B makes a group with A, sends the link there, and A's group card shows it.
# usage: tools\links.ps1 -Root DIR [-Shots DIR]
param([Parameter(Mandatory = $true)][string]$Root, [string]$Shots = "")
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ui.ps1"
function Snap($name) { if ($Shots) { Shot-Montana (Join-Path $Shots "$name.png") } }
function Says([string]$text, [int]$timeout = 60) { Find-Named $text $timeout | Out-Null; "  sees: $text" }
$t0 = Get-Date
$stamp = Get-Date -Format "HHmmss"
$words = "Код $stamp https://github.com/efir369999/montana_messenger"
$B = Start-Montana -DataDir "$Root\B"; Front-Montana -X 0 -Y 40 -Width 1500 -Height 950
Start-Sleep -Seconds 2
"B types a link"
Click-Named "Алиса Тест"
Type-Into "Сообщение..." $words
Says "GitHub" 20
Says "Отмена" 20   # the plate's own cross: the card over the field is this letter's, not an older letter's card in the feed
Snap "38-B-plate"
Click-Named "Отправить"
Sent-Settle   # the new letter itself left (an older letter of the feed may read «Отправлено» already)
Says "Картинка ссылки" 40
"  B: the picture caught up on B's own letter"
"B makes a group with A and sends the link into it"
$title = "Ссылки $stamp"
Click-Named "Написать"; Click-Named "Новая группа"
Click-Named "Выбрать: Алиса Тест"; Click-Named "Готово"
Type-Into "Название группы" $title; Click-Named "Готово"
Says "Вы создали группу «$title»" 15
Type-Into "Сообщение..." "Группа $stamp https://github.com/efir369999/montana_messenger"
Says "GitHub" 20
Says "Отмена" 20
Click-Named "Отправить"
Sent-Settle
$end = (Get-Date).AddSeconds(40)
do { $n = @(All-Named | Where-Object { try { $_.Current.Name -eq "Картинка ссылки" } catch { $false } }).Count; if ($n -ge 1) { break }; Start-Sleep -Milliseconds 500 } while ((Get-Date) -lt $end)
Start-Sleep -Seconds 4   # the group's card word leaves after the picture lands
Stop-Montana
"A sees the card under the letter"
$A = Start-Montana -DataDir "$Root\A"; Front-Montana -X 0 -Y 40 -Width 1500 -Height 950
Start-Sleep -Seconds 2
Click-Named "Борис Тест"
Says "Код $stamp" 90
$cards = @(Get-Texts | Where-Object { $_ -like "*montana_messenger*" -and $_ -notlike "http*" -and $_ -notlike "Код *" })
if (-not $cards) { throw "no card under the letter" }
"  sees the card: $($cards[0])"
Snap "39-A-card"
if (Get-Texts | Where-Object { $_ -eq "Картинка ссылки" }) { "  A: the pair's card came with a picture" } else { "  A: the pair's card came with its words alone (the envelope leg)" }
"A sees the picture on the group's card"
Click-Named "Чаты"; Click-Named $title
Says "Группа $stamp" 90
Says "Картинка ссылки" 90
Snap "40-A-group-card"
"done in $([int]((Get-Date) - $t0).TotalSeconds) s"
Stop-Montana
