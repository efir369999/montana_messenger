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
# THE QUICK WAY BACK INTO THE WALLET: each name asked of the window alone (one question, not a reading of every element) and pressed the
# moment it stands -- the wallet's cross, then the panel's first slot once the page is gone (its right button opens the drawer while a
# hint stands there, as Open-Drawer does), the drawer's «Монета Времени», the page's «Баланс Времени». The way through Click-Named «Чаты»
# and Open-Drawer read the whole window a dozen times and brought the page back 3.4-3.5 s after the last tap (a triage of 25.10.2026),
# past the fire's three seconds.
function Quick([string]$Name, [double]$Timeout = 5) {
    $c = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty, $Name)
    $end = (Get-Date).AddSeconds($Timeout)
    do { try { $e = (Root).FindFirst([System.Windows.Automation.TreeScope]::Descendants, $c); if ($e) { return $e } } catch {}; Start-Sleep -Milliseconds 40 } while ((Get-Date) -lt $end)
    $null
}
function Quick-Back {
    $x = Quick "Закрыть"; if (-not $x) { throw "the wallet's page wears no «Закрыть»" }
    $x.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
    $end = (Get-Date).AddSeconds(5); $opened = $false
    do {
        $lib = Quick "Библиотека приложений" 0
        if ($lib) { $lib.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke(); $opened = $true }
        foreach ($hint in @("Хранить мою копию у собеседников", "Уведомления выключены")) {
            if ($opened) { break }
            $h = Quick $hint 0
            if (-not $h) { continue }
            $b = $h.Current.BoundingRectangle; $px = [int]($b.X + $b.Width / 2); $py = [int]($b.Y + $b.Height / 2)
            $who = Point-Holder $px $py
            if ($who) { throw "the right button on '$hint' would land on $who -- another program holds the front" }
            [MontanaMouse]::SetCursorPos($px, $py) | Out-Null
            [MontanaMouse]::mouse_event(0x0008, 0, 0, 0, [UIntPtr]::Zero); [MontanaMouse]::mouse_event(0x0010, 0, 0, 0, [UIntPtr]::Zero)
            $opened = $true
        }
        if (-not $opened) { Start-Sleep -Milliseconds 40 }
    } while (-not $opened -and (Get-Date) -lt $end)
    if (-not $opened) { throw "the panel's first slot never stood again after the wallet left" }
    $coin = Quick "Монета Времени"; if (-not $coin) { throw "the drawer never showed «Монета Времени»" }
    $coin.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
    if (-not (Quick "Баланс Времени")) { throw "the wallet's page never came back" }
    "  sees: Баланс Времени"
}
# the page opened again while the Pantheon burns: taps light it, the wallet is left and opened at once. The fire goes out three seconds
# after the last tap (coins.rs QUIET); a page seen again later than 2.8 s after it may have opened on a fire gone out -- where the auto
# minting rightly turns on -- and that look tells nothing: it is made again, three times at most
function Reopen-Burning {
    for ($try = 1; $try -le 3; $try++) {
        Front-Montana   # the window in front first: a return to it (iOS scenePhase .active) fires the auto minting by itself
        for ($i = 0; $i -lt 3; $i++) { Click-Named "Монета" }
        $lit = Get-Date
        $on = Lines "wallet_pull auto on"
        Quick-Back
        $took = ((Get-Date) - $lit).TotalSeconds
        Start-Sleep -Seconds 1
        if ($took -gt 2.8) { "  the page came back $([math]::Round($took, 1)) s after the last tap: the fire may be out, looked at again"; Start-Sleep -Seconds 4; continue }
        if ((Lines "wallet_pull auto on") -gt $on) { throw "the page opened while the Pantheon burns turned the auto minting on" }
        "  the page opened while the Pantheon burns ($([math]::Round($took, 1)) s after the last tap): no auto minting"
        $script:quiet = Lines "wallet_pull auto on"
        return
    }
    throw "the page never came back within 2.8 s of the last tap"
}
# THE REAL MOUSE PRESSES WHAT STANDS AT ITS POINT, and a window put in front again is a return that turns the auto minting on by itself
# (lib.rs auto_fire «active»): when another program has taken the front since the window was put there, the press would land on it and
# the step would read a turning-on that never came (a triage of 25.10.2026 saw a browser take the front 8 s before the hold) -- the scene
# says so and stops rather than put the window in front once more
function Still-Front($x, $y, [int]$since) {
    $who = Front-Holder; if (-not $who) { $who = Point-Holder $x $y }
    if ($who) { throw "another program took the front ($who) before the press: the desktop was not the scene's alone" }
    # the front taken and given back meanwhile is a return all the same: the app's own diary says what turned the auto minting on
    if ((Lines "wallet_pull auto on") -gt $since) {
        $last = @(Get-Content "$Root\A\trace.log" -Encoding UTF8 -ErrorAction SilentlyContinue | Where-Object { $_ -like "*wallet_pull auto on*" }) | Select-Object -Last 1
        throw "the auto minting was on before the press ($($last -replace '^\d+ ', '')): the press can show nothing"
    }
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
Still-Front $p[0] $p[1] $script:quiet
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
Still-Front $p[0] $p[1] $script:quiet
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
