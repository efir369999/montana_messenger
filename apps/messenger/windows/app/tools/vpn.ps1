# THE VPN WALL IN THE WINDOW (iOS NetworkTabView, MontanaVPNStore; after tools\ab.ps1 with the same -Root): A opens «ВПН стена» --
# the tunnel's power stands closed with the word why (the engine waits for the owner); A pastes a vless link and the server
# stands under «Добавлены вручную»; A pastes a plan's link served by this check itself on 127.0.0.1 (a base64 body of two
# links, the panel's title and counters in its headers, as the panels write them): the plan stands under its own title with its
# two servers, and the panel heard this computer's random device number (x-hwid). A renames a server, copies its link (the
# clipboard is given back after), narrows the page by the search, deletes the server and the plan. No server is dialled.
# usage: tools\vpn.ps1 -Root DIR [-Shots DIR]
param([Parameter(Mandatory = $true)][string]$Root, [string]$Shots = "")
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ui.ps1"
function Snap($name) { if ($Shots) { Shot-Montana (Join-Path $Shots "$name.png") } }
function Says([string]$text, [int]$timeout = 30) { Find-Named $text $timeout | Out-Null; "  sees: $text" }
$t0 = Get-Date

# THE PLAN'S PANEL, this check's own: one GET answered with a base64 body of two test links and the panel's headers
$port = Get-Random -Minimum 41000 -Maximum 48000
$heard = Join-Path $Root "vpn-panel.txt"
Remove-Item $heard -ErrorAction SilentlyContinue
$links = "vless://11111111-2222-3333-4444-555555555555@203.0.113.7:443?security=reality&pbk=A&sid=B&type=tcp#Plan One`n" +
         "trojan://pw@203.0.113.8:443?security=tls&sni=t.example#Plan Two"
$body = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($links))
$title = "base64:" + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("Тест-подписка"))
$stop = Join-Path $Root "vpn-panel.stop"
Remove-Item $stop -ErrorAction SilentlyContinue
$panel = Start-Job -ArgumentList $port, $body, $title, $heard, $stop -ScriptBlock {
    param($port, $body, $title, $heard, $stop)
    $l = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $port)
    $l.Start()
    # the panel answers until the check says stop (or five minutes pass): never a wait nobody ends
    $deadline = (Get-Date).AddMinutes(5)
    while ((Get-Date) -lt $deadline -and -not (Test-Path $stop)) {
        if (-not $l.Pending()) { Start-Sleep -Milliseconds 100; continue }
        $c = $l.AcceptTcpClient()
        $s = $c.GetStream()
        $buf = New-Object byte[] 8192
        $got = $s.Read($buf, 0, $buf.Length)
        [IO.File]::AppendAllText($heard, [Text.Encoding]::ASCII.GetString($buf, 0, $got))
        $b = [Text.Encoding]::ASCII.GetBytes($body)
        $head = "HTTP/1.1 200 OK`r`nContent-Type: text/plain`r`nprofile-title: $title`r`n" +
                "subscription-userinfo: upload=1048576; download=2097152; total=10737418240; expire=1830000000`r`n" +
                "Content-Length: $($b.Length)`r`nConnection: close`r`n`r`n"
        $h = [Text.Encoding]::ASCII.GetBytes($head)
        $s.Write($h, 0, $h.Length); $s.Write($b, 0, $b.Length); $s.Flush(); $c.Close()
    }
    $l.Stop()
}
$clip = try { Get-Clipboard -Raw } catch { $null }
try {
    $A = Start-Montana -DataDir "$Root\A"; Front-Montana -X 0 -Y 40 -Width 1500 -Height 950
    Start-Sleep -Seconds 2
    "A opens the VPN wall: the power stands closed, and says why"
    Open-Drawer; Click-Named "ВПН стена"
    Says "Подключить"
    Says "На Windows тоннелю нужен движок Xray" 10
    "a server's link by hand"
    Type-Into "Добавить сервер или подписку" "vless://aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee@192.0.2.3:443?flow=xtls-rprx-vision&type=tcp&security=reality&fp=safari&sni=www.example.com&pbk=PBK&sid=ab#Amsterdam Test"
    Click-Named "Добавить"
    Says "Добавлено серверов: 1"
    Says "Добавлены вручную"
    Says "Amsterdam Test"
    "a plan's link, served on this computer"
    Type-Into "Добавить сервер или подписку" "http://127.0.0.1:$port/sub/abc#Name"
    Click-Named "Добавить"
    Says "Подписка дала серверов: 2" 40
    Says "Тест-подписка"
    Says "Plan One"; Says "Plan Two"
    $req = Get-Content $heard -Raw -ErrorAction SilentlyContinue
    if ($req -notmatch "(?im)^x-hwid: [0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\s*$") { throw "the panel heard no device number" }
    if ($req -match "(?im)^x-hwid:.*(montana|windows)") { throw "the device number names something of this computer" }
    "  the panel heard a random device number (x-hwid) and a GET of /sub/abc, the name after # left off: $([bool]($req -match 'GET /sub/abc HTTP'))"
    Snap "117-A-vpn"
    "rename, copy the link, search, delete"
    Click-Named "Ещё: Amsterdam Test"; Click-Named "Переименовать"
    Type-Into "Переименовать" "Амстердам"; Click-Named "Готово"
    Says "Амстердам"
    Click-Named "Ещё: Амстердам"; Click-Named "Скопировать ссылку"
    Says "Скопировано" 10
    $copied = Get-Clipboard -Raw
    if ($copied -notlike "vless://aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee@192.0.2.3:443?*#%D0%90%D0%BC*") { throw "the copied link is not the server's: $copied" }
    "  the clipboard holds the server's own link, its new name in it"
    Type-Into "Поиск" "Plan Two"
    Start-Sleep -Milliseconds 800
    if (Get-Texts | Where-Object { $_ -eq "Plan One" }) { throw "the search left another server on the page" }
    Says "Plan Two"
    Type-Into "Поиск" ""
    Click-Named "Ещё: Амстердам"; Click-Named "Удалить"
    Gone-Named "Амстердам" 10
    Click-Named "Удалить: Тест-подписка"
    Gone-Named "Тест-подписка" 10
    Says "Серверов пока нет"
    "done in $([int]((Get-Date) - $t0).TotalSeconds) s"
} finally {
    if ($null -ne $clip) { try { Set-Clipboard -Value $clip } catch {} }
    New-Item -ItemType File -Force $stop | Out-Null
    Wait-Job $panel -Timeout 5 | Out-Null; Remove-Job $panel -Force -ErrorAction SilentlyContinue
    Stop-Montana
}
