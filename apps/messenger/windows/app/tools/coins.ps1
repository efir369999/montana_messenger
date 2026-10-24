# THE TIME COIN IN THE WINDOWS (after tools\ab.ps1 with the same -Root), BY THE RULE OF iOS 2304 (fold-6, from the time cut of
# 23.10.2026 00:00 MSK): only the chain mints -- the book mints nothing, so in a check's own folder, where the chain on the nodes is
# not written (MONTANA_COIN_CHAIN), A's open wallet stands still; the Pantheon on Fire's taps light the game, and a burn unbroken
# for a minute rests a minute; A writes to B and the letter mints no coin on either side («Монеты из чатов» stand); with nothing
# held «Отправить» stands disabled (iOS .disabled(total <= 0)); the TimeChain page tells the Global Level and the person's seconds
# on the network. The chain's minting is checked by the live test wallet::tests (two
# throwaway keys).
# usage: tools\coins.ps1 -Root DIR [-Shots DIR]
param([Parameter(Mandatory = $true)][string]$Root, [string]$Shots = "")
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ui.ps1"
function Snap($name) { if ($Shots) { Shot-Montana (Join-Path $Shots "$name.png") } }
function Says([string]$text, [int]$timeout = 60) { Find-Named $text $timeout | Out-Null; "  sees: $text" }
function Available {
    $e = Find-Named "Доступно " 15
    [int](($e.Current.Name -replace '^Доступно ', '') -replace '[^\d]', '')
}
function Minted([string]$row) {
    $e = Find-Named "${row}: " 15
    [int](($e.Current.Name -replace "^${row}: ", '') -replace '[^\d]', '')
}
function Wallet { Open-Drawer; Click-Named "Монета Времени"; Says "Баланс Времени" 15 }
$stamp = Get-Date -Format "HHmmss"
$t0 = Get-Date
$B = Start-Montana -DataDir "$Root\B"; Front-Montana -X 300 -Y 40 -Width 1500 -Height 950
Start-Sleep -Seconds 2
$A = Start-Montana -DataDir "$Root\A"; Front-Montana -X 0 -Y 40 -Width 1500 -Height 950
Start-Sleep -Seconds 2

"A opens the wallet: the book mints nothing from the time cut, the Available of a check's folder stands"
Wallet
$a1 = Available
Start-Sleep -Seconds 5
$a2 = Available
if ($a2 -ne $a1) { throw "the book minted after the time cut ($a1 -> $a2)" }
"  the Available stands at $a2 for 5 s"
"the Pantheon on Fire: the taps light it; a burn unbroken for a minute rests a minute"
Click-Named "Монета"; Click-Named "Монета"
Says "из 60 секунд подряд" 5
Snap "111-A-wallet"
$end = (Get-Date).AddSeconds(80); $rested = $false
while ((Get-Date) -lt $end) {
    Click-Named "Монета"; Start-Sleep -Milliseconds 1500
    if ((Get-Texts) -match '^Пауза чеканки') { $rested = $true; break }
}
if (-not $rested) { throw "the burn never rested after its minute" }
"  sees: the minting rests after the burn's minute"
$beforeChats = Minted "Монеты из чатов"

"A writes to B: the letter mints no coin on either side (the book mints nothing from the time cut)"
Click-Named "Чаты"; Click-Named "Борис Тест"
Start-Sleep -Seconds 2
Type-Into "Сообщение..." "Монета за письмо $stamp"; Click-Named "Отправить"
Sent-Settle
Wallet
$afterChats = Minted "Монеты из чатов"
if ($afterChats -ne $beforeChats) { throw "A's letter minted in the book ($beforeChats -> $afterChats)" }
"  A: coins from chats stand at $afterChats"
Use-Montana $B; Front-Montana
$bChats = $null
Click-Named "Алиса Тест"
Says "Монета за письмо $stamp" 90
Wallet
$bChats = Minted "Монеты из чатов"
Click-Named "Чаты"; Wallet
if ((Minted "Монеты из чатов") -ne $bChats) { throw "B's received letter minted in the book" }
"  B: coins from chats stand at $bChats"

"A's transfer: weighed by what A holds -- with nothing, «Отправить» stands disabled (iOS .disabled(total <= 0))"
Use-Montana $A; Front-Montana
if ($a2 -le 0) {
    if ((Find-Named "Отправить" 10).Current.IsEnabled) { throw "«Отправить» stands enabled with nothing to send" }
    "  «Отправить» stands disabled: A holds nothing"
} else {
    # the send sheet as iOS draws it (MTCoinSendSheet): the chats in the chats tab's rows, a field and a pick beside each
    Click-Named "Отправить"
    Says "Выберите чаты" 10
    Says "Доступно" 5
    Type-Into "Сумма: Борис Тест" "5"
    Says "Итого" 5
    Snap "112-A-send"
    Click-Named "Отправить"
    if ($a2 -lt 5) { Says "Недостаточно монет" 15 } else { Says "Ждёт сети" 30 }
    Click-Named "Закрыть"
}
"A's TimeChain page (iOS MTTimeChainsPage): the Global Level and the person's seconds on the network by the nodes' clock; the"
"Pantheon's chain takes no link from the time cut -- its taps mint nothing in the book"
Click-Named "Чаты"; Wallet
Click-Named "TimeChain"
Says "Время в сети: " 30
$online = Get-Texts | Where-Object { $_ -match "^Время в сети: " } | Select-Object -First 1
$global = Get-Texts | Where-Object { $_ -match "^Глобальный уровень: \d+$" } | Select-Object -First 1
if (-not $online -or $online -match ": 0 с$") { throw "the person's seconds did not count: $online" }
if (-not $global) { throw "no Global Level on the page" }
"  $online; $global"
Snap "113-A-timechain"
Click-Named "Назад"
"done in $([int]((Get-Date) - $t0).TotalSeconds) s"
Use-Montana $A; Stop-Montana; Use-Montana $B; Stop-Montana
