# THE SEED'S COINS ON ANOTHER DEVICE OF THE WORDS, LIVE, BY THE RULE OF iOS 2304-2305 (fold-6, MTCoinSplit.beat): only the chain
# mints -- the coin key is the words' own, one chain on every device of them, and its node credits the key's seconds itself. A is
# born on a fresh folder: its key's chain opens with its GENESIS of 0, and A's wallet shows the chain's Available growing by the
# second. B opens the same words on a folder of its own: the same key, the same chain -- B's wallet shows no less than A's did. The
# words go from window to window inside this check alone -- never into a file, a log or a shot; the check lets the throwaway key's
# chain be written on the nodes (MONTANA_COIN_CHAIN=1).
# usage: tools\seedbook.ps1 -Root DIR [-Shots DIR]
param([Parameter(Mandatory = $true)][string]$Root, [string]$Shots = "")
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ui.ps1"
if (Test-Path $Root) { Remove-Item -Recurse -Force $Root }
function Snap($name) { if ($Shots) { Shot-Montana (Join-Path $Shots "$name.png") } }
function Says([string]$text, [int]$timeout = 60) { Find-Named $text $timeout | Out-Null; "  sees: $text" }
function Available {
    $e = Find-Named "Доступно " 15
    [int](($e.Current.Name -replace '^Доступно ', '') -replace '[^\d]', '')
}
function Wallet { Open-Drawer; Click-Named "Монета Времени"; Says "Баланс Времени" 15 }
# the last line of a person's trace that matches, waited for
function Traced([string]$who, [string]$pattern, [int]$timeout = 120) {
    $end = (Get-Date).AddSeconds($timeout)
    do {
        $hit = Get-Content "$Root\$who\trace.log" -Encoding UTF8 -ErrorAction SilentlyContinue | Where-Object { $_ -match $pattern } | Select-Object -Last 1
        if ($hit) { "  ${who}: $($hit -replace '^\d+ ', '')" | Out-Host; return $hit }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $end)
    throw "$who never traced '$pattern'"
}
$env:MONTANA_TRACE = "1"
$env:MONTANA_COIN_CHAIN = "1"
$t0 = Get-Date

"A: a new identity; its words are read off the grid for B"
$A = Start-Montana -DataDir "$Root\A"; Front-Montana -X 0 -Y 40 -Width 900 -Height 900
Click-Named "Продолжить с Montana"; Click-Named "Создать"; Click-Named "Готово"
Click-Named "Я понимаю и беру ответственность на себя"; Click-Named "Показать слова"
Find-Named "Ваша сид-фраза из 24 слов" | Out-Null; Start-Sleep -Milliseconds 500
# the grid's cells as the tree reads them: the number, its dot, the word
$words = New-Object string[] 24
$n = $null
foreach ($e in (All-Named)) {
    $s = $e.Current.Name
    if ($s -match '^(\d{1,2})\.?$' -and [int]$Matches[1] -ge 1 -and [int]$Matches[1] -le 24) { $n = [int]$Matches[1]; continue }
    if ($s -eq ".") { continue }
    if ($n -and $s -match '^[a-z]{3,8}$') { $words[$n - 1] = $s }
    $n = $null
}
if (@($words | Where-Object { $_ }).Count -ne 24) { throw "the grid gave $(@($words | Where-Object { $_ }).Count) of 24 words" }
"  the grid gave 24 words (kept in this check's memory only)"
Click-Named "Я записал слова в надёжном месте"; Click-Named "Ваша личность в Montana"
Find-Named "Готово" | Out-Null; Start-Sleep -Milliseconds 500
Type-First-Field "Алиса Тест"; Click-Named "Готово"; Click-Named "Принимаю"
Traced "A" "coin_v3 genesis code=200" 120 | Out-Null   # the key's chain opens with its GENESIS of 0

"A opens its wallet: the chain credits the key's seconds, the Available grows by the second"
Wallet
$end = (Get-Date).AddSeconds(90); $a1 = Available
do { Start-Sleep -Seconds 3; $a2 = Available } while ($a2 -le $a1 -and (Get-Date) -lt $end)
if ($a2 -le $a1) { throw "A's chain shows no seconds ($a1 -> $a2)" }
$x = $a2
"  A's Available $a1 -> $a2"
Snap "121-A-wallet"
Click-Named "Чаты"

"B: the same words on a folder of its own"
$B = Start-Montana -DataDir "$Root\B"; Front-Montana -X 920 -Y 40 -Width 900 -Height 900
Click-Named "Продолжить с Montana"; Click-Named "Открыть личность"
# the page of the words stands a moment after the press: its field is asked again until it is there
$end = (Get-Date).AddSeconds(15)
while ($true) { try { Type-First-Field ($words -join " "); break } catch { if ((Get-Date) -gt $end) { throw }; Start-Sleep -Milliseconds 300 } }
$words = $null
Click-Named "Восстановить"
$end = (Get-Date).AddSeconds(60)
do { $tx = Get-Texts; if ($tx -contains "Принимаю") { Click-Named "Принимаю"; break }; if ($tx -contains "Чаты") { break }; Start-Sleep -Milliseconds 500 } while ((Get-Date) -lt $end)
"B opens its wallet: the same key's chain -- no less than A's"
Wallet
$end = (Get-Date).AddSeconds(90)
do { $seenB = Available; if ($seenB -ge $x) { break }; Start-Sleep -Seconds 3 } while ((Get-Date) -lt $end)
"  B's Available $seenB"
Snap "122-B-wallet"
if ($seenB -lt $x) { throw "B shows $seenB, below A's $x" }
"done in $([int]((Get-Date) - $t0).TotalSeconds) s"
Use-Montana $A; Stop-Montana; Use-Montana $B; Stop-Montana
