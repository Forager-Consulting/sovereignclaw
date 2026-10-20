#Requires -Version 5.1
<#
.SYNOPSIS
    Confirms .\uninstall.ps1 left nothing behind. Observe only.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$DISTRO_NAME = 'sovereignclaw'
$DISTRO_DIR  = "$env:LOCALAPPDATA\sovereignclaw\distro"
$ROOTFS_FILE = "$env:LOCALAPPDATA\sovereignclaw\rootfs\ubuntu-22.04-wsl.tar.gz"
$fail = 0

$registered = (wsl --list --quiet 2>&1 | ForEach-Object { $_ -replace "`0", '' }) -contains $DISTRO_NAME
if ($registered) { Write-Host "  [FAIL] '$DISTRO_NAME' is still registered -> wsl --unregister $DISTRO_NAME" -ForegroundColor Red; $fail++ }
else             { Write-Host "  [PASS] '$DISTRO_NAME' distro is gone" -ForegroundColor Green }

if (Test-Path $DISTRO_DIR) { Write-Host "  [FAIL] $DISTRO_DIR still exists" -ForegroundColor Red; $fail++ }
else                       { Write-Host "  [PASS] distro directory removed" -ForegroundColor Green }

if (Test-Path $ROOTFS_FILE) { Write-Host "  [INFO] cached rootfs kept at $ROOTFS_FILE (expected with -KeepRootfs)" -ForegroundColor Cyan }

Write-Host ''
if ($fail -eq 0) { Write-Host '  Not one stone remains, Majesty.' -ForegroundColor Magenta }
else             { exit 1 }
