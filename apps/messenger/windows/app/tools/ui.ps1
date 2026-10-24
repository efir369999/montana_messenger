# A remote for the running Montana window, as a person at the keyboard: Windows UI Automation reads the WebView2's
# accessible tree -- every button by its name, every field -- and acts on it. Dot-source it: . tools\ui.ps1
#   Start-Montana [-DataDir DIR]         the built app, with a data folder of its own; returns the process
#   Find-Named NAME [-Timeout S]         the first element whose name contains NAME (waits for it)
#   Click-Named NAME                     invokes that element (a button, a link, a switch)
#   Type-Into NAME TEXT                  the field named NAME (or its placeholder) gets TEXT
#   Get-Texts                            every name on screen, in order -- what a person reads
#   Stop-Montana                         closes the app
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
$script:proc = $null
$script:exe = Join-Path $PSScriptRoot "..\..\target\release\montana-desktop.exe"

# A DRAWN CLIP FOR THE TEST CAMERA (WebView2 reads it in a camera's place; its own drawn camera stops at once on this Windows):
# 320 by 240, 24 frames a second, a light bar walking over grey -- nothing of this computer in it
function Fake-Camera {
    $path = Join-Path ([IO.Path]::GetTempPath()) "montana-check-camera.y4m"
    if (Test-Path $path) { return $path }
    $w = 320; $h = 240; $n = 24
    $part = "$path.$PID"
    $fs = [IO.File]::Create($part)
    $head = [Text.Encoding]::ASCII.GetBytes("YUV4MPEG2 W$w H$h F24:1 Ip A1:1 C420jpeg`n")
    $fs.Write($head, 0, $head.Length)
    $mark = [Text.Encoding]::ASCII.GetBytes("FRAME`n")
    $chroma = [byte[]]::new($w * $h / 2); for ($i = 0; $i -lt $chroma.Length; $i++) { $chroma[$i] = 128 }
    $luma = [byte[]]::new($w * $h); $row = [byte[]]::new($w)
    for ($f = 0; $f -lt $n; $f++) {
        $x0 = ($f * 13) % $w
        for ($x = 0; $x -lt $w; $x++) { $row[$x] = if ($x -ge $x0 -and $x -lt $x0 + 40) { 220 } else { 90 } }
        for ($r = 0; $r -lt $h; $r++) { [Array]::Copy($row, 0, $luma, $r * $w, $w) }
        $fs.Write($mark, 0, $mark.Length); $fs.Write($luma, 0, $luma.Length); $fs.Write($chroma, 0, $chroma.Length)
    }
    $fs.Close()
    Move-Item -Force $part $path
    $path
}

function Start-Montana([string]$DataDir = "", [switch]$Person, [switch]$FakeMedia, [switch]$KeepCall, [int]$Cameras = 0) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo $script:exe
    $psi.UseShellExecute = $false
    if ($DataDir) { $psi.EnvironmentVariables["MONTANA_DATA_DIR"] = $DataDir }
    # a check starts clean: a call a failed check left standing on the disk would be gone back into (only tools\callrevive.ps1
    # keeps it, -KeepCall)
    if ($DataDir -and -not $KeepCall) { Remove-Item (Join-Path $DataDir "vault\callHeld.sealed") -ErrorAction SilentlyContinue }
    # WebView2's own test devices (a check of pictures and screens): a drawn camera, a drawn screen, a made-up microphone and no
    # sound out -- no camera, no microphone and no screen of this computer is opened; the program's own arguments are kept
    if ($FakeMedia) {
        $psi.EnvironmentVariables["WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS"] = "--disable-features=msWebOOUI,msPdfOOUI,msSmartScreenProtection " +
            "--autoplay-policy=no-user-gesture-required --use-fake-device-for-media-stream --use-file-for-fake-video-capture=$(Fake-Camera) " +
            "--use-fake-ui-for-media-stream --mute-audio"
    }
    # no Windows Hello, finger or PIN in a check (the owner's word 20.10.2026): the window refuses the words at once, nobody
    # is asked; only tools\manual-hello.ps1 -Owner starts it with -Person, for the real Hello and the person beside it
    # SEVERAL TEST CAMERAS (the call's «Сменить камеру»): WebView2's own drawn cameras, as many as asked -- still nothing of this
    # computer is opened (the drawn picture may stand still on this Windows; the switch itself is what such a check reads)
    if ($Cameras -gt 1) {
        $psi.EnvironmentVariables["WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS"] = "--disable-features=msWebOOUI,msPdfOOUI,msSmartScreenProtection " +
            "--autoplay-policy=no-user-gesture-required --use-fake-device-for-media-stream=device-count=$Cameras --use-fake-ui-for-media-stream --mute-audio"
    }
    if (-not $Person) { $psi.EnvironmentVariables["MONTANA_NO_HELLO"] = "1" }
    $script:proc = [System.Diagnostics.Process]::Start($psi)
    # a freshly built program is read through by the antivirus at its first starts: its window may take a while (60 s at most)
    for ($i = 0; $i -lt 240 -and $script:proc.MainWindowHandle -eq [IntPtr]::Zero; $i++) { Start-Sleep -Milliseconds 250; $script:proc.Refresh() }
    Start-Sleep -Milliseconds 800
    $script:proc
}

Add-Type @"
using System; using System.Runtime.InteropServices; using System.Text;
public static class MontanaFind {
  delegate bool Each(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] static extern bool EnumWindows(Each f, IntPtr l);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  // the process's own top-level window of that class: read off the window list, no message sent to any window -- a stopped
  // process's windows never hold the search
  public static IntPtr Of(int pid, string cls) {
    IntPtr found = IntPtr.Zero;
    EnumWindows((h, l) => {
      uint p; GetWindowThreadProcessId(h, out p);
      if (p != (uint)pid) return true;
      var sb = new StringBuilder(64); GetClassName(h, sb, 64);
      if (sb.ToString() != cls) return true;
      found = h; return false;
    }, IntPtr.Zero);
    return found;
  }
}
"@

# The app's own window, its handle asked again (the window may stand anew while the program starts): a minimized window
# leaves the process's «main window» to a hidden helper of its own, so the window is looked up by its class
function Handle {
    $script:proc.Refresh()
    $w = [MontanaFind]::Of($script:proc.Id, "Tauri Window")
    if ($w -ne [IntPtr]::Zero) { return $w }
    $script:proc.MainWindowHandle
}

# The window as UI Automation sees it
function Root { [System.Windows.Automation.AutomationElement]::FromHandle((Handle)) }

# Everything on the window, or nothing while it is not there yet
function All-Named {
    try { $r = Root; if ($r) { return $r.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition) } } catch {}
    @()
}

function Find-Named([string]$Name, [int]$Timeout = 15) {
    $end = (Get-Date).AddSeconds($Timeout)
    do {
        $all = All-Named
        try {
            foreach ($e in $all) { if ($e.Current.Name -eq $Name) { return $e } }   # the exact name first
            foreach ($e in $all) { if ($e.Current.Name -and $e.Current.Name.Contains($Name)) { return $e } }
        } catch {}   # an element that left while it was read: the next look reads the window again
        Start-Sleep -Milliseconds 300
    } while ((Get-Date) -lt $end)
    throw "nothing named '$Name' on screen"
}

# THE TIME COIN IS A PAGE OVER THE APP (iOS ui.walletPage): before the panel's glyphs are pressed, the wallet's page standing over them
# is closed by its cross, as a person closes it
function Leave-Wallet {
    # a page of the wallet still sliding out (TimeChain, History) shows neither the wallet nor the panel for a moment: looked at again
    # for up to three seconds -- the wallet's page closed by its cross, or the panel standing free
    $end = (Get-Date).AddSeconds(3)
    do {
        $names = @(All-Named | ForEach-Object { try { $_.Current.Name } catch {} })
        if ($names -contains "Баланс Времени") { Click-Named "Закрыть"; Start-Sleep -Milliseconds 500; return }
        if ($names -contains "Чаты") { return }
        Start-Sleep -Milliseconds 300
    } while ((Get-Date) -lt $end)
}

function Click-Named([string]$Name, [int]$Timeout = 15) {
    if (@("Чаты", "Контакты", "Звонки", "Музыка", "Галерея", "Библиотека приложений") -contains $Name) { Leave-Wallet }
    # THE DRAWER STAYS ONE STROKE AWAY (iOS slot 0): while the panel's first slot says what stands in the way -- the banners refused,
    # the copy with contacts kept nowhere -- its right button opens the drawer, as the edge's stroke does
    if ($Name -eq "Библиотека приложений") {
        foreach ($alt in @("Хранить мою копию у собеседников", "Уведомления выключены")) {
            if ((All-Named | Where-Object { try { $_.Current.Name -eq $alt } catch { $false } } | Select-Object -First 1)) { RightClick-Named $alt; Start-Sleep -Milliseconds 400; return }
        }
    }
    # the key to the 24 words asks Windows Hello: never pressed by a check, only by tools\manual-hello.ps1 -Owner
    if (@("Сохранить 24 слова", "Save 24 words") -contains $Name -and $env:MONTANA_MANUAL_HELLO -ne "1") {
        throw "'$Name' asks Windows Hello: a manual check only (tools\manual-hello.ps1 -Owner)"
    }
    Find-Named $Name $Timeout | Out-Null   # waits until it is on screen
    $all = All-Named
    # every element of that name, the exact ones first: a label's text and its switch share the name, only one can be pressed
    $named = @($all | Where-Object { $_.Current.Name -eq $Name }) + @($all | Where-Object { $_.Current.Name -ne $Name -and $_.Current.Name -and $_.Current.Name.Contains($Name) })
    foreach ($e in $named) {
        $p = $null
        if ($e.TryGetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern, [ref]$p)) { $p.Toggle(); return }
        if ($e.TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern, [ref]$p)) { $p.Invoke(); return }
        # a tab of a strip (role tab) is chosen rather than pressed
        if ($e.TryGetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern, [ref]$p)) { $p.Select(); return }
        # a disclosure (aria-expanded) opens and closes rather than being pressed
        if ($e.TryGetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern, [ref]$p)) {
            if ($p.Current.ExpandCollapseState -eq [System.Windows.Automation.ExpandCollapseState]::Collapsed) { $p.Expand() } else { $p.Collapse() }
            return
        }
    }
    throw "'$Name' cannot be pressed"
}

# A button inside one element of the window, found by that element's name: a sheet's «Очистить» while a row of the same name
# stands under the sheet's shade
function Click-In([string]$Scope, [string]$Name, [int]$Timeout = 15) {
    Find-Named $Scope $Timeout | Out-Null
    $cond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty, $Name)
    $end = (Get-Date).AddSeconds($Timeout)
    do {
        # every element of exactly that name, case and all (a section's «КЕШ» is not the alert «Кеш»): the one holding the button
        foreach ($s in @(All-Named | Where-Object { $_.Current.Name -ceq $Scope })) {
            $b = $s.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $cond)
            if ($b) { $b.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke(); return }
        }
        Start-Sleep -Milliseconds 300
    } while ((Get-Date) -lt $end)
    throw "no '$Name' inside '$Scope'"
}

function Type-Into([string]$Name, [string]$Text, [int]$Timeout = 15) {
    # a field may stand in the tree a moment before it takes text: asked again until it does; of the elements of that name
    # (a section's head and its field may share it) the one that takes text, the exact names first
    $end = (Get-Date).AddSeconds($Timeout)
    do {
        Find-Named $Name $Timeout | Out-Null
        $all = All-Named
        try {
            $named = @($all | Where-Object { $_.Current.Name -eq $Name }) + @($all | Where-Object { $_.Current.Name -ne $Name -and $_.Current.Name -and $_.Current.Name.Contains($Name) })
            foreach ($e in $named) {
                $p = $null
                if ($e.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern, [ref]$p)) { $p.SetValue($Text); return }
            }
        } catch {}
        Start-Sleep -Milliseconds 300
    } while ((Get-Date) -lt $end)
    throw "'$Name' takes no text"
}

function Type-First-Field([string]$Text) {
    $c = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Edit)
    $e = (Root).FindFirst([System.Windows.Automation.TreeScope]::Descendants, $c)
    if (-not $e) { throw "no field on screen" }
    $p = $null
    if ($e.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern, [ref]$p)) { $p.SetValue($Text); return }
    throw "the field takes no text"
}

function Get-Texts {
    $all = All-Named
    $seen = @()
    foreach ($e in $all) { try { $n = $e.Current.Name; if ($n -and -not ($seen -contains $n)) { $seen += $n } } catch {} }
    $seen
}

# THE PAGE'S OWN TEXT (UI Automation's TextPattern of the web document): what a row shows under its name, which the tree's names
# leave out -- a row's words are its button's content
function Page-Text {
    $c = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Document)
    $doc = (Root).FindFirst([System.Windows.Automation.TreeScope]::Descendants, $c)
    $p = $null
    if ($doc -and $doc.TryGetCurrentPattern([System.Windows.Automation.TextPattern]::Pattern, [ref]$p)) { return $p.DocumentRange.GetText(-1) }
    ""
}
function Page-Says([string]$text, [int]$timeout = 15) {
    $end = (Get-Date).AddSeconds($timeout)
    do { if ((Page-Text).Contains($text)) { "  page says: $text"; return }; Start-Sleep -Milliseconds 500 } while ((Get-Date) -lt $end)
    throw "the page never says '$text'"
}

# THE FILES KEY STANDS IN THE OPEN ROW (iOS ChatInputBar: composeOpen): the folded row is opened by «Ещё» first, as a person does
function Files-Key {
    # the key by its exact name: a chat named «Файлы …» (a scene's group) holds the word too, and the folded row shows no key until «Ещё»
    $exact = { param($n) @(All-Named | Where-Object { try { $_.Current.Name -eq $n } catch { $false } }) | Select-Object -First 1 }
    # the chat just opened may not have drawn its row yet: the key or the row's «Ещё», whichever stands first (the row keeps its shape)
    $end = (Get-Date).AddSeconds(15)
    while (-not (& $exact "Файлы") -and -not (& $exact "Ещё") -and (Get-Date) -lt $end) { Start-Sleep -Milliseconds 300 }
    if (-not (& $exact "Файлы")) { Click-Named "Ещё"; Start-Sleep -Milliseconds 400 }
    $k = & $exact "Файлы"
    if (-not $k) { throw "no files key in the compose row" }
    $p = $null
    if ($k.TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern, [ref]$p)) { $p.Invoke() } else { Click-Named "Файлы" }
    Start-Sleep -Milliseconds 300
}

function Stop-Montana { if ($script:proc -and -not $script:proc.HasExited) { $script:proc.Kill() } }

Add-Type @"
using System; using System.Runtime.InteropServices;
public class MontanaWin {
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out Rect r);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int w, int hh, uint flags);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint flags);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, IntPtr pid);
  [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
  [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool attach);
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  public struct Rect { public int Left, Top, Right, Bottom; }
}
"@
Add-Type -AssemblyName System.Drawing
[MontanaWin]::SetProcessDPIAware() | Out-Null

# The window to the front (a chat says «read» only before the person's eyes), placed and sized in its own pixels
function Front-Montana([int]$X = -1, [int]$Y = 0, [int]$Width = 0, [int]$Height = 0) {
    $h = Handle
    if ([MontanaWin]::IsIconic($h)) { [MontanaWin]::ShowWindow($h, 9) | Out-Null }   # SW_RESTORE
    if ($X -ge 0) { [MontanaWin]::SetWindowPos($h, [IntPtr]::Zero, $X, $Y, $Width, $Height, 0x0004) | Out-Null }
    [MontanaWin]::SetForegroundWindow($h) | Out-Null
    if ([MontanaWin]::GetForegroundWindow() -ne $h) {
        # Windows lets the foreground move only from the thread that holds it: the input of this thread is joined to it a moment
        # (no key is pressed), and the window is brought forward -- a chat says «read» only before the person's eyes
        $fg = [MontanaWin]::GetWindowThreadProcessId([MontanaWin]::GetForegroundWindow(), [IntPtr]::Zero)
        $me = [MontanaWin]::GetCurrentThreadId()
        [MontanaWin]::AttachThreadInput($me, $fg, $true) | Out-Null
        [MontanaWin]::SetForegroundWindow($h) | Out-Null
        [MontanaWin]::BringWindowToTop($h) | Out-Null
        [MontanaWin]::AttachThreadInput($me, $fg, $false) | Out-Null
    }
    # the web view takes the keyboard as a click would give it: the first field, else the window
    $c = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Edit)
    try { $r = Root; $e = $r.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $c); if ($e) { $e.SetFocus() } else { $r.SetFocus() } } catch {}
    Start-Sleep -Milliseconds 400
}

# The window out of sight while the person works at the computer: placed beyond every screen, never activated -- it keeps
# working and UI Automation keeps reading and pressing it (a minimized web view is restored by the first press)
function Away-Montana {
    Add-Type -AssemblyName System.Windows.Forms
    $h = Handle
    if ([MontanaWin]::IsIconic($h)) { [MontanaWin]::ShowWindow($h, 4) | Out-Null }   # SW_SHOWNOACTIVATE
    $x = [System.Windows.Forms.SystemInformation]::VirtualScreen.Right + 200
    [MontanaWin]::SetWindowPos($h, [IntPtr]::Zero, $x, 0, 1200, 900, 0x0014) | Out-Null   # SWP_NOZORDER | SWP_NOACTIVATE
}

# The window's pixels as a person sees them: the window's own (PrintWindow, its full content), never the screen under it --
# a window another one covers, or one not yet shown, gives no stranger's pixels
function Shot-Montana([string]$Out) {
    Front-Montana
    # the web view presents its next frame first: right after a file dialog closed the window's pixels were still the old frame
    Start-Sleep -Milliseconds 400
    $h = Handle
    $r = New-Object MontanaWin+Rect; [MontanaWin]::GetWindowRect($h, [ref]$r) | Out-Null
    $bmp = New-Object System.Drawing.Bitmap ($r.Right - $r.Left), ($r.Bottom - $r.Top)
    $g = [System.Drawing.Graphics]::FromImage($bmp); $dc = $g.GetHdc()
    [MontanaWin]::PrintWindow($h, $dc, 2) | Out-Null   # PW_RENDERFULLCONTENT: the web view's composed pixels too
    $g.ReleaseHdc($dc); $g.Dispose()
    $bmp.Save($Out); $bmp.Dispose()
}

# The process the remote speaks to: one of several windows open at once
function Use-Montana($p) { $script:proc = $p }

# A MOVE BETWEEN THE PERSONS OF ONE COMPUTER starts the program again (iOS MTSeats): the window's process writes its id into
# <data>\front.pid, and the check follows it to the new window
function Follow-Montana([string]$DataDir, [int]$Timeout = 60) {
    $old = if ($script:proc) { $script:proc.Id } else { 0 }
    $file = Join-Path $DataDir "front.pid"
    for ($i = 0; $i -lt $Timeout * 4; $i++) {
        $n = 0
        if (Test-Path $file) { [int]::TryParse(([IO.File]::ReadAllText($file)).Trim(), [ref]$n) | Out-Null }
        if ($n -gt 0 -and $n -ne $old) {
            $p = Get-Process -Id $n -ErrorAction SilentlyContinue
            if ($p -and $p.MainWindowHandle -ne [IntPtr]::Zero) { $script:proc = $p; Start-Sleep -Milliseconds 800; return $p }
        }
        Start-Sleep -Milliseconds 250
    }
    throw "the program did not come back after the move"
}

Add-Type @"
using System; using System.Runtime.InteropServices;
public class MontanaMouse {
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, UIntPtr e);
}
"@

# a click of the mouse itself on the first element wearing that class, at a share of its width (a plate takes the finger, not a key)
function Click-Class([string]$class, [double]$at, [switch]$Last) {
    # the first of that class, or with -Last the last of them (a feed's newest) -- of those standing in sight when any does
    $all = @(All-Named | Where-Object { try { $_.Current.ClassName -split ' ' -contains $class } catch { $false } })
    $seen = @($all | Where-Object { try { -not $_.Current.IsOffscreen } catch { $false } })
    if ($seen.Count) { $all = $seen }
    $e = if ($Last) { $all | Select-Object -Last 1 } else { $all | Select-Object -First 1 }
    if (-not $e) {
        $root = [System.Windows.Automation.AutomationElement]::RootElement
        $c = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ClassNameProperty, $class)
        $e = $root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $c)
    }
    if (-not $e) { throw "nothing of class '$class' on screen" }
    $r = $e.Current.BoundingRectangle
    [MontanaMouse]::SetCursorPos([int]($r.X + $r.Width * $at), [int]($r.Y + $r.Height / 2)) | Out-Null
    Start-Sleep -Milliseconds 150
    [MontanaMouse]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero); [MontanaMouse]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 400
}

# A right click at the middle of the element of that name (a letter's menu, a row's menu): the mouse itself, as a person
# A PRESS HELD (iOS MontanaHoldControl): the left button down on the element's middle, held for the seconds given -- carried up by
# past 60 points to lock when asked -- then let go
function Hold-Named([string]$Name, [double]$Seconds = 2, [switch]$Lock, [int]$Timeout = 15) {
    $e = Find-Named $Name $Timeout
    Front-Montana
    $r = $e.Current.BoundingRectangle
    $x = [int]($r.X + $r.Width / 2); $y = [int]($r.Y + $r.Height / 2)
    [MontanaMouse]::SetCursorPos($x, $y) | Out-Null
    Start-Sleep -Milliseconds 150
    [MontanaMouse]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds ([int]($Seconds * 1000))
    # carried up past the lock's 60 points: screen pixels are points times the display's scale (150 % here), so 160 pixels
    if ($Lock) { for ($i = 1; $i -le 16; $i++) { [MontanaMouse]::SetCursorPos($x, $y - 10 * $i) | Out-Null; Start-Sleep -Milliseconds 25 } }
    [MontanaMouse]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 400
}

# THE MEDIA KEY TURNED TO A MODE (iOS: a tap turns microphone → camera → coin): tapped until it is the key named, a button by that
# very name -- never a letter whose name begins so
function Media-Mode([string]$Want) {
    $key = { param($n) All-Named | Where-Object { try { $_.Current.Name -eq $n -and $_.Current.ControlType.ProgrammaticName -eq "ControlType.Button" } catch { $false } } | Select-Object -First 1 }
    for ($i = 0; $i -lt 4; $i++) {
        if (& $key $Want) { return }
        foreach ($k in @("Голосовое сообщение", "Видеосообщение", "Монета")) {
            $e = & $key $k
            if ($e) { $e.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke(); Start-Sleep -Milliseconds 400; break }
        }
    }
    if (-not (& $key $Want)) { throw "the media key never turned to '$Want'" }
}

# THE DRAWER, WHATEVER THE FIRST SLOT SAYS (TopBar: «App Library», or what stands in the way -- «Keep my copy with my contacts»,
# «Notifications are off» -- whose right click still opens the drawer, iOS MontanaDrawerHost): a scene never depends on the hint
function Open-Drawer {
    foreach ($n in @("Библиотека приложений", "App Library")) { try { Click-Named $n 2; return } catch {} }
    foreach ($n in @("Хранить мою копию у собеседников", "Keep my copy with my contacts", "Уведомления выключены", "Notifications are off")) {
        try { RightClick-Named $n 2; return } catch {}
    }
    throw "nothing on screen opens the drawer"
}
function RightClick-Named([string]$Name, [int]$Timeout = 15) {
    $e = Find-Named $Name $Timeout
    Front-Montana
    # a letter above the feed's fold is brought into sight first: the mouse presses only what the eye sees
    try { $e.GetCurrentPattern([System.Windows.Automation.ScrollItemPattern]::Pattern).ScrollIntoView(); Start-Sleep -Milliseconds 400 } catch {}
    # a letter that just arrived still rises on the feed's spring (iOS MTLetterMotion): the hand waits until it stands still
    $r = $e.Current.BoundingRectangle
    for ($i = 0; $i -lt 20; $i++) { Start-Sleep -Milliseconds 120; $n = $e.Current.BoundingRectangle; if ($n -eq $r) { break }; $r = $n }
    [MontanaMouse]::SetCursorPos([int]($r.X + $r.Width / 2), [int]($r.Y + $r.Height / 2)) | Out-Null
    Start-Sleep -Milliseconds 150
    [MontanaMouse]::mouse_event(0x0008, 0, 0, 0, [UIntPtr]::Zero); [MontanaMouse]::mouse_event(0x0010, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 400
}

# The call screen's timer in seconds, or -1: read inside the call's own screen (its dialog «Аудиовызов Montana» or «Видеовызов
# Montana») -- after midnight an hour of the list reads «0:42» too
function Call-Timer {
    foreach ($kind in @("Аудиовызов Montana", "Видеовызов Montana")) {
        try {
            $d = @(All-Named | Where-Object { $_.Current.Name -eq $kind -and $_.Current.ControlType -ne [System.Windows.Automation.ControlType]::Text }) | Select-Object -First 1
            if (-not $d) { continue }
            $shown = @($d.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition) | ForEach-Object { $_.Current.Name } | Where-Object { $_ -match "^\d{1,2}:[0-5]\d$" })
            if ($shown) { return [int]($shown[0].Split(":")[0]) * 60 + [int]($shown[0].Split(":")[1]) }
        } catch {}
    }
    -1
}

# Waits until a letter just sent has left this machine: the feed holds no «Отправка…» on two reads in a row, after the row
# had its moment to stand (a window closed at once would take the letter's words with it until its next run)
function Sent-Settle([int]$Timeout = 40) {
    Start-Sleep -Seconds 3
    $end = (Get-Date).AddSeconds($Timeout)
    $calm = 0
    while ((Get-Date) -lt $end) {
        if ((Get-Texts) -contains "Отправка…") { $calm = 0 } else { $calm++ }
        if ($calm -ge 2) { return }
        Start-Sleep -Seconds 1
    }
    throw "a letter is still «Отправка…»"
}

# Presses the row of that name in a menu just opened (a confirmation): the menu is waited for, it may draw a moment later
function Press-MenuRow([string]$Name, [int]$Timeout = 6) {
    $cond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::MenuItem)
    $end = (Get-Date).AddSeconds($Timeout)
    do {
        $row = @((Root).FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond) | Where-Object { $_.Current.Name -eq $Name }) | Select-Object -First 1
        if ($row) { $row.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke(); return }
        Start-Sleep -Milliseconds 300
    } while ((Get-Date) -lt $end)
    throw "no confirmation row '$Name'"
}

# Waits until nothing of that name is on screen
function Gone-Named([string]$Name, [int]$Timeout = 60) {
    $end = (Get-Date).AddSeconds($Timeout)
    do {
        if (-not ((Get-Texts) -contains $Name)) { return }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $end)
    throw "'$Name' is still on screen"
}

Add-Type @"
using System; using System.Runtime.InteropServices; using System.Text;
public class MontanaDlg {
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr FindWindowEx(IntPtr parent, IntPtr after, string cls, string title);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr SendMessage(IntPtr h, uint msg, IntPtr w, string l);
  [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern IntPtr GetDlgItem(IntPtr dlg, int id);
}
"@

# The standard Open dialog a page's file field shows (class #32770, a child of the app's window): the file's full path set
# into «File name» (control 1148: ComboBoxEx32 > ComboBox > Edit) and «Open» (control 1) clicked -- the dialog's own
# controls, by their window messages, as Windows 11 shows them to UI Automation only as panes
function Pick-File([string]$Path, [int]$Timeout = 15) {
    $cls = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ClassNameProperty, "#32770")
    $end = (Get-Date).AddSeconds($Timeout); $dlg = $null
    do { $dlg = (Root).FindFirst([System.Windows.Automation.TreeScope]::Children, $cls); if (-not $dlg) { Start-Sleep -Milliseconds 300 } } while (-not $dlg -and (Get-Date) -lt $end)
    if (-not $dlg) { throw "no Open dialog" }
    Start-Sleep -Milliseconds 500
    $h = [IntPtr]$dlg.Current.NativeWindowHandle
    $combo = [MontanaDlg]::GetDlgItem($h, 1148)
    $edit = [MontanaDlg]::FindWindowEx([MontanaDlg]::FindWindowEx($combo, [IntPtr]::Zero, "ComboBox", $null), [IntPtr]::Zero, "Edit", $null)
    if ($edit -eq [IntPtr]::Zero) { $edit = [MontanaDlg]::FindWindowEx($combo, [IntPtr]::Zero, "Edit", $null) }
    if ($edit -eq [IntPtr]::Zero) { $edit = [MontanaDlg]::GetDlgItem($h, 1152) }   # the folder picker: its «Папка» box stands alone
    if ($edit -eq [IntPtr]::Zero) { throw "no file name box" }
    [MontanaDlg]::SendMessage($edit, 0x000C, [IntPtr]::Zero, $Path) | Out-Null   # WM_SETTEXT
    [MontanaDlg]::SendMessage([MontanaDlg]::GetDlgItem($h, 1), 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null   # BM_CLICK
    Start-Sleep -Milliseconds 800
}
