# A CARD BORN ON ONE DEVICE OPENS AN INTRODUCTION ON ANOTHER (D3, stage 3: iOS MontanaCard.twinLiveCards/takeTwin, the mirror's «TC:»;
# Windows card.rs live_cards/take_twin, Android MontanaCard.takeTwin): AliceTest's Windows shows its own permanent link -- a card born
# on that machine alone -- and its live cards ride to her Android by the mirror; Windows is then stopped. A new test person K scans
# that link on another Windows folder and writes a first letter: only the Android, holding the sibling's card, can open it.
# Test identities, test folders and the emulator only.
# usage: tools\twincard.ps1 -Root DIR   (-Root\P: Alice's Windows folder, made by tools\twin3.ps1)
param([Parameter(Mandatory = $true)][string]$Root)
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ui.ps1"
. "$PSScriptRoot\android.ps1" -Device emulator-5554
$stamp = Get-Date -Format "HHmmss"
$t0 = Get-Date
if (-not (Test-Path "$Root\P")) { throw "no Alice on Windows: run tools\twin3.ps1 with the same -Root first" }
function App-Up {
    Droid-Adb shell am force-stop $script:Package | Out-Null; Droid-Start
    $end = (Get-Date).AddSeconds(60)
    while (-not (Droid-Nodes | Where-Object { $_.Text -eq "Чаты" })) { if ((Get-Date) -gt $end) { throw "android: no chat list" }; Start-Sleep -Seconds 1 }
}

try {
    "Alice's Android up (its ear on the twin's pipe)"
    if (((Droid-Adb get-state) -join "") -notmatch "^device") { Droid-Up "MontanaA" }
    App-Up
    Start-Sleep -Seconds 6
    Droid-Adb logcat -c | Out-Null

    "Alice's Windows shows its own permanent link: its live cards ride to the Android"
    $script:proc = Start-Montana -DataDir "$Root\P"; Front-Montana -X 0 -Y 40 -Width 1100 -Height 900
    Start-Sleep -Seconds 4
    try { Click-Named "Не сейчас" 3 } catch {}
    Click-Named "Чаты"; Start-Sleep -Milliseconds 500
    Click-Named "Написать"; Click-Named "Мой код и ссылка"
    $end = (Get-Date).AddSeconds(20)
    do { $link = Get-Texts | Where-Object { $_ -like "https://montana.quest/perp/*" } | Select-Object -First 1; if (-not $link) { Start-Sleep -Milliseconds 500 } } while (-not $link -and (Get-Date) -lt $end)
    if (-not $link) { throw "Windows shows no permanent link" }
    "  the link shown (its card born on Windows alone)"
    $end = (Get-Date).AddSeconds(120)
    while (-not (@(Droid-Adb logcat -d -v time -s Montana:V) -match "rdv_twin|twin_lt taken")) { if ((Get-Date) -gt $end) { break }; Start-Sleep -Seconds 3 }
    Start-Sleep -Seconds 5
    @(Droid-Adb logcat -d -v time -s Montana:V | Where-Object { $_ -match "rdv_twin|twin_lt" }) | Select-Object -Last 6 | ForEach-Object { "  log: $_" }
    Stop-Montana; Start-Sleep -Seconds 1
    "  Windows stopped"

    "K, a new test person on another folder, scans Alice's link and writes"
    $script:proc = Start-Montana -DataDir "$Root\K$stamp"; Front-Montana -X 0 -Y 40 -Width 1100 -Height 900
    Click-Named "Продолжить с Montana"; Click-Named "Создать"; Click-Named "Готово"
    Click-Named "Я понимаю и беру ответственность на себя"; Click-Named "Показать слова"
    Find-Named "Ваша сид-фраза из 24 слов" | Out-Null; Start-Sleep -Milliseconds 300
    Click-Named "Я записал слова в надёжном месте"; Click-Named "Ваша личность в Montana"
    Find-Named "Готово" | Out-Null; Start-Sleep -Milliseconds 500
    Type-First-Field "Карта $stamp"; Click-Named "Готово"
    $end = (Get-Date).AddSeconds(20)
    do { $tx = Get-Texts; if ($tx -contains "Принимаю") { Click-Named "Принимаю"; break }; if ($tx -contains "Чаты") { break }; Start-Sleep -Milliseconds 400 } while ((Get-Date) -lt $end)
    Start-Sleep -Seconds 2
    try { Click-Named "Не сейчас" 3 } catch {}
    Click-Named "Написать"; Click-Named "Сканировать код"; Type-Into "Ссылка" $link; Click-Named "Открыть"
    Find-Named "Сообщение..." 30 | Out-Null
    $hello = "hi from K $stamp"
    Type-Into "Сообщение..." $hello; Click-Named "Отправить"
    Start-Sleep -Seconds 8

    "Alice's Android opens the introduction by the sibling's card"
    App-Up
    $end = (Get-Date).AddSeconds(240)
    while (-not (Droid-Nodes | Where-Object { $_.Text -like "*$hello*" -or $_.Text -like "*Карта $stamp*" })) {
        if ((Get-Date) -gt $end) { break }
        Start-Sleep -Seconds 5
    }
    @(Droid-Adb logcat -d -v time -s Montana:V | Where-Object { $_ -match "rdv|first|twin_" }) | Select-Object -Last 10 | ForEach-Object { "  log: $_" }
    if (-not (Droid-Nodes | Where-Object { $_.Text -like "*$hello*" -or $_.Text -like "*Карта $stamp*" })) { throw "the introduction by Windows's card did not open on Android" }
    "  K's introduction stands on Alice's Android"
    "done in $([int]((Get-Date) - $t0).TotalSeconds) s"
} finally {
    try { Stop-Montana } catch {}
    try { if (((Droid-Adb get-state) -join "") -match "^device") { Droid-Off "emulator-5554" } } catch {}
}
