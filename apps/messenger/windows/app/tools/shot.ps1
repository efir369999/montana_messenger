# The built Montana window, started, photographed as it is on screen, and closed: tools\shot.ps1 OUT.png
# The window's own pixels (DPI-aware), so what the picture shows is what a person sees.
param([Parameter(Mandatory = $true)][string]$Out, [string]$Exe = "$PSScriptRoot\..\..\target\release\montana-desktop.exe", [int]$Wait = 3,
      [int]$Width = 0, [int]$Height = 0)   # a size in the window's own pixels, or as it opens
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System; using System.Runtime.InteropServices;
public class MontanaShot {
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out Rect r);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int w, int hh, uint flags);
  public struct Rect { public int Left, Top, Right, Bottom; }
}
"@
[MontanaShot]::SetProcessDPIAware() | Out-Null
$p = Start-Process -FilePath $Exe -PassThru
$h = [IntPtr]::Zero
for ($i = 0; $i -lt 40 -and $h -eq [IntPtr]::Zero; $i++) { Start-Sleep -Milliseconds 500; $p.Refresh(); $h = $p.MainWindowHandle }
if ($h -eq [IntPtr]::Zero) { Stop-Process -Id $p.Id -ErrorAction SilentlyContinue; throw "no window" }
if ($Width -gt 0) { [MontanaShot]::SetWindowPos($h, [IntPtr]::Zero, 100, 100, $Width, $Height, 0x0004) | Out-Null }   # SWP_NOZORDER
Start-Sleep -Seconds $Wait
[MontanaShot]::SetForegroundWindow($h) | Out-Null; Start-Sleep -Milliseconds 800
$r = New-Object MontanaShot+Rect; [MontanaShot]::GetWindowRect($h, [ref]$r) | Out-Null
$bmp = New-Object System.Drawing.Bitmap ($r.Right - $r.Left), ($r.Bottom - $r.Top)
[System.Drawing.Graphics]::FromImage($bmp).CopyFromScreen($r.Left, $r.Top, 0, 0, $bmp.Size)
$bmp.Save($Out)
"window $($bmp.Width)x$($bmp.Height) '$($p.MainWindowTitle)' -> $Out"
Stop-Process -Id $p.Id
