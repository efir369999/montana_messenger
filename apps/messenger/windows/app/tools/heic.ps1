# A HEIC FROM AN IPHONE, LIVE (iOS: a photo of the camera roll, a sticker with its transparency; after tools\ab.ps1 with the
# same -Root): the check writes a HEIC of its own through Windows' own imaging (WinRT BitmapEncoder, the HEIF extension);
# WebView2 does not open HEIF, so the window asks Windows for its PNG. B picks it in the Open dialog with a caption: it goes
# as iOS sends a photo -- JPEG, its long side at most 1600 (B's diary: «media send img jpg from heif») -- and A draws it at
# its own 640x400. Then B makes a sticker of the same HEIC: it joins B's set.
# usage: tools\heic.ps1 -Root DIR [-Shots DIR]
param([Parameter(Mandatory = $true)][string]$Root, [string]$Shots = "")
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ui.ps1"
function Snap($name) { if ($Shots) { Shot-Montana (Join-Path $Shots "$name.png") } }
function Says([string]$text, [int]$timeout = 60) { Find-Named $text $timeout | Out-Null; "  sees: $text" }
function Wrote([string]$who, [string]$line, [int]$timeout = 20) {
    $end = (Get-Date).AddSeconds($timeout)
    do { $hit = Get-Content "$Root\$who\trace.log" -Encoding UTF8 -ErrorAction SilentlyContinue | Where-Object { $_ -like "*$line*" } | Select-Object -Last 1; if ($hit) { "  ${who}: $($hit -replace '^\d+ ', '')"; return }; Start-Sleep -Milliseconds 500 } while ((Get-Date) -lt $end)
    throw "$who never wrote '$line'"
}
# the HEIC: 640x400, two gradients, written by WinRT's HEIF encoder (nothing of this computer's own photos is touched)
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$null = [Windows.Graphics.Imaging.BitmapEncoder, Windows.Graphics.Imaging, ContentType = WindowsRuntime]
$null = [Windows.Storage.Streams.InMemoryRandomAccessStream, Windows.Storage.Streams, ContentType = WindowsRuntime]
$asTaskOp = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq "AsTask" -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' } | Select-Object -First 1
$asTaskAct = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq "AsTask" -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq "IAsyncAction" } | Select-Object -First 1
function Await($op, [type]$t) { $task = $asTaskOp.MakeGenericMethod($t).Invoke($null, @($op)); $task.Wait(-1) | Out-Null; $task.Result }
function AwaitAction($a) { $task = $asTaskAct.Invoke($null, @($a)); $task.Wait(-1) | Out-Null }
$w = 640; $h = 400; $px = New-Object byte[] ($w * $h * 4)
for ($y = 0; $y -lt $h; $y++) { for ($x = 0; $x -lt $w; $x++) { $i = 4 * ($y * $w + $x); $px[$i] = [byte]($x * 255 / $w); $px[$i + 1] = [byte]($y * 255 / $h); $px[$i + 2] = 180; $px[$i + 3] = 255 } }
$ms = New-Object Windows.Storage.Streams.InMemoryRandomAccessStream
$enc = Await ([Windows.Graphics.Imaging.BitmapEncoder]::CreateAsync([Windows.Graphics.Imaging.BitmapEncoder]::HeifEncoderId, $ms)) ([Windows.Graphics.Imaging.BitmapEncoder])
$enc.SetPixelData([Windows.Graphics.Imaging.BitmapPixelFormat]::Bgra8, [Windows.Graphics.Imaging.BitmapAlphaMode]::Ignore, $w, $h, 96, 96, $px)
AwaitAction ($enc.FlushAsync())
$mem = New-Object IO.MemoryStream; [System.IO.WindowsRuntimeStreamExtensions]::AsStreamForRead($ms.GetInputStreamAt(0)).CopyTo($mem)
$heic = Join-Path $Root "iphone-photo.heic"; [IO.File]::WriteAllBytes($heic, $mem.ToArray())
$brand = [Text.Encoding]::ASCII.GetString($mem.ToArray(), 4, 8)
if ($brand -ne "ftypheic") { throw "not a HEIC: $brand" }
"the HEIC: $($mem.Length) bytes, $brand"
$env:MONTANA_TRACE = "1"
Remove-Item "$Root\A\trace.log", "$Root\B\trace.log" -ErrorAction SilentlyContinue
$t0 = Get-Date

$A = Start-Montana -DataDir "$Root\A"; Front-Montana -X 0 -Y 40 -Width 900 -Height 900
$B = Start-Montana -DataDir "$Root\B"; Front-Montana -X 920 -Y 40 -Width 900 -Height 900
"B picks the HEIC with a caption"
Click-Named "Алиса Тест"
Type-Into "Сообщение..." "Фото HEIC с iPhone"
Files-Key; Pick-File $heic
Wrote "B" "media send img jpg from heif" 20
Says "Фото HEIC с iPhone"
Sent-Settle 90
Snap "140-B-heic"

"A draws it"
Use-Montana $A; Front-Montana
Click-Named "Борис Тест"
Says "Фото HEIC с iPhone" 90
Wrote "A" "media shows img jpg 640x400" 60
Snap "141-A-heic"

"B makes a sticker of the HEIC"
Use-Montana $B; Front-Montana
Click-Named "Эмодзи"; Click-Named "Стикеры"
Says "Мои стикеры" 10
$before = @(Get-Texts | Where-Object { $_ -like "Мой стикер *" }).Count
Click-Named "Добавить стикер"; Pick-File $heic
$end = (Get-Date).AddSeconds(15)
while ((Get-Date) -lt $end -and @(Get-Texts | Where-Object { $_ -like "Мой стикер *" }).Count -le $before) { Start-Sleep -Milliseconds 500 }
if (@(Get-Texts | Where-Object { $_ -like "Мой стикер *" }).Count -le $before) { throw "the HEIC sticker never joined B's set" }
"  B: the set holds it"
Snap "142-B-heic-sticker"
Remove-Item $heic -ErrorAction SilentlyContinue
"done in $([int]((Get-Date) - $t0).TotalSeconds) s"
Use-Montana $A; Stop-Montana; Use-Montana $B; Stop-Montana
