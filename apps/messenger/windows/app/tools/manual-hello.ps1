# WINDOWS HELLO BEFORE THE 24 WORDS -- A MANUAL CHECK, with the person beside the computer (the owner's word 20.10.2026: no
# Hello, finger or PIN in automatic or background checks). After tools\ab.ps1 with the same -Root (its identity A is a
# throwaway one): A asks for the words in Settings, the real Windows Hello asks over the window and no word is drawn
# meanwhile; the person answers it, and the 24 words show. Never part of tools\all.ps1.
# usage: tools\manual-hello.ps1 -Root DIR -Owner
param([Parameter(Mandatory = $true)][string]$Root, [switch]$Owner)
$ErrorActionPreference = "Stop"
if (-not $Owner) { throw "a manual check: run it with -Owner, beside the computer, ready to answer Windows Hello" }
. "$PSScriptRoot\ui.ps1"
$env:MONTANA_MANUAL_HELLO = "1"
try {
    $A = Start-Montana -DataDir "$Root\A" -Person; Front-Montana -X 0 -Y 40 -Width 1500 -Height 950
    Open-Drawer; Click-Named "Настройки"; Click-Named "Сохранить 24 слова"
    # Windows Hello shows its own window over the app's
    $hello = $null
    for ($i = 0; $i -lt 40 -and -not $hello; $i++) {
        foreach ($w in (Root).FindAll([System.Windows.Automation.TreeScope]::Children, [System.Windows.Automation.Condition]::TrueCondition)) {
            if ($w.Current.ClassName -match "Credential Dialog Xaml Host" -or $w.Current.Name -match "Безопасность Windows|Windows Security") { $hello = $w }
        }
        if (-not $hello) { Start-Sleep -Milliseconds 300 }
    }
    if (-not $hello) { throw "Windows Hello did not ask" }
    "  Windows Hello asks: '$($hello.Current.Name)'"
    if ((Get-Texts) -match "^\d+\.$") { throw "words shown before the device confirmed the person" }
    "  no word on screen while Hello asks -- answer Windows Hello now (finger, face or PIN), 2 minutes"
    $deadline = (Get-Date).AddMinutes(2); $shown = 0
    while ($shown -lt 24 -and (Get-Date) -lt $deadline) { $shown = @((Get-Texts) -match "^\d+\.$").Count; Start-Sleep -Milliseconds 500 }
    if ($shown -lt 24) { throw "the 24 words did not show after Windows Hello" }
    "  the 24 words show after the person answered"
} finally {
    Remove-Item env:MONTANA_MANUAL_HELLO -ErrorAction SilentlyContinue
    Stop-Montana
}
