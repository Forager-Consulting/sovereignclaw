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

while ($true) {
    # rollout status follows pod replacements; `kubectl wait` on pods would keep
    # waiting on a pod that a rollout already deleted.
    wsl -d $DISTRO_NAME -- bash -c 'kubectl rollout status deployment/openclaw -n openclaw --timeout=900s >/dev/null && echo "    The throne room is open: http://localhost:18789" && kubectl port-forward svc/openclaw -n openclaw 18789:18789'
    Write-Host '    The gate slipped its hinges (OpenClaw restarted?). Rehanging it...' -ForegroundColor Yellow
    Start-Sleep -Seconds 3
}
