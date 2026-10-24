# THE PANES OF A PERSON'S PAGE, LIVE (iOS MTTabStrip, MontanaPeerInfoScreen.panes; after tools\ab.ps1, files.ps1, links.ps1 and
# coins.ps1 with the same -Root): A opens B's page; the strip stands under the page's rows with «Стена» chosen and B's wall under
# it; each tab shows its pane -- the picture B sent in «Медиа», the document in «Файлы», the link in «Ссылки», the coins moved with B
# in «Транзакции» -- or its own empty word with its glyph; a sideways stroke of the touchpad turns to the next pane. The item law (iOS
# MTProfileItem): the right button on the picture opens the letter's menu, «Выбрать» marks it and the bar stands, «Показать в чате»
# closes the page and opens the chat.
# usage: tools\panes.ps1 -Root DIR [-Shots DIR]
param([Parameter(Mandatory = $true)][string]$Root, [string]$Shots = "")
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ui.ps1"
function Snap($name) { if ($Shots) { Shot-Montana (Join-Path $Shots "$name.png") } }
function Says([string]$text, [int]$timeout = 30) { Find-Named $text $timeout | Out-Null; "  sees: $text" }
function Wrote([string]$line, [int]$timeout = 20) {
    $end = (Get-Date).AddSeconds($timeout)
    do { $hit = Get-Content "$Root\A\trace.log" -Encoding UTF8 -ErrorAction SilentlyContinue | Where-Object { $_ -like "*$line*" } | Select-Object -Last 1; if ($hit) { return }; Start-Sleep -Milliseconds 300 } while ((Get-Date) -lt $end)
    throw "A never wrote '$line'"
}
# a tab of the strip by its name: «Музыка» is also a slot of the main screen under the page
function Choose-Tab([string]$name) {
    $t = @(All-Named | Where-Object { try { $_.Current.ControlType -eq [System.Windows.Automation.ControlType]::TabItem -and $_.Current.Name -eq $name } catch { $false } }) | Select-Object -First 1
    if (-not $t) { throw "no tab '$name'" }
    $t.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select()
}
$env:MONTANA_TRACE = "1"
Remove-Item "$Root\A\trace.log" -ErrorAction SilentlyContinue
$t0 = Get-Date
$A = Start-Montana -DataDir "$Root\A"; Front-Montana -X 0 -Y 40 -Width 900 -Height 950
Start-Sleep -Seconds 2
"A opens B's page: the strip, «Стена» chosen, B's wall under it"
Click-Named "Контакты"; RightClick-Named "Борис Тест"
Says "Заблокировать" 30
$tabs = @(All-Named | Where-Object { try { $_.Current.ControlType -eq [System.Windows.Automation.ControlType]::TabItem } catch { $false } } | ForEach-Object { $_.Current.Name })
"  tabs: $($tabs -join ', ')"
if ($tabs.Count -ne 8) { throw "the strip holds $($tabs.Count) tabs, not 8" }
Snap "170-A-panes-wall"
# «Транзакции» may stand empty: from the time cut (23.10.2026, fold-6) the book mints nothing, and a fresh root's people hold no coins to move
$want = @{ "Медиа" = "Фото"; "Файлы" = ""; "Ссылки" = "github.com" }
$empty = @{ "Медиа" = "Общие фотографии появятся здесь"; "Видео" = "Общие видео появятся здесь"; "Файлы" = "Общие файлы появятся здесь";
            "Ссылки" = "Здесь появятся ссылки"; "Музыка" = "Здесь появится музыка"; "Голосовые" = "Общие голосовые сообщения появятся здесь";
            "Транзакции" = "Транзакций пока нет" }
$keys = @{ "Медиа" = "media"; "Видео" = "video"; "Файлы" = "files"; "Ссылки" = "links"; "Музыка" = "music"; "Голосовые" = "voice"; "Транзакции" = "transactions" }
foreach ($tab in @("Транзакции", "Медиа", "Видео", "Файлы", "Ссылки", "Музыка", "Голосовые")) {
    Choose-Tab $tab
    Wrote "peer pane $($keys[$tab])"
    Start-Sleep -Milliseconds 1500
    $texts = @(Get-Texts)
    $isEmpty = $texts -contains $empty[$tab]
    $rows = @(All-Named | Where-Object { try { $_.Current.ControlType -eq [System.Windows.Automation.ControlType]::Button -and $_.Current.ClassName -eq "" } catch { $false } }).Count
    "  ${tab}: $(if ($isEmpty) { 'empty -- ' + $empty[$tab] } else { 'holds items' })"
    if ($want.ContainsKey($tab) -and $isEmpty) { throw "«$tab» stands empty, though the root's scenes put something there" }
    if ($want[$tab] -and -not ($texts | Where-Object { $_ -like "*$($want[$tab])*" }) -and -not (All-Named | Where-Object { try { $_.Current.Name -like "*$($want[$tab])*" } catch { $false } })) { throw "«$tab» does not show $($want[$tab])" }
    Snap "171-A-pane-$($keys[$tab])"
}
"A opens the picture of «Медиа» in the viewer and closes it"
Choose-Tab "Медиа"; Wrote "peer pane media"; Start-Sleep -Milliseconds 800
Click-Named "Фото"
Says "Закрыть" 10
Snap "172-A-pane-photo"
Click-Named "Закрыть"
function Marked([string]$name) {
    $e = Find-Named $name 5; $p = $null
    $e.TryGetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern, [ref]$p) -and $p.Current.ToggleState -eq [System.Windows.Automation.ToggleState]::On
}
"The item law (iOS MTProfileItem): the right button opens the letter's menu; «Выбрать» marks it, a click takes it out, the cross ends it"
RightClick-Named "Фото"
Says "Показать в чате" 5
Snap "173-A-pane-menu"
Click-Named "Выбрать"
if (-not (Marked "Фото")) { throw "the picture is not marked" }
"  the picture marked; the bar stands"
Snap "174-A-pane-selecting"
Click-Named "Фото"
if (Marked "Фото") { throw "a click while choosing left the mark" }
"  a click took it out"
Click-Named "Отмена"
"«Показать в чате»: the page closes, the chat opens at the picture"
RightClick-Named "Фото"
Click-Named "Показать в чате"
Says "Сообщение..." 15
Gone-Named "Заблокировать" 10
"  the chat stands, the page is gone"
Snap "175-A-shown-in-chat"
"done in $([int]((Get-Date) - $t0).TotalSeconds) s"
Stop-Montana
