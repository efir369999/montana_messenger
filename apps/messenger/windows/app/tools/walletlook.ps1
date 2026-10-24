# THE TIME COIN'S PAGE AS iOS LAYS IT (MTWalletPage, MTSecondPrice, MTHourWorth, MTPiLevelsSheet, MTCoinAnalyticsPage, MTCoinRules;
# after tools\ab.ps1 with the same -Root): A opens the wallet -- the auto minting turns the coin (iOS's own CoinFace/CoinBack), no
# app mints over it (the book mints nothing from the time cut), the bar to the next level of π under it, the price of a second; A
# tells her hour (1000 an hour):
# her rate and her balance in her currency stand; the levels of π, the analytics and the rules of Top up open; the rate is taken
# back at the end. Each state is shot from the window's own pixels for the comparison with iOS.
# usage: tools\walletlook.ps1 -Root DIR [-Shots DIR]
param([Parameter(Mandatory = $true)][string]$Root, [string]$Shots = "")
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ui.ps1"
function Snap($name) { if ($Shots) { Shot-Montana (Join-Path $Shots "$name.png") } }
function Says([string]$text, [int]$timeout = 30) { Find-Named $text $timeout | Out-Null; "  sees: $text" }
$env:MONTANA_TRACE = "1"
$t0 = Get-Date
$A = Start-Montana -DataDir "$Root\A"; Front-Montana -X 0 -Y 40 -Width 600 -Height 1000
"A opens the wallet: the coin turns, nothing mints over it, the price of a second under it"
Open-Drawer; Click-Named "Монета Времени"
Says "Пантеон в Огне"
Says "1 секунда = 1 Монета"
Says "Сколько стоит Ваш час Сейчас?"
# the apps that mint stand over the coin while their coins are born (iOS MTCoinFlash); from the time cut the book mints nothing
# (iOS 2304, fold-6), so in a check's folder, where no chain is written, nothing stands there
if (Get-Texts | Where-Object { $_ -like "Чеканка *" }) { throw "a minting stands over the coin, though the book mints nothing from the time cut" }
"  nothing mints over the coin: the book mints nothing from the time cut"
Start-Sleep -Seconds 2
Snap "200-A-wallet-head"
"A tells her hour: her rate and her balance in her currency"
Click-Named "Сколько стоит Ваш час Сейчас?"
Says "Сколько вы зарабатываете?"
Click-Named "Час"
Type-Into "В час" "1000"
Says "1 монета" 10
Snap "201-A-hour"
Click-Named "Закрыть"   # the hour is a sheet: its close at the left, its check at the right (iOS MTHourWorth)
Says "Ваш курс: 1 монета =" 15
Says "Ваш час:" 10
"The levels of π, the analytics, the rules of Top up"
Click-Named "Уровни"
Says "π 3" 10
Snap "202-A-pi-levels"
Click-Named "Закрыть"   # the levels of π are a sheet (iOS MTPiLevelsSheet)
Click-Named "Аналитика"
Says "Все месяцы" 10
Says "Доходы" 10
Snap "203-A-analytics"
Click-Named "Назад"
Click-Named "История"
Says "Операции" 10   # a day's minting (iOS «Чеканка за сутки») stands only where the book minted: none from the time cut
Snap "205-A-history"
Click-Named "Назад"
# with nothing held the Send stands disabled (iOS .disabled(total <= 0)); with coins its sheet and the levelling of the top
if (-not (Find-Named "Отправить" 10).Current.IsEnabled) {
    "  «Отправить» stands disabled: A holds nothing"
} else {
    Click-Named "Отправить"
    Says "Выберите чаты" 10
    Click-Named "Выровнять топ 13"
    $q = $null; $end = (Get-Date).AddSeconds(10)
    do { $q = @(Get-Texts | Where-Object { $_ -eq "Выровнять топ 13?" -or $_ -eq "Некого выравнивать" }) | Select-Object -First 1; if (-not $q) { Start-Sleep -Milliseconds 300 } } while (-not $q -and (Get-Date) -lt $end)
    if (-not $q) { throw "the levelling asked nothing" }
    "  the levelling asks: $q"
    Snap "206-A-send-level"
    if ($q -eq "Некого выравнивать") { Click-Named "ОК" } else { Click-Named "Отмена" }
    Snap "207-A-send"
    Click-Named "Закрыть"
}
Click-Named "Пополнить"
# ONE COIN, ONE SECOND -- ALL THE TOP UP SAYS (iOS MTCoinRules, the author's word 21.10.2026): the old rules are gone
Says "1 монета — 1 секунда" 10
Says "Живи здесь и сейчас" 10
if (Get-Texts | Where-Object { $_ -like "*О деньгах*" -or $_ -like "*Ваш курс чеканки*" }) { throw "the old rules stand on Top up" }
Snap "204-A-topup"
# ESC TAKES THE TOPMOST LAYER AWAY (the iOS edge stroke's Windows road): the sheet leaves, the wallet stands
Front-Montana
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.SendKeys]::SendWait("{ESC}")
Gone-Named "Живи здесь и сейчас" 5
Says "Баланс Времени" 5
"  Esc closed the sheet alone"
"The TimeChain page: the Explorer and the sections as iOS lays them; a line of the history opens its own card"
Click-Named "TimeChain"
Says "Глобальный уровень" 15
Says "Эксплорер" 10
Says "Для наблюдателя" 10
Snap "208-A-timechain"
Click-Named "Назад"
Click-Named "История"
$line = @(Get-Texts | Where-Object { $_ -match "^.+: [+−-]?[\d,]+$" }) | Select-Object -First 1
if ($line) {
    Click-Named $line
    $card = $null; $end = (Get-Date).AddSeconds(8)
    do { $card = @(Get-Texts | Where-Object { $_ -eq "Операция" -or $_ -eq "Транзакция" }) | Select-Object -First 1; if (-not $card) { Start-Sleep -Milliseconds 300 } } while (-not $card -and (Get-Date) -lt $end)
    if (-not $card) { throw "a line of the history opened nothing" }
    "  the line opens: $card"
    Snap "209-A-operation"
    Click-Named "Назад"
} else { "  no line in the history (nothing minted from the time cut)" }
Click-Named "Назад"
"The rate is taken back"
Click-Named "Ваш час:"
Type-Into "В час" ""
Click-Named "Готово"
Start-Sleep -Seconds 1
if (@(Get-Texts | Where-Object { $_ -like "Ваш курс:*" }).Count) { throw "the rate stood after it was taken back" }
"  no rate stands"
"done in $([int]((Get-Date) - $t0).TotalSeconds) s"
Stop-Montana
