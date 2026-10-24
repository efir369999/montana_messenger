# THE CALLS' PAGE, LIVE (iOS CallsTabView; after tools\ab.ps1 with the same -Root): A rings B and hangs up before B answers --
# B's calls' glyph says the missed call, and the page looked at clears it (iOS missedCallsUnseen, clearMissedCallsBadge); on A
# the hold menu deletes a call, «Select» marks rows and the bar's bin deletes the chosen, the block deed raises the block sheet
# (cancelled: nobody is blocked), «New Call» leads to the contacts; on B the bin for all empties the log. Two calls of one kind
# within 90 s are one row (iOS: the same call told twice within its life), so a run less than 90 s after a failed one finds B's
# missed call merged into the last and no badge: wait out the 90 s before running it again.
# usage: tools\callslog.ps1 -Root DIR [-Shots DIR]
param([Parameter(Mandatory = $true)][string]$Root, [string]$Shots = "")
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ui.ps1"
function Snap($name) { if ($Shots) { Shot-Montana (Join-Path $Shots "$name.png") } }
function Says([string]$text, [int]$timeout = 60) { Find-Named $text $timeout | Out-Null; "  sees: $text" }
# the call rows of one person on the calls' page: buttons named by the person and the call's state («Борис Тест, 0:29»)
function Rows-Of([string]$name) {
    $cond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Button)
    @((Root).FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond) | Where-Object { $_.Current.Name.StartsWith("$name, ") })
}
function Exact-Gone([string]$name, [int]$timeout = 20) {
    $end = (Get-Date).AddSeconds($timeout)
    do {
        if (-not @(All-Named | Where-Object { $_.Current.Name -ceq $name }).Count) { return }
        Start-Sleep -Milliseconds 400
    } while ((Get-Date) -lt $end)
    throw "'$name' is still on screen"
}
function Count-Settles([string]$name, [int]$want, [int]$timeout = 15) {
    $end = (Get-Date).AddSeconds($timeout)
    do { $n = (Rows-Of $name).Count; if ($n -eq $want) { return $n }; Start-Sleep -Milliseconds 400 } while ((Get-Date) -lt $end)
    throw "rows of '$name': $n, not $want"
}
$t0 = Get-Date
$B = Start-Montana -DataDir "$Root\B"; Front-Montana -X 920 -Y 40 -Width 460 -Height 900
Start-Sleep -Seconds 2
$A = Start-Montana -DataDir "$Root\A"; Front-Montana -X 0 -Y 40 -Width 460 -Height 900
Find-Named "Борис Тест" 30 | Out-Null

"A rings B and hangs up before B answers"
Click-Named "Борис Тест"; Click-Named "Позвонить"; Click-Named "Аудиозвонок"
Says "Аудиовызов Montana" 10
Use-Montana $B
Says "Принять" 60
Use-Montana $A
Click-Named "Отбой"
Use-Montana $B
try { Says "Звонки: 1" 60 } catch {
    Snap "201-B-no-badge"
    Click-Named "Звонки"; Start-Sleep -Seconds 2
    "  B without the badge: " + ((Rows-Of "Алиса Тест" | Select-Object -First 3 | ForEach-Object { $_.Current.Name }) -join " | ")
    throw
}
Gone-Named "Звонок завершён" 20   # the call's own screen leaves first
Snap "201-B-missed-badge"
Click-Named "Звонки: 1"
Says "Алиса Тест, Пропущенный" 15
Exact-Gone "Звонки: 1"
"  B: the page looked at, the badge is gone"

"A: the arrow back to the top (iOS MTToTopButton) on the Wall of Thoughts"
Use-Montana $A
Gone-Named "Звонок завершён" 20
Click-Named "Назад"   # the narrow window stood in the chat the call was made from
Open-Drawer; Click-Named "Стена Мыслей"
Start-Sleep -Seconds 3
if (@(All-Named | Where-Object { $_.Current.Name -ceq "Наверх" }).Count) { throw "the arrow stands at the list's top" }
Front-Montana
if ([MontanaWin]::GetForegroundWindow() -ne (Handle)) { throw "Montana is not in front: no wheel" }
$h = Handle; $r = New-Object MontanaWin+Rect; [MontanaWin]::GetWindowRect($h, [ref]$r) | Out-Null
[MontanaMouse]::SetCursorPos($r.Left + 200, $r.Top + 600) | Out-Null
for ($i = 0; $i -lt 20; $i++) { [MontanaMouse]::mouse_event(0x0800, 0, 0, [uint32]4294967176, [UIntPtr]::Zero); Start-Sleep -Milliseconds 60 }
Says "Наверх" 5
Snap "204-A-feed-to-top"
Click-Named "Наверх"
Exact-Gone "Наверх" 5
"  A: the arrow came below the first screen and took the feed back to its top"

"A: the hold menu deletes a call"
Click-Named "Звонки"
Start-Sleep -Seconds 2
$n = (Rows-Of "Борис Тест").Count
"  A: $n calls with Boris"
if ($n -lt 4) { throw "A holds too few calls with Boris for the check: $n" }
RightClick-Named "Борис Тест"
Press-MenuRow "Удалить"
$n = Count-Settles "Борис Тест" ($n - 1)
"  A: deleted by the menu, $n left"

"A: Select marks the row, a tap marks another, the bin deletes both"
RightClick-Named "Борис Тест"
Press-MenuRow "Выбрать"
Says "Удалить все" 5
if (@(All-Named | Where-Object { $_.Current.Name -ceq "Новый звонок" }).Count) { throw "«New Call» stands while selecting" }
$rows = Rows-Of "Борис Тест"
$p = $null   # selecting, a row is a toggle (aria-pressed): it is toggled, not pressed
if ($rows[1].TryGetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern, [ref]$p)) { $p.Toggle() }
else { $rows[1].GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke() }
Start-Sleep -Milliseconds 500
Snap "202-A-calls-selecting"
Click-Named "Удалить" 5   # the bar's bin for the chosen; «Удалить все» is the bin for all
$n = Count-Settles "Борис Тест" ($n - 2)
Exact-Gone "Удалить все"
"  A: two chosen deleted, $n left; the bar is gone"

"A: the block deed raises the block sheet, cancelled"
RightClick-Named "Борис Тест"
Press-MenuRow "Заблокировать"
Says "Заблокировать этого человека?" 5
Click-Named "Отмена"
Gone-Named "Заблокировать этого человека?" 5
"  A: the sheet came and went; nobody blocked"

"A: New Call leads to the contacts"
Click-Named "Новый звонок"
Exact-Gone "Новый звонок" 5
Says "Поиск" 5
"  A: the contacts stand"

"B: the bin for all empties the log"
Use-Montana $B
RightClick-Named "Алиса Тест"
Press-MenuRow "Выбрать"
Click-Named "Удалить все"
Says "Здесь появятся ваши" 15
Snap "203-B-calls-empty"
"  B: the log is empty"
"done in $([int]((Get-Date) - $t0).TotalSeconds) s"
Use-Montana $A; Stop-Montana; Use-Montana $B; Stop-Montana
