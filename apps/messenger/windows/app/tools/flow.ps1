# THE MONEY FLOW, LIVE (iOS MTMoneyFlow, LiveDraftState, MTLetterSeal; after tools\ab.ps1 with the same -Root): A and B turn the
# coin of their chat -- the row «Денежный поток начался» stands, the feed turns newest on top. B types without sending and A sees
# B's live words as they stand in B's field; B sends and the live words leave, the letter stays. Every letter wears its gematria at
# the stamp, the same number on both sides. Both turn the coin off; then B's words show nothing at A.
# usage: tools\flow.ps1 -Root DIR [-Shots DIR]
param([Parameter(Mandatory = $true)][string]$Root, [string]$Shots = "")
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ui.ps1"
function Snap($name) { if ($Shots) { Shot-Montana (Join-Path $Shots "$name.png") } }
function Says([string]$text, [int]$timeout = 60) { Find-Named $text $timeout | Out-Null; "  sees: $text" }
function Wrote([string]$who, [string]$line, [int]$timeout = 60) {
    $end = (Get-Date).AddSeconds($timeout)
    do { $hit = Get-Content "$Root\$who\trace.log" -Encoding UTF8 -ErrorAction SilentlyContinue | Where-Object { $_ -like "*$line*" } | Select-Object -Last 1; if ($hit) { "  ${who}: $($hit -replace '^\d+ ', '')"; return }; Start-Sleep -Milliseconds 500 } while ((Get-Date) -lt $end)
    throw "$who never wrote '$line'"
}
function Lines([string]$who, [string]$line) { @(Get-Content "$Root\$who\trace.log" -Encoding UTF8 -ErrorAction SilentlyContinue | Where-Object { $_ -like "*$line*" }).Count }
# a line written once more than it stood before
function Wrote-Again([string]$who, [string]$line, [int]$before, [int]$timeout = 60) {
    $end = (Get-Date).AddSeconds($timeout)
    do { if ((Lines $who $line) -gt $before) { "  ${who}: $line"; return }; Start-Sleep -Milliseconds 500 } while ((Get-Date) -lt $end)
    throw "$who never wrote '$line' again"
}
# the coin of the open chat, as its toggle stands: «On» or «Off»
function Flow-State {
    Find-Named "Денежный поток" 15 | Out-Null
    foreach ($e in @(All-Named | Where-Object { try { $_.Current.Name -eq "Денежный поток" } catch { $false } })) {
        $p = $null
        if ($e.TryGetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern, [ref]$p)) { return [string]$p.Current.ToggleState }
    }
    throw "the coin of the chat is not on screen"
}
# the coin turned on afresh: a run left on by a broken one is turned off first, so the row of the beginning is born now
function Flow-On([string]$who) {
    if ((Flow-State) -eq "On") { $off = Lines $who "money_flow on=false"; Click-Named "Денежный поток"; Wrote-Again $who "money_flow on=false" $off 20 }
    $on = Lines $who "money_flow on=true"
    Click-Named "Денежный поток"
    Wrote-Again $who "money_flow on=true" $on 20
}
# how many elements carry exactly this name
function Count-Named([string]$name) { @(All-Named | Where-Object { try { $_.Current.Name -eq $name } catch { $false } }).Count }
# the gematria numbers the stamps wear: «· 1234»
function Gems { @(Get-Texts | Where-Object { $_ -match '^· \d+$' } | ForEach-Object { [int]($_ -replace '^· ', '') }) }
function Top-Of([string]$name) { (Find-Named $name 10).Current.BoundingRectangle.Top }
Add-Type -AssemblyName System.Windows.Forms
$env:MONTANA_TRACE = "1"
Remove-Item "$Root\A\trace.log", "$Root\B\trace.log" -ErrorAction SilentlyContinue
$stamp = Get-Date -Format "HHmmss"
$t0 = Get-Date
$A = Start-Montana -DataDir "$Root\A"; Front-Montana -X 0 -Y 40 -Width 1200 -Height 950
$B = Start-Montana -DataDir "$Root\B"; Front-Montana -X 920 -Y 40 -Width 1200 -Height 950
"A turns the coin of the chat with B"
Use-Montana $A; Front-Montana
Click-Named "Борис Тест"
Flow-On "A"
Says "Денежный поток начался" 20
"B turns it too and writes a letter that stands"
Use-Montana $B; Front-Montana
Click-Named "Алиса Тест"
Flow-On "B"
Says "Денежный поток начался" 20
Type-Into "Сообщение..." "письмо потока $stamp"; Click-Named "Отправить"; Says "письмо потока $stamp" 20
# the letter closes every draft said before it lands (iOS ChatStore.place): B types once it stands at A
Use-Montana $A; Front-Montana
Says "письмо потока $stamp" 120
"B types without sending: A sees the live words"
Use-Montana $B; Front-Montana
$words = Lines "B" "draft_tx word"
Type-Into "Сообщение..." "живые"
Start-Sleep -Seconds 2
Type-Into "Сообщение..." "живые слова $stamp"
Wrote-Again "B" "draft_tx word" ($words + 1) 20
Use-Montana $A; Front-Montana
Says "живые слова $stamp" 60
Snap "180-A-live-words"
# the turned feed: B's letter, newer than the row of the flow's beginning, stands over it
$letter = Top-Of "письмо потока $stamp"; $row = Top-Of "Денежный поток начался"
if ($letter -ge $row) { throw "the feed is not turned: the letter at $letter, the row at $row" }
"  the newest stands on top: the letter at $letter, the row at $row"
$gemsA = Gems
if (-not $gemsA.Count) { throw "no stamp wears its gematria" }
"  A's stamps wear $($gemsA.Count) gematria numbers"
"B sends: the live words leave, the letter stays"
Use-Montana $B; Front-Montana
$gemsB = Gems
$shared = @($gemsA | Where-Object { $gemsB -contains $_ })
if (-not $shared.Count) { throw "no letter wears the same gematria on both sides (A: $gemsA; B: $gemsB)" }
"  the same gematria on both sides: $($shared -join ', ')"
$ends = Lines "B" "draft_tx end"
Type-Into "Сообщение..." "живые слова $stamp"
[System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
Wrote-Again "B" "draft_tx end" $ends 20
Use-Montana $A; Front-Montana
$end = (Get-Date).AddSeconds(60)
do { $n = Count-Named "живые слова $stamp"; if ($n -eq 1) { break }; Start-Sleep -Milliseconds 500 } while ((Get-Date) -lt $end)
if ($n -ne 1) { throw "the live words and the letter: $n elements named so (one expected: the letter)" }
"  one bubble of those words: the letter"
Snap "181-A-letter-landed"
"both turn the coin off: B's words show nothing at A"
Click-Named "Денежный поток"
Wrote "A" "money_flow on=false" 20
Use-Montana $B; Front-Montana
Click-Named "Денежный поток"
Wrote "B" "money_flow on=false" 20
Type-Into "Сообщение..." "без потока $stamp"
Start-Sleep -Seconds 4
Use-Montana $A; Front-Montana
Start-Sleep -Seconds 6
if ((Count-Named "без потока $stamp") -ne 0) { throw "B's words showed at A with the flow off" }
"  nothing of B's field at A"
Use-Montana $B; Front-Montana
Type-Into "Сообщение..." ""
"done in $([int]((Get-Date) - $t0).TotalSeconds) s"
Use-Montana $A; Stop-Montana; Use-Montana $B; Stop-Montana
