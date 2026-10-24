# TO ONESELF ON ANOTHER ACCOUNT OF THIS COMPUTER, LIVE (iOS «My other accounts», MTSeats.pairWithShelf, MTCoinTx.knowOwn/landOwn):
# Anna is made and mints in her wallet, her chain opened on the nodes; the plus makes Vera beside her; Anna is seated again and
# sends five coins to «My other accounts: Vera» -- the sheet asks first whether to link the two accounts forever.
# The two persons meet by Vera's card on this computer with no node, the SEND names Vera's key, Vera's RECV is laid at once with her
# own key and the move goes into her book on the nodes; Vera's own process on the shelf takes the pipe; Vera seated finds the five
# coins received and Anna's letter. The check asks the nodes to keep the chains of these throwaway persons (MONTANA_COIN_CHAIN=1).
# usage: tools\seatsend.ps1 -Root DIR [-Shots DIR]
param([Parameter(Mandatory = $true)][string]$Root, [string]$Shots = "")
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ui.ps1"
function Snap($name) { if ($Shots) { Shot-Montana (Join-Path $Shots "$name.png") } }
function Says([string]$text, [int]$timeout = 60) { Find-Named $text $timeout | Out-Null; "  sees: $text" }
$dir = Join-Path $Root "T"
if (Test-Path $dir) { Remove-Item -Recurse -Force $dir }
function Place { Front-Montana -X 0 -Y 40 -Width 1500 -Height 950 }
function Make([string]$name, [switch]$Door) {
    if ($Door) { Click-Named "Продолжить с Montana" }
    Click-Named "Создать"; Click-Named "Готово"
    Click-Named "Я понимаю и беру ответственность на себя"; Click-Named "Показать слова"
    Click-Named "Я записал слова в надёжном месте"; Click-Named "Ваша личность в Montana"
    Find-Named "Готово" | Out-Null; Start-Sleep -Milliseconds 500
    Type-First-Field $name; Click-Named "Готово"; Click-Named "Принимаю"
}
function Drawer { Open-Drawer; Start-Sleep -Milliseconds 600 }
function Seat-Of([string]$name) { Click-Named "Звонки"; Drawer; Click-Named $name; Follow-Montana $dir | Out-Null; Place }
function Wallet { Open-Drawer; Click-Named "Монета Времени"; Says "Баланс Времени" 15 }
function Minted([string]$row) { $e = Find-Named "${row}: " 15; [int](($e.Current.Name -replace "^${row}: ", '') -replace '[^\d]', '') }
# the last line of a trace that matches, waited for: the folder's own (Anna's is the base, Vera's under Seats)
function Traced([string]$folder, [string]$pattern, [int]$timeout = 60) {
    $end = (Get-Date).AddSeconds($timeout)
    do {
        $hit = Get-Content (Join-Path $folder "trace.log") -Encoding UTF8 -ErrorAction SilentlyContinue | Where-Object { $_ -match $pattern } | Select-Object -Last 1
        if ($hit) { "  $(Split-Path $folder -Leaf): $($hit -replace '^\d+ ', '')" | Out-Host; return $hit }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $end)
    throw "never traced '$pattern' in $folder"
}
$env:MONTANA_TRACE = "1"
$env:MONTANA_COIN_CHAIN = "1"
$t0 = Get-Date

"Anna: the first person of this computer; her wallet mints while it stands open"
Start-Montana -DataDir $dir | Out-Null; Place
Make "Анна Тест" -Door
Wallet
Traced $dir "coin_v3 genesis code=200" 90 | Out-Null
Start-Sleep -Seconds 20

"the plus at the drawer's head: Vera is made beside her"
Drawer; Click-Named "Выберите способ входа"
Follow-Montana $dir | Out-Null; Place
Make "Вера Тест"
Says "Скопировать ссылку" | Out-Null
$vera = @(Get-ChildItem (Join-Path $dir "Seats") -Directory)[0].FullName

"Anna seated again: five of her coins go to «My other accounts: Vera» (her chain holds them: the node counts her key's seconds)"
Seat-Of "Анна Тест"
Wallet
# her coins are her chain's once it speaks in this run (iOS MTWalletScreen.total, fold-7): «Отправить» stands disabled until then
$end = (Get-Date).AddSeconds(120)
while (-not (Find-Named "Отправить" 10).Current.IsEnabled) {
    if ((Get-Date) -gt $end) { throw "«Отправить» never stood enabled: Anna's chain did not speak" }
    Start-Sleep -Seconds 3
}
Click-Named "Отправить"
Says "Мои другие аккаунты" 15
Type-Into "Сумма: Вера Тест" "5"
Snap "141-A-send-own"
Click-Named "Отправить"
Says "Связать ваши аккаунты навсегда?" 10
Snap "142-A-link"
Click-Named "Отправить и связать"
Traced $dir "seat_pair seat=\w+ conv=" 60 | Out-Null
# her RECV laid at once (code=200, the move in her book on the nodes) -- or, a node out of reach, left hers to take when seated
Traced $dir "coin_own seat=\w+ coins=5 " 120 | Out-Null
Traced $vera "shelf_met pipes=1" 30 | Out-Null
Says "Вера Тест" 30   # the chat with the other account opens after
Snap "143-A-chat"

"Vera seated: the five coins stand received in her book"
Seat-Of "Вера Тест"
# her book takes the move from the nodes at her start (the vault Anna's step laid it in), or her own chain's walk credits it
Traced $vera "coin_book joined moves=[1-9]|coin_v3 recv code=\d+ word=[\w ]* taken=true" 240 | Out-Null
Wallet
$got = Minted "Монеты получены"
if ($got -lt 5) { throw "Vera shows $got coins received" }
"  Vera: coins received $got"
Snap "144-V-wallet"
"done in $([int]((Get-Date) - $t0).TotalSeconds) s"
Stop-Montana
