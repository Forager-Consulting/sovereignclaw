#Requires -Version 5.1
<#
.SYNOPSIS
    Opens the castle gates: starts SovereignClaw and forwards the OpenClaw UI
    to http://localhost:18789.

.DESCRIPTION
    WSL stops the distro shortly after its last session exits, so this window
    IS the on switch: while it is open, the stack runs. Close it (Ctrl+C) and
    the castle goes quiet; run .\stop.ps1 to stop it immediately.

    The port-forward reconnects automatically if OpenClaw restarts (for
    example after an Argo CD sync). It binds to localhost only.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$DISTRO_NAME = 'sovereignclaw'

$exists = $false
try { $exists = ((wsl -d $DISTRO_NAME -- echo 'ok' 2>&1) -join '') -match 'ok' } catch { }
if (-not $exists) {
    Write-Host "ERROR: the '$DISTRO_NAME' WSL2 distro was not found. Run .\install.ps1 first." -ForegroundColor Red
    exit 1
}

Write-Host ''
Write-Host '  Open the gates! The court assembles, Majesty. This takes a minute or two after a reboot.' -ForegroundColor Magenta
Write-Host '  Keep this window open while you hold audience. Ctrl+C to close the gates.' -ForegroundColor Magenta
Write-Host ''

# The reconnect loop runs inside bash, not PowerShell: a PowerShell loop would
# survive Ctrl+C (it only kills the current wsl call). Here one Ctrl+C ends it all.
# rollout status follows pod replacements; `kubectl wait` on pods would keep
# waiting on a pod that a rollout already deleted.
# No double quotes inside: Windows PowerShell 5.1 mangles them when passing args to wsl.
wsl -d $DISTRO_NAME -- bash -c 'while true; do kubectl rollout status deployment/openclaw -n openclaw --timeout=900s >/dev/null && echo The throne room is open: http://localhost:18789 && kubectl port-forward svc/openclaw -n openclaw 18789:18789; echo The gate slipped its hinges. Rehanging it...; sleep 3; done'
Write-Host ''
Write-Host '  The gates are closed, Majesty. The castle will settle into slumber shortly.' -ForegroundColor Magenta
