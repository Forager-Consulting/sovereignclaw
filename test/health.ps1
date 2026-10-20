#Requires -Version 5.1
<#
.SYNOPSIS
    Inspects the castle: verifies SovereignClaw is healthy. Observe only;
    nothing is written to the cluster or the distro.

.NOTES
    Starting the check boots the distro if it is stopped; it then idles out
    on its own unless .\start.ps1 is running.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$DISTRO_NAME = 'sovereignclaw'

Write-Host ''
Write-Host '  An inspection of the castle, Majesty? At once.' -ForegroundColor Magenta

$fail = 0
try { wsl --status 2>&1 | Out-Null; Write-Host '  [PASS] WSL2 available' -ForegroundColor Green }
catch { Write-Host '  [FAIL] WSL2 not available -> wsl --install' -ForegroundColor Red; $fail++ }

$exists = $false
try { $exists = ((wsl -d $DISTRO_NAME -- echo 'ok' 2>&1) -join '') -match 'ok' } catch { }
if (-not $exists) {
    Write-Host "  [FAIL] '$DISTRO_NAME' distro not found -> .\install.ps1" -ForegroundColor Red
    exit 1
}
Write-Host "  [PASS] '$DISTRO_NAME' distro is reachable" -ForegroundColor Green

Get-Content -Raw "$PSScriptRoot\health-inner.sh" | wsl -d $DISTRO_NAME -- bash -s
if ($LASTEXITCODE -ne 0) { $fail++ }

Write-Host ''
if ($fail -eq 0) {
    Write-Host '  The realm is in excellent order, Majesty.' -ForegroundColor Magenta
} else {
    Write-Host '  Majesty, I regret to report irregularities. See the [FAIL] lines above.' -ForegroundColor Red
    exit 1
}
