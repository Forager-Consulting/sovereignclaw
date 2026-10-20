#Requires -Version 5.1
<#
.SYNOPSIS
    Razes SovereignClaw completely: unregisters the 'sovereignclaw' WSL2
    distro (cluster, Secrets, models, and Lord Clawsworth's memories).

.PARAMETER KeepRootfs
    Keep the cached Ubuntu rootfs (~200 MB) for a faster reinstall.
#>

[CmdletBinding()]
param([switch]$KeepRootfs)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$DISTRO_NAME = 'sovereignclaw'
$DATA_DIR    = "$env:LOCALAPPDATA\sovereignclaw"
$DISTRO_DIR  = "$DATA_DIR\distro"
$ROOTFS_FILE = "$DATA_DIR\rootfs\ubuntu-22.04-wsl.tar.gz"

Write-Host ''
Write-Host '  Raze the castle, Majesty? Very well. I shall go down with the ship.' -ForegroundColor Magenta
Write-Host ''
Write-Host 'This permanently deletes:' -ForegroundColor Yellow
Write-Host "  - The '$DISTRO_NAME' WSL2 distro and ALL data inside it (cluster, Secrets, models, agent memory)" -ForegroundColor Yellow
if (-not $KeepRootfs -and (Test-Path $ROOTFS_FILE)) {
    Write-Host "  - The cached Ubuntu rootfs at $ROOTFS_FILE" -ForegroundColor Yellow
}
Write-Host ''
if ((Read-Host "Type 'yes' to confirm") -ne 'yes') {
    Write-Host '  A reprieve! The court rejoices.' -ForegroundColor Magenta
    exit 0
}

$registered = (wsl --list --quiet 2>&1 | ForEach-Object { $_ -replace "`0", '' }) -contains $DISTRO_NAME
if ($registered) {
    wsl --unregister $DISTRO_NAME
    Write-Host "    OK: distro '$DISTRO_NAME' removed" -ForegroundColor Green
} else {
    Write-Host "    Distro '$DISTRO_NAME' not found; nothing to unregister" -ForegroundColor Yellow
}

if (Test-Path $DISTRO_DIR) { Remove-Item -Recurse -Force $DISTRO_DIR }
if (-not $KeepRootfs -and (Test-Path $ROOTFS_FILE)) { Remove-Item -Force $ROOTFS_FILE }

Write-Host ''
Write-Host '  It is done. Not one stone remains, and your own system is untouched.' -ForegroundColor Magenta
Write-Host '  Verify with: .\test\uninstall-verify.ps1' -ForegroundColor White
Write-Host ''
