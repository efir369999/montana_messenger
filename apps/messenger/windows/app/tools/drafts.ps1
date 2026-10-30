# THE UNSENT WORDS (after tools\ab.ps1 with the same -Root): A writes words in B's chat and leaves them unsent; the list shows
# «Черновик:» and the words under B's name; the chat opens with them in the field; they live through a restart; sent, they
# become the letter and leave the row (iOS ChatStore.setDraft, ChatRow's draft).
# usage: tools\drafts.ps1 -Root DIR [-Shots DIR]
param([Parameter(Mandatory = $true)][string]$Root, [string]$Shots = "")
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ui.ps1"
function Snap($name) { if ($Shots) { Shot-Montana (Join-Path $Shots "$name.png") } }
function Says([string]$text, [int]$timeout = 15) { Find-Named $text $timeout | Out-Null; "  sees: $text" }
function Field([string]$name) {
    $e = Find-Named $name 10; $p = $null
    if ($e.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern, [ref]$p)) { return $p.Current.Value }
    ""
}
$words = "Слова без отправки " + (Get-Random -Maximum 9999)
$A = Start-Montana -DataDir "$Root\A"; Front-Montana -X 0 -Y 40 -Width 900 -Height 900   # narrow: the chat over the list
Start-Sleep -Seconds 2
"A: words in B's field, left unsent"
Click-Named "Борис Тест"
Type-Into "Сообщение..." $words
Start-Sleep -Seconds 1
Click-Named "Назад"
Page-Says "Черновик: $words"
Snap "drafts-1-row"
"A: the chat opens with them"
Click-Named "Борис Тест"
$v = Field "Сообщение..."
if ($v -ne $words) { throw "the field holds '$v'" }
"  field: $v"
Click-Named "Назад"
"A: through a restart"
Stop-Montana
$A = Start-Montana -DataDir "$Root\A"; Front-Montana -X 0 -Y 40 -Width 900 -Height 900
Start-Sleep -Seconds 2
Page-Says "Черновик: $words" 20
"A: sent, they leave the row"
Click-Named "Борис Тест"
Click-Named "Отправить"
Start-Sleep -Seconds 1
Click-Named "Назад"
Page-Says $words
if ((Page-Text).Contains("Черновик: $words")) { throw "the draft stayed after the letter left" }
Snap "drafts-2-sent"
"done"
Stop-Montana
