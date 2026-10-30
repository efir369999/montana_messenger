# THE PERSON LEAVES AND NOTHING OF THEIRS WAITS FOR THE NEXT ONE (forgotten.rs; iOS SeedScope.forget, MTCoinPlace.setAside): A is
# born on a fresh folder and writes a note to itself; A deletes the account -- the program starts again, the first screen stands,
# A's words, book and secrets are gone from the folder, A's coin book, archive and files wait aside under Forgotten\, the settings
# stay; B is born in the same folder and sees nothing of A; B leaves too, and A comes back by the same words: A's archive, set
# aside under A's words, is A's again (iOS keeps it sealed under the words), B's stays aside untouched.
# usage: tools\leave.ps1 -Root DIR [-Shots DIR]
param([Parameter(Mandatory = $true)][string]$Root, [string]$Shots = "")
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ui.ps1"
if (Test-Path $Root) { Remove-Item -Recurse -Force $Root }
if ($Shots) { New-Item -ItemType Directory -Force $Shots | Out-Null }
function Snap($name) { if ($Shots) { Shot-Montana (Join-Path $Shots "$name.png") } }
function Says([string]$text, [int]$timeout = 60) { Find-Named $text $timeout | Out-Null; "  sees: $text" }
# the grid's words, read into this check's memory only (never a file, a log or a shot)
function Grid-Words {
    $w = New-Object string[] 24; $n = $null
    foreach ($e in (All-Named)) {
        $s = $e.Current.Name
        if ($s -match '^(\d{1,2})\.?$' -and [int]$Matches[1] -ge 1 -and [int]$Matches[1] -le 24) { $n = [int]$Matches[1]; continue }
        if ($s -eq ".") { continue }
        if ($n -and $s -match '^[a-z]{3,8}$') { $w[$n - 1] = $s }
        $n = $null
    }
    if (@($w | Where-Object { $_ }).Count -ne 24) { throw "the grid gave $(@($w | Where-Object { $_ }).Count) of 24 words" }
    $w
}
function Born([string]$name) {
    Click-Named "Продолжить с Montana"; Click-Named "Создать"; Click-Named "Готово"
    Click-Named "Я понимаю и беру ответственность на себя"; Click-Named "Показать слова"
    Find-Named "Ваша сид-фраза из 24 слов" | Out-Null; Start-Sleep -Milliseconds 300
    $script:words = Grid-Words
    Click-Named "Я записал слова в надёжном месте"; Click-Named "Ваша личность в Montana"
    Find-Named "Готово" | Out-Null; Start-Sleep -Milliseconds 500
    Type-First-Field $name; Click-Named "Готово"
    $end = (Get-Date).AddSeconds(20)
    do { $tx = Get-Texts; if ($tx -contains "Принимаю") { Click-Named "Принимаю"; break }; if ($tx -contains "Чаты") { break }; Start-Sleep -Milliseconds 400 } while ((Get-Date) -lt $end)
}
$t0 = Get-Date
$note = "Заметка уходящего " + (Get-Random -Maximum 99999)
$dir = "$Root\A"

"A: born, a note to itself"
$A = Start-Montana -DataDir $dir; Front-Montana -X 0 -Y 40 -Width 900 -Height 900
Born "Алиса Уходит"
$wordsA = $script:words
Click-Named "Избранное"; Type-Into "Сообщение..." $note; Click-Named "Отправить"; Start-Sleep -Milliseconds 700
try { Click-Named "Назад" 3 } catch {}
Page-Says $note
if (-not (Test-Path "$dir\vault\mt_active_mnemonic.sealed")) { throw "A's words are not where the check looks for them" }

"A deletes the account: the program starts again on the first screen"
# the window's browser data is A's (storage, cookies, cache: the owner's word 25.10.2026): a mark laid in it must not outlive A
$mark = "$dir\EBWebView\leave-mark-of-A.txt"
if (Test-Path "$dir\EBWebView") { Set-Content -Path $mark -Value "A" } else { $mark = $null }
Open-Drawer; Click-Named "Настройки"; Click-Named "Приватность"
Click-Named "Удалить аккаунт"; Start-Sleep -Milliseconds 500
Click-In "Удалить аккаунт?" "Удалить аккаунт"
Follow-Montana $dir 60 | Out-Null
Says "Продолжить с Montana" 30
Snap "leave-1-first-screen"

"the folder: A's words, book and secrets gone; the coin book, the archive and the files aside; the settings stay"
foreach ($k in @("mt_active_mnemonic", "pipeSecrets", "chats", "draftsMap", "mt.twin.ref", "passwords", "vpnBook", "blobKeySeed")) {
    if (Test-Path "$dir\vault\$k.sealed") { throw "$k stayed in the folder" }
}
if (-not $mark) { throw "A's window kept no browser data where the check looks ($dir\EBWebView)" }
if (Test-Path $mark) { throw "A's browser data stayed for the next person" }
"  A's browser data gone (the window's folder is the next person's, fresh)"
$aside = Get-ChildItem "$dir\Forgotten" -Directory | Select-Object -First 1
if (-not $aside) { throw "nothing was set aside" }
"  aside: Forgotten\$($aside.Name) -- " + ((Get-ChildItem $aside.FullName -Recurse -File | Measure-Object).Count) + " files"
if (-not (Test-Path "$($aside.FullName)\archive")) { throw "A's archive is not aside" }
if (Test-Path "$($aside.FullName)\vault\passwords.sealed") { throw "A's passwords were set aside, not deleted" }
# the next person's program lays an empty store again at its start: none of A's files may be in it
if (Test-Path "$dir\media") { if (@(Get-ChildItem "$dir\media" -Recurse -File).Count) { throw "A's files stayed in the folder" } }
if (Test-Path "$dir\archive") { throw "A's archive stayed in the folder" }
$s = Get-Content "$dir\settings.json" -Raw -Encoding UTF8 | ConvertFrom-Json
if ($s.userName) { throw "A's name stayed in the settings" }
if (Test-Path "$dir\forget.pending") { throw "the mark stayed" }

"B: born in the same folder, sees nothing of A"
Born "Борис Новый"
Says "Избранное" 30
Click-Named "Избранное"; Start-Sleep -Seconds 2
if ((Page-Text).Contains($note)) { throw "B sees A's note" }
"  B's Saved Messages holds nothing of A"
Snap "leave-2-B"

"B leaves too; A comes back by the same words on this computer: A's archive, set aside under A's words, comes back -- B's stays aside"
Open-Drawer; Click-Named "Настройки"; Click-Named "Приватность"
Click-Named "Удалить аккаунт"; Start-Sleep -Milliseconds 500
Click-In "Удалить аккаунт?" "Удалить аккаунт"
Follow-Montana $dir 60 | Out-Null
Says "Продолжить с Montana" 30
if (@(Get-ChildItem "$dir\Forgotten" -Directory).Count -ne 2) { throw "two people left: two places aside" }
Click-Named "Продолжить с Montana"; Click-Named "Открыть личность"
$end = (Get-Date).AddSeconds(15)
while ($true) { try { Type-First-Field ($wordsA -join " "); break } catch { if ((Get-Date) -gt $end) { throw }; Start-Sleep -Milliseconds 300 } }
$wordsA = $null; $script:words = $null
Click-Named "Восстановить"
$end = (Get-Date).AddSeconds(60)
do { $tx = Get-Texts; if ($tx -contains "Принимаю") { Click-Named "Принимаю"; break }; if ($tx -contains "Чаты") { break }; Start-Sleep -Milliseconds 500 } while ((Get-Date) -lt $end)
Page-Says $note 60
"  A's note came back to A"
if (@(Get-ChildItem "$dir\Forgotten" -Directory).Count -ne 1) { throw "B's place aside was touched, or A's was not let go" }
"  B's place aside stays as it lies"
Snap "leave-3-A-again"
"done in $([int]((Get-Date) - $t0).TotalSeconds) s"
Stop-Montana
