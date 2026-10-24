# THE AUTO MINTING BY THE PULL AND THE NINE SECONDS (iOS MTWalletPull, MTCoinTapPad.armNine, MTWalletScreen.pulled; after
# tools\ab.ps1 with the same -Root): A's wallet opens with the auto minting on; taps light the Pantheon, and the page opened again
# while it burns does not turn it on by itself; the coin held nine seconds turns the auto minting on, the Pantheon burning or not;
# once more opened while it burns, the page drawn down at its top past the trigger turns it on once the fire is out. The hand is the
# mouse itself (as tools\rows.ps1): the check moves the pointer to the coin and holds its button there. The auto minting is the
# book's, and from the time cut of 23.10.2026 the book mints nothing (iOS 2304, fold-6): the diary says each turn on, and the
# Available of a check's folder, where no chain is written, stands.
# usage: tools\coinhold.ps1 -Root DIR [-Shots DIR]
param([Parameter(Mandatory = $true)][string]$Root, [string]$Shots = "")
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ui.ps1"
function Snap($name) { if ($Shots) { Shot-Montana (Join-Path $Shots "$name.png") } }
function Says([string]$text, [int]$timeout = 60) { Find-Named $text $timeout | Out-Null; "  sees: $text" }
function Available {
    $e = Find-Named "Доступно " 15
    [int](($e.Current.Name -replace '^Доступно ', '') -replace '[^\d]', '')
}
function Lines([string]$line) { @(Get-Content "$Root\A\trace.log" -Encoding UTF8 -ErrorAction SilentlyContinue | Where-Object { $_ -like "*$line*" }).Count }
function Wrote-Again([string]$line, [int]$before, [int]$timeout = 20) {
    $end = (Get-Date).AddSeconds($timeout)
    do { if ((Lines $line) -gt $before) { "  A: $line"; return }; Start-Sleep -Milliseconds 300 } while ((Get-Date) -lt $end)
    throw "A never wrote '$line' again"
}
function Wallet { Open-Drawer; Click-Named "Монета Времени"; Says "Баланс Времени" 15 }
# the page opened again while the Pantheon burns: taps light it, the wallet is left and opened at once
function Reopen-Burning {
    Front-Montana   # the window in front first: a return to it (iOS scenePhase .active) fires the auto minting by itself
    for ($i = 0; $i -lt 3; $i++) { Click-Named "Монета" }
    Click-Named "Чаты"
    $on = Lines "wallet_pull auto on"
    Wallet
    Start-Sleep -Seconds 1
    if ((Lines "wallet_pull auto on") -gt $on) { throw "the page opened while the Pantheon burns turned the auto minting on" }
    "  the page opened while the Pantheon burns: no auto minting"
}
# the coin's middle on the screen
function Coin-Point { $r = (Find-Named "Монета" 15).Current.BoundingRectangle; @([int]($r.X + $r.Width / 2), [int]($r.Y + $r.Height / 2)) }
$env:MONTANA_TRACE = "1"
Remove-Item "$Root\A\trace.log" -ErrorAction SilentlyContinue
$t0 = Get-Date
$A = Start-Montana -DataDir "$Root\A"; Front-Montana -X 0 -Y 40 -Width 900 -Height 950

"A opens the wallet: the auto minting is on"
$on = Lines "wallet_pull auto on why=page"
Wallet
Wrote-Again "wallet_pull auto on why=page" $on

"A's taps light the Pantheon; the wallet opened again while it burns stands still once the fire is out"
Reopen-Burning
Start-Sleep -Seconds 4   # three seconds of quiet put the fire out
$a1 = Available; Start-Sleep -Seconds 4; $a2 = Available
if ($a2 -ne $a1) { throw "the page minted with no auto minting ($a1 -> $a2)" }
"  the Available stands at $a1"

"A holds the coin nine seconds: the auto minting turns on"
$p = Coin-Point
[MontanaMouse]::SetCursorPos($p[0], $p[1]) | Out-Null; Start-Sleep -Milliseconds 200
$held = Lines "wallet_pull auto on why=hold"
[MontanaMouse]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
try { Wrote-Again "wallet_pull auto on why=hold" $held 14 } finally { [MontanaMouse]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero) }
Start-Sleep -Seconds 4   # the fire the hold kept goes out three seconds after the lift
# the auto minting is the book's, and from the time cut the book mints nothing (iOS 2304, fold-6): the hold turns it on (the diary
# says so above), and the Available of a check's folder, where no chain is written, stands
$a3 = Available; Start-Sleep -Seconds 4; $a4 = Available
if ($a4 -ne $a3) { throw "the book minted after the time cut ($a3 -> $a4)" }
"  the Available stands at $a4"
Snap "131-A-held"

"A opens the wallet again while it burns, then draws the page down past its trigger"
Reopen-Burning
Start-Sleep -Seconds 4
$pulled = Lines "wallet_pull auto on why=pull"
$p = Coin-Point   # the wheel over the page's top, where the coin stands in sight
[MontanaMouse]::SetCursorPos($p[0], $p[1]) | Out-Null; Start-Sleep -Milliseconds 200
for ($i = 0; $i -lt 4; $i++) { [MontanaMouse]::mouse_event(0x0800, 0, 0, 120, [UIntPtr]::Zero); Start-Sleep -Milliseconds 40 }
Wrote-Again "wallet_pull auto on why=pull" $pulled 10
$a5 = Available; Start-Sleep -Seconds 4; $a6 = Available
if ($a6 -ne $a5) { throw "the book minted after the time cut ($a5 -> $a6)" }
"  the Available stands at $a6 (the book mints nothing from the time cut)"

"A leaves the wallet: the auto minting stops with the page"
$off = Lines "wallet_pull auto off why=page"
Click-Named "Чаты"
Wrote-Again "wallet_pull auto off why=page" $off
"done in $([int]((Get-Date) - $t0).TotalSeconds) s"
Stop-Montana
