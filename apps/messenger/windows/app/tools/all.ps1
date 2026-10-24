# EVERY LIVE SCENARIO IN TURN, from two fresh throw-away identities: the meeting and the letters (ab), the letter's menu
# (deeds), files (files), the pages (pages), the row's menu (rows), presence, blocking, forward and search. Each runs in a
# process of its own with a deadline; the summary says which passed.
# usage: tools\all.ps1 -Root DIR [-Shots DIR] [-Only step,step]   (-Only: those steps alone, in the run's own order)
param([Parameter(Mandatory = $true)][string]$Root, [string]$Shots = "", [string[]]$Only = @())
$results = @()
foreach ($step in @("ab", "deeds", "files", "album", "pages", "rows", "drafts", "savedpick", "presence", "blocks", "forward", "select", "links", "groups", "gtyping", "folders", "gface", "glink", "grights", "channel", "ccomments", "rename", "look", "qr", "chess", "chesscpu", "room", "calls", "callbreak", "callrebuild", "callroute", "callgrow", "callshare", "callvideo", "roomvideo", "roomlive", "callrevive", "keeping", "filter", "note", "voice", "gif", "card", "stickers", "callrecord", "gfiles", "roomrecord", "callsign", "passwords", "ground", "callsecond", "wall", "coins", "coinhold", "panes", "fabric", "coinreact", "flow", "core", "homenode", "squeeze", "datapage", "walletlook", "seedbook", "seatsend", "seats", "vpn", "callflip", "callslog", "p2p", "music", "heic", "library", "bigfile")) {
    if ($Only.Count -and $Only -notcontains $step) { continue }
    $t0 = Get-Date
    $out = Join-Path $env:TEMP "montana-$step.out"; $err = Join-Path $env:TEMP "montana-$step.err"
    # the seed's book on another device of the words is born on folders of its own (it clears its root)
    $args = @("-NoProfile", "-STA", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $PSScriptRoot "$step.ps1"), "-Root", $(if ($step -eq "seedbook") { "$Root-seed" } elseif ($step -eq "seatsend") { "$Root-seat" } else { $Root }))
    if ($Shots) { $args += @("-Shots", $Shots) }
    $p = Start-Process powershell -ArgumentList $args -RedirectStandardOutput $out -RedirectStandardError $err -PassThru
    $ok = $p.WaitForExit($(if ($step -eq "bigfile") { 2700000 } elseif ($step -eq "seedbook" -or $step -eq "seatsend") { 480000 } else { 300000 }))   # a big file rides the network for minutes; the seed's book waits for its minutes
    if (-not $ok) { $p.Kill() }
    Get-Process montana-desktop -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "C:\project\Montana\Montana-Windows\*target\release\*" } | Stop-Process -Force
    $failed = (-not $ok) -or ((Get-Content $err -ErrorAction SilentlyContinue) -match "Exception|throw|nothing named|still on screen")
    $s = [int]((Get-Date) - $t0).TotalSeconds
    $results += "{0,-9} {1} {2,4} s" -f $step, $(if ($failed) { "FAILED" } else { "passed" }), $s
    if ($failed) { Get-Content $err -ErrorAction SilentlyContinue | Select-Object -First 3 | ForEach-Object { $results += "          $_" } }
}
$results
