# PASSWORDS, IN THE WINDOWS (after tools\ab.ps1 with the same -Root). No check calls Windows Hello (the owner's word 20.10.2026):
# the windows run with MONTANA_NO_HELLO, so the passwords are refused at once -- what is checked here is that nothing of them
# opens without it. A opens «Пароли» -- the page stays locked and says the passwords did not open; B sends A a secret the way iOS
# writes one («🔑 title» and the machine line with the coded secret): on both sides only its title stands -- never the password,
# never the machine line -- and A's «Сохранить в Пароли» is refused without Windows Hello. Saving, codes and sharing with the
# real Windows Hello: tools\manual-hello.ps1 and docs\IPHONE-CHECK.md (manual).
# usage: tools\passwords.ps1 -Root DIR [-Shots DIR]
param([Parameter(Mandatory = $true)][string]$Root, [string]$Shots = "")
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ui.ps1"
function Snap($name) { if ($Shots) { Shot-Montana (Join-Path $Shots "$name.png") } }
function Says([string]$text, [int]$timeout = 60) { Find-Named $text $timeout | Out-Null; "  sees: $text" }
$stamp = Get-Date -Format "HHmmss"
$title = "Почта $stamp"
$secret = "S3cret-$stamp"
$json = '{"id":"","kind":"login","title":"' + $title + '","site":"mail.example","login":"alice","password":"' + $secret + '","otp":"","note":"","at":1760943600.5}'
$code = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json)).Replace("+", "-").Replace("/", "_")
$letter = "🔑 $title`nmontana://secret/1/$code"
$t0 = Get-Date
$B = Start-Montana -DataDir "$Root\B"; Front-Montana -X 920 -Y 40 -Width 900 -Height 900
Start-Sleep -Seconds 2
$A = Start-Montana -DataDir "$Root\A"; Front-Montana -X 0 -Y 40 -Width 900 -Height 900
Start-Sleep -Seconds 2
"A: the passwords stay locked without Windows Hello"
Open-Drawer; Click-Named "Пароли"
Says "Пароли не открылись" 15
if ((Get-Texts) -contains "Паролей пока нет") { throw "the passwords opened without Windows Hello" }
Snap "97-A-locked"
"B sends A a secret as iOS writes it"
Use-Montana $B; Front-Montana
Click-Named "Алиса Тест"
Type-Into "Сообщение..." $letter; Click-Named "Отправить"
Sent-Settle
Says "🔑 $title" 10
if ((Get-Texts) | Where-Object { $_ -like "*montana://secret*" -or $_ -like "*$secret*" }) { throw "B's own feed shows the secret's machine line" }
"A: only the title stands; saving needs Windows Hello"
Use-Montana $A; Front-Montana
Click-Named "Чаты"
Click-Named "Борис Тест" 30
Says "🔑 $title" 90
Says "Сохранить в Пароли" 10
if ((Get-Texts) | Where-Object { $_ -like "*montana://secret*" -or $_ -like "*$secret*" -or $_ -like "*$code*" }) { throw "A's feed shows the secret" }
Click-Named "Сохранить в Пароли"
Says "Пароли не открылись" 15
Snap "98-A-secret"
"done in $([int]((Get-Date) - $t0).TotalSeconds) s"
Use-Montana $A; Stop-Montana; Use-Montana $B; Stop-Montana
