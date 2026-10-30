# THE FIRST SLOT'S PAGE AND EVERY WAY BACK, AS iOS GOES (the owner's word 25.10.2026 14:3x: the window froze after the crossed
# people; iOS ContentView.swift 2473-2478: the slot opens Data and Storage alone, its cross top left; MontanaSettings.swift 113-147:
# Settings is one navigation stack, its list standing under a pushed page). After tools\ab.ps1 with the same -Root (it answers
# «Не сейчас»: the slot wears the crossed people). Every page must stand within 2 s of its press, and after every way back the window
# must answer: Window-Alive, a click of the mouse itself. The freeze: a page of Settings left by «Назад», Esc, Alt+←, the mouse's back
# button or its edge stroke came back «leaving» -- inert, under the window's foot -- and the window under it stayed inert: the chats
# drawn, nothing taking a click, no button in the reader's tree.
# First the list of Settings from the drawer: «Данные и память» left by «Назад» (today's build fails there, within 2 s), by Esc, Alt+←,
# the mouse's back button and the page's edge stroke, five times in a row; each page of Settings itself and an answer of «Вопросы»;
# the list keeps its place under a page; the list left by Esc. Then the slot's own page: the cross, never «Назад»; the same ways out;
# five entries in a row; a double press of the slot by the mouse, quick and slow.
# Never pressed: a language on «Язык» (it reloads the window), a row that opens something outside the window, a switch.
# -Still: the window asks for less motion (WebView2's --force-prefers-reduced-motion, this check's own; no setting of this computer is
# touched) -- Page then closes without its leave, and the edge stroke still set «leaving» on today's build (Settings.jsx 37, 82).
# usage: tools\slotpage.ps1 -Root DIR [-Shots DIR] [-Still]
param([Parameter(Mandatory = $true)][string]$Root, [string]$Shots = "", [switch]$Still)
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ui.ps1"
Add-Type -AssemblyName System.Windows.Forms
if ($Shots) { New-Item -ItemType Directory -Force $Shots | Out-Null }
function Snap($name) { if ($Shots) { Shot-Montana (Join-Path $Shots "$name.png") } }
$slot = "Хранить мою копию у собеседников"
$list = "Настройки"; $listProof = "Уведомления и звуки"
$data = "Данные и память"; $dataProof = "Через Wi-Fi"
$script:mark = $null   # where the slot's page wears its cross: a second press of the slot lands there

# THE SLOT BY THE MOUSE ITSELF, at its middle, as the owner pressed it
function Slot-Click {
    if (-not (Bar-Slot $slot)) { throw "the first slot «$slot» is not on the time panel" }
    Front-Montana
    $r = (Bar-Slot $slot).Current.BoundingRectangle
    [MontanaMouse]::SetCursorPos([int]($r.X + $r.Width / 2), [int]($r.Y + $r.Height / 2)) | Out-Null; Start-Sleep -Milliseconds 120
    [MontanaMouse]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero); [MontanaMouse]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
}
# THE SLOT TWICE BY THE MOUSE, $Gap ms apart (one double click of Windows): where the slot's page wears its cross, when the slot
# holds that point (the slot's middle lies under the page's mark at the window's usual width), else at the slot's middle
function Slot-Twice([int]$Gap) {
    Front-Montana
    $r = (Bar-Slot $slot).Current.BoundingRectangle
    $x = $r.X + $r.Width / 2; $y = $r.Y + $r.Height / 2; $where = "at the slot's middle"
    if ($script:mark) {
        $m = $script:mark
        $x0 = [Math]::Max($r.Left, $m.Left); $x1 = [Math]::Min($r.Right, $m.Right); $y0 = [Math]::Max($r.Top, $m.Top); $y1 = [Math]::Min($r.Bottom, $m.Bottom)
        if ($x1 - $x0 -ge 4 -and $y1 - $y0 -ge 4) { $x = ($x0 + $x1) / 2; $y = ($y0 + $y1) / 2; $where = "where the page's cross stands" }
    }
    [MontanaMouse]::SetCursorPos([int]$x, [int]$y) | Out-Null; Start-Sleep -Milliseconds 150
    [MontanaMouse]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero); [MontanaMouse]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds $Gap
    [MontanaMouse]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero); [MontanaMouse]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
    $where
}
# A KEY TO THE PAGE THAT STANDS (leave.js: Esc, Alt+←): the window to the front, the page's own mark holding the keyboard (a mark
# does nothing of its own with either key), the key sent as a person sends it
function Key-To([string]$Title, [string]$Keys) {
    $pg = Page-Over $Title
    if (-not $pg) { throw "no page «$Title» to send a key to" }
    Front-Montana
    foreach ($n in @("Назад", "Закрыть")) { $m = Inside-Page (Page-Over $Title) $n; if ($m) { try { $m.SetFocus() } catch {}; break } }
    Start-Sleep -Milliseconds 150
    [System.Windows.Forms.SendKeys]::SendWait($Keys)
}
# THE MOUSE'S OWN BACK BUTTON (XBUTTON1, whose mouseup leave.js hears) over the page's left margin, where no row stands
function Mouse-Back([string]$Title) {
    if (-not (Page-Over $Title)) { throw "no page «$Title» under the mouse" }
    Front-Montana
    $r = (Page-Over $Title).Current.BoundingRectangle
    [MontanaMouse]::SetCursorPos([int]($r.X + 10), [int]($r.Y + $r.Height * 0.6)) | Out-Null; Start-Sleep -Milliseconds 150
    [MontanaMouse]::mouse_event(0x0080, 0, 0, 1, [UIntPtr]::Zero); Start-Sleep -Milliseconds 40   # MOUSEEVENTF_XDOWN, XBUTTON1
    [MontanaMouse]::mouse_event(0x0100, 0, 0, 1, [UIntPtr]::Zero)                                # MOUSEEVENTF_XUP
}
# THE PAGE'S EDGE STROKE BY THE MOUSE ITSELF (Settings.jsx Page, iOS MontanaSlideController.pan: pressed within the page's first 16
# points and drawn right past a third of its width): the left button down 3 px inside the page's left edge, carried right over half
# its width in 14 steps, let go while still moving
function Edge-Stroke([string]$Title) {
    if (-not (Page-Over $Title)) { throw "no page «$Title» to stroke" }
    Front-Montana
    $r = (Page-Over $Title).Current.BoundingRectangle
    $x = [int]($r.X + 3); $y = [int]($r.Y + $r.Height * 0.6); $far = $r.Width * 0.5
    [MontanaMouse]::SetCursorPos($x, $y) | Out-Null; Start-Sleep -Milliseconds 150
    [MontanaMouse]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 40
    for ($i = 1; $i -le 14; $i++) { [MontanaMouse]::SetCursorPos([int]($x + $far * $i / 14), $y) | Out-Null; Start-Sleep -Milliseconds 16 }
    [MontanaMouse]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
}
$ways = [ordered]@{ "esc" = "Esc"; "altleft" = "Alt+←"; "xback" = "the mouse's back button"; "stroke" = "the page's edge stroke" }
function Way-Out([string]$How, [string]$Title) {
    switch ($How) {
        "back"    { Press-In-Page $Title "Назад" }
        "cross"   { Press-In-Page $Title "Закрыть" }
        "esc"     { Key-To $Title "{ESC}" }
        "altleft" { Key-To $Title "%{LEFT}" }
        "xback"   { Mouse-Back $Title }
        "stroke"  { Edge-Stroke $Title }
        default   { throw "no way out named '$How'" }
    }
}
# SETTINGS FROM THE DRAWER (iOS: the drawer's last row, ContentView.swift 1676): the list stands within 2 s, its sheet's rise ended
function Settings-Open {
    Open-Drawer
    Press-Exact "Настройки"
    Page-Drawn $list $listProof
    Start-Sleep -Milliseconds 450
}
# a page of the list pushed and standing, its slide ended
function Push([string]$Row, [string]$Title, [string]$Proof) { Press-In-Page $list $Row; Page-Drawn $Title $Proof; Start-Sleep -Milliseconds 400 }
# the page left its way, and the list standing again within 2 s
function Back-To-List([string]$How, [string]$Title, [string]$Proof) { Way-Out $How $Title; Page-Left $Title $Proof; Page-Drawn $list $listProof }
# the list closed by its cross, and the window answering
function List-Closed([string]$After) { Start-Sleep -Milliseconds 300; Press-In-Page $list "Закрыть"; Page-Left $list $listProof; Window-Alive $After }

$t0 = Get-Date
$was = $env:WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS
if ($Still) {
    # the window's browser of this folder gone first: a browser still standing with other flags would refuse the new ones
    $ud = [IO.Path]::GetFullPath((Join-Path "$Root\A" "EBWebView")).ToLower()
    $end = (Get-Date).AddSeconds(20)
    while ((Get-Date) -lt $end -and @(Get-CimInstance Win32_Process -Filter "Name='msedgewebview2.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -and $_.CommandLine.ToLower().Contains($ud) }).Count) { Start-Sleep -Milliseconds 500 }
    $env:WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS = "--disable-features=msWebOOUI,msPdfOOUI,msSmartScreenProtection --force-prefers-reduced-motion"
}
"the program: $((Resolve-Path $script:exe).Path), built $((Get-Item $script:exe).LastWriteTime.ToString('dd.MM.yyyy HH:mm:ss'))$(if ($Still) { '; less motion asked' })"
$A = Start-Montana -DataDir "$Root\A"
try {
    Front-Montana -X 0 -Y 40 -Width 1300 -Height 800

    "the first slot wears the crossed people (TopBar.jsx slot 0, lib.rs bar_first: the banners allowed, no copy kept with contacts)"
    $w = [Diagnostics.Stopwatch]::StartNew(); $first = ""; $seen = $null
    do {
        $first = ""
        foreach ($n in @($slot, "Уведомления выключены", "Библиотека приложений")) { if (Bar-Slot $n) { $first = $n; break } }
        if ($first -eq $slot -or $first -eq "Уведомления выключены") { break }
        if ($first -and $null -eq $seen) { $seen = $w.Elapsed.TotalSeconds }
        if ($null -ne $seen -and $w.Elapsed.TotalSeconds - $seen -gt 10) { break }   # the grid answered, and stays
        Start-Sleep -Milliseconds 300
    } while ($w.Elapsed.TotalSeconds -lt 60)
    if ($first -eq "Уведомления выключены") { throw "not checked: Windows refuses this program's banners -- the first slot is the crossed speaker «Уведомления выключены» (lib.rs bar_first answers «notifications» before «keeping»), so the crossed people and their page cannot be reached here" }
    if ($first -eq "Библиотека приложений") { throw "not checked: the first slot is the drawer's grid «Библиотека приложений», not the crossed people -- this identity keeps its copy with its contacts, or was never asked (tools\ab.ps1 answers «Не сейчас»)" }
    if ($first -ne $slot) { throw "not checked: no first slot on the time panel within 60 s" }
    if ((Bar-Slot $slot).Current.BoundingRectangle.Width -lt 4) { throw "not checked: the time panel stands folded -- its first slot has no room for the mouse" }
    "  the slot: «$slot»"
    Window-Alive "the start"

    "the list of Settings from the drawer: «Данные и память» left by «Назад» -- the list stands again within 2 s, and the window answers"
    Settings-Open
    Push $data $data $dataProof
    Back-To-List "back" $data $dataProof
    Snap "slotpage-1-list-again"
    List-Closed "«Данные и память» → «Назад» → «Закрыть»"

    "«Данные и память» left by Esc, by Alt+←, by the mouse's back button and by the page's edge stroke: the list stands again each time"
    Settings-Open
    foreach ($k in $ways.Keys) { Push $data $data $dataProof | Out-Null; Back-To-List $k $data $dataProof; "  left by $($ways[$k])" }
    List-Closed "«Данные и память» left by Esc, Alt+←, the mouse's back button and the edge stroke"

    "five times in a row: «Данные и память», then «Назад»"
    Settings-Open
    for ($i = 1; $i -le 5; $i++) { Push $data $data $dataProof | Out-Null; Back-To-List "back" $data $dataProof | Out-Null }
    "  the list stood again each time"
    List-Closed "five times «Данные и память» → «Назад»"

    "each page of Settings itself left by «Назад»: the list stands again (Privacy, a page of its own, the same); an answer of «Вопросы»"
    Settings-Open
    foreach ($p in @(@("Уведомления и звуки", "Уведомления", "Разрешить уведомления"), @("Язык", "Язык", "Смена языка применится сразу."),
                     @("Задать вопрос", "Задать вопрос", "Справка"), @("Условия использования", "Условия использования", "contact@montana.quest"),
                     @("Приватность", "Приватность", "Заблокированные"))) {
        Push $p[0] $p[1] $p[2]; Back-To-List "back" $p[1] $p[2]
    }
    # the answer is a step of «Вопросы»: back from it, the questions stand again, then the list. A question's row is one button
    # that UI Automation names «<question> ›» (Questions.jsx:199-200; read on the live window 26.10.2026), not the bare question
    Push "Вопросы" "Вопросы" "Кто видит мой уровень? ›"
    Press-In-Page "Вопросы" "Кто видит мой уровень? ›"; Page-Drawn "Приватность" "Кто видит мой уровень?"; Start-Sleep -Milliseconds 400
    Press-In-Page "Приватность" "Назад"; Page-Left "Приватность" "Кто видит мой уровень?"; Page-Drawn "Вопросы" "Кто видит мой уровень? ›"
    Start-Sleep -Milliseconds 300
    Back-To-List "back" "Вопросы" "Кто видит мой уровень? ›"

    "the list keeps its place under a page and after it (iOS NavigationStack: the list is never drawn anew)"
    $pg = Page-Over $list $listProof
    $top = (Inside-Page $pg "Условия использования").Current.BoundingRectangle.Y
    try { (Inside-Page $pg "Политика конфиденциальности").GetCurrentPattern([System.Windows.Automation.ScrollItemPattern]::Pattern).ScrollIntoView() } catch {}
    Start-Sleep -Milliseconds 600
    $y0 = (Inside-Page (Page-Over $list $listProof) "Условия использования").Current.BoundingRectangle.Y
    if ([Math]::Abs($y0 - $top) -lt 4) { "  the list does not scroll at this size: its place is not weighed" }
    else {
        Push "Условия использования" "Условия использования" "contact@montana.quest"
        Back-To-List "back" "Условия использования" "contact@montana.quest"
        Start-Sleep -Milliseconds 600
        $y1 = (Inside-Page (Page-Over $list $listProof) "Условия использования").Current.BoundingRectangle.Y
        if ([Math]::Abs($y1 - $y0) -gt 4) { throw "the list of Settings came back at another place («Условия использования» at y $([int]$y1), was $([int]$y0)): iOS keeps the list where it stood under a pushed page (MontanaSettings.swift 113-147)" }
        "  the list stands where it stood («Условия использования» at y $([int]$y0), scrolled from $([int]$top))"
    }

    "the list itself left by Esc: Settings closes, and the window answers"
    Key-To $list "{ESC}"; Page-Left $list $listProof
    Window-Alive "the list of Settings left by Esc"

    "the slot's own page (iOS .keeping): «Данные и память» wearing the cross top left, never «Назад»; the cross takes it away"
    Slot-Click
    Page-Drawn $data $dataProof
    $pg = Page-Over $data $dataProof
    if (Inside-Page $pg "Назад") { throw "the slot's page wears «Назад»: iOS gives it the cross top left and nothing under it (ContentView.swift 2473-2478); «Назад» leads into the list of Settings" }
    if (-not (Inside-Page $pg "Закрыть")) { throw "the slot's page wears no cross «Закрыть»" }
    Start-Sleep -Milliseconds 450
    $script:mark = (Inside-Page (Page-Over $data $dataProof) "Закрыть").Current.BoundingRectangle
    Snap "slotpage-2-slot-page"
    Press-In-Page $data "Закрыть"; Page-Left $data $dataProof
    Window-Alive "the slot's page → «Закрыть»"

    "the slot's page left by Esc, by Alt+←, by the mouse's back button and by its edge stroke (iOS: the page leaves by the screen edge's pan, ContentView.swift 700-702)"
    foreach ($k in $ways.Keys) {
        Slot-Click; Page-Drawn $data $dataProof | Out-Null; Start-Sleep -Milliseconds 450
        Way-Out $k $data; Page-Left $data $dataProof
        Window-Alive "the slot's page left by $($ways[$k])"
    }

    "five entries in a row: the slot, its page, the cross"
    for ($i = 1; $i -le 5; $i++) {
        Slot-Click; Page-Drawn $data $dataProof | Out-Null; Start-Sleep -Milliseconds 300
        Press-In-Page $data "Закрыть"; Page-Left $data $dataProof
        $w = [Diagnostics.Stopwatch]::StartNew()
        while (-not (Bar-Slot $slot) -and $w.Elapsed.TotalSeconds -lt 2) { Start-Sleep -Milliseconds 100 }
        if (-not (Bar-Slot $slot)) { throw "entry ${i}: the slot did not stand again within 2 s of the cross" }
    }
    Window-Alive "five entries of the slot's page"

    $slow = [Math]::Min(300, [System.Windows.Forms.SystemInformation]::DoubleClickTime - 100)
    "a double press of the slot by the mouse, quick (90 ms) and slow ($slow ms, still one double click of Windows): the page stands and answers, or the second press found its cross; the window answers either way"
    foreach ($gap in @(90, $slow)) {
        $where = Slot-Twice $gap
        Start-Sleep -Milliseconds 1500
        if (Page-Over $data $dataProof) {
            "  $gap ms apart, ${where}: the page stands"
            Press-In-Page $data "Закрыть"; Page-Left $data $dataProof
        } else { "  $gap ms apart, ${where}: the page is gone -- the second press found its cross" }
        Window-Alive "a double press of the slot, $gap ms apart"
    }
    "done in $([int]((Get-Date) - $t0).TotalSeconds) s"
} catch {
    $failure = $_
    # the step that failed, by its line here (the throw itself stands in a helper of ui.ps1)
    $at = @("$($failure.ScriptStackTrace)" -split "`n" | Where-Object { $_ -like "*slotpage.ps1*" }) | Select-Object -Last 1
    if ($at) { "  failed $($at.Trim())" }
    if ($Shots) { try { Shot-Montana (Join-Path $Shots "slotpage-failed.png") } catch {} }
    throw $failure
} finally {
    Stop-Montana
    $env:WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS = $was
}
