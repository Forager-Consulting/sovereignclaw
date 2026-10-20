#Requires -Version 5.1
<#
.SYNOPSIS
    Closes the castle: stops the SovereignClaw distro immediately, returning
    all GPU memory and RAM to Windows. Nothing is deleted.
#>

wsl --terminate sovereignclaw
if ($LASTEXITCODE -eq 0) {
    Write-Host '  The gates are shut and the court retires, Majesty. Your GPU is yours again.' -ForegroundColor Magenta
} else {
    Write-Host 'ERROR: could not stop the sovereignclaw distro (is it installed?).' -ForegroundColor Red
    exit 1
}
