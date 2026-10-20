#Requires -Version 5.1
<#
.SYNOPSIS
    Installs SovereignClaw: a self-hosted AI agent (OpenClaw + Ollama) in a
    disposable WSL2 sandbox on your Windows PC.

.DESCRIPTION
    Creates a dedicated 'sovereignclaw' WSL2 distro (Ubuntu 22.04) and runs
    bootstrap/bootstrap.sh inside it: k3s, the NVIDIA container toolkit,
    Argo CD, Ollama on your non-display GPU, and OpenClaw, narrated by your
    Grand Vizier, Lord Clawsworth. No API keys, no accounts, nothing leaves
    your machine.

.EXAMPLE
    .\install.ps1
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$DISTRO_NAME = 'sovereignclaw'
$DATA_DIR    = "$env:LOCALAPPDATA\sovereignclaw"
$DISTRO_DIR  = "$DATA_DIR\distro"
$ROOTFS_DIR  = "$DATA_DIR\rootfs"
$ROOTFS_FILE = "$ROOTFS_DIR\ubuntu-22.04-wsl.tar.gz"
$ROOTFS_URL  = 'https://cloud-images.ubuntu.com/wsl/releases/22.04/current/ubuntu-jammy-wsl-amd64-wsl.rootfs.tar.gz'
$REPO_ROOT   = $PSScriptRoot

function Write-Step([string]$msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-OK([string]$msg)   { Write-Host "    OK: $msg" -ForegroundColor Green }
function Write-Say([string]$msg)  { Write-Host "    $msg" -ForegroundColor Yellow }
function Write-Fail([string]$msg) { Write-Host "`nERROR: $msg" -ForegroundColor Red; exit 1 }

function ConvertTo-WslPath([string]$winPath) {
    $drive = $winPath.Substring(0, 1).ToLower()
    $rest  = $winPath.Substring(2) -replace '\\', '/'
    return "/mnt/$drive$rest"
}

Write-Host ''
Write-Host '  Your Majesty! Lord Clawsworth, Grand Vizier, at your service.' -ForegroundColor Magenta
Write-Host '  Permit me to raise a castle upon your own hardware, where no cloud may intrude.' -ForegroundColor Magenta

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------

Write-Step 'Inspecting the grounds'

try { wsl --status 2>&1 | Out-Null; Write-OK 'WSL2 is present.' }
catch { Write-Fail 'WSL2 not found. Enable it with: wsl --install, then reboot.' }

try {
    $smi = & nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>&1
    if ($LASTEXITCODE -ne 0) { throw }
    $driverVersion = ($smi -split '\n')[0].Trim()
    if ([int]($driverVersion -split '\.')[0] -lt 525) {
        Write-Fail "NVIDIA driver $driverVersion is too old. Need >= 525 (https://www.nvidia.com/drivers)."
    }
    Write-OK "NVIDIA driver $driverVersion. A worthy forge."
} catch {
    Write-Fail 'nvidia-smi not found. Install NVIDIA drivers >= 525 from https://www.nvidia.com/drivers'
}

$exists = $false
try { $exists = ((wsl -d $DISTRO_NAME -- echo 'ok' 2>&1) -join '') -match 'ok' } catch { }
if ($exists) { Write-Fail "A '$DISTRO_NAME' WSL2 distro already exists. Run .\uninstall.ps1 first." }

# ---------------------------------------------------------------------------
# Ubuntu rootfs + distro
# ---------------------------------------------------------------------------

Write-Step 'Quarrying the foundation stone (Ubuntu 22.04)'
New-Item -ItemType Directory -Force -Path $ROOTFS_DIR, $DISTRO_DIR | Out-Null
if (Test-Path $ROOTFS_FILE) {
    Write-OK 'A stone from a previous reign is in storage. We shall reuse it.'
} else {
    Write-Say 'Downloading the Ubuntu 22.04 WSL rootfs (~200 MB)...'
    Invoke-WebRequest -Uri $ROOTFS_URL -OutFile $ROOTFS_FILE -UseBasicParsing
    Write-OK 'Stone delivered.'
}

Write-Step "Laying the foundation (WSL2 distro '$DISTRO_NAME')"
wsl --import $DISTRO_NAME $DISTRO_DIR $ROOTFS_FILE --version 2
if ($LASTEXITCODE -ne 0) { Write-Fail 'wsl --import failed.' }
Write-OK 'Foundation laid. It is entirely separate from your own system, Majesty, and can be razed at will.'

Write-Step 'Delivering the plans and the Vizier''s robes'
$wslBootstrap = ConvertTo-WslPath "$REPO_ROOT\bootstrap\bootstrap.sh"
$wslPersona   = ConvertTo-WslPath "$REPO_ROOT\persona"
wsl -d $DISTRO_NAME -- bash -c "mkdir -p /opt/sovereignclaw/bootstrap /opt/sovereignclaw/persona && cp '$wslBootstrap' /opt/sovereignclaw/bootstrap/ && chmod +x /opt/sovereignclaw/bootstrap/bootstrap.sh && cp '$wslPersona'/*.md /opt/sovereignclaw/persona/"
if ($LASTEXITCODE -ne 0) { Write-Fail 'Copying files into the distro failed.' }
Write-OK 'Delivered.'

# ---------------------------------------------------------------------------
# systemd (required by k3s)
# ---------------------------------------------------------------------------

Write-Step 'Hiring the night watch (systemd)'
# Written from Windows via the UNC path: UTF-8 without BOM, LF line endings
[System.IO.File]::WriteAllText("\\wsl.localhost\$DISTRO_NAME\etc\wsl.conf", "[boot]`nsystemd=true`n", [System.Text.UTF8Encoding]::new($false))
Write-Say 'Restarting WSL to apply. Your other WSL distros will stop briefly.'
wsl --shutdown
Start-Sleep -Seconds 5

$ready = $false
for ($i = 0; $i -lt 45; $i++) {
    if ((wsl -d $DISTRO_NAME -- systemctl is-system-running 2>&1) -match 'running|degraded') { $ready = $true; break }
    Start-Sleep -Seconds 2
}
if (-not $ready) { Write-Fail 'systemd did not start within 90 seconds. Try: wsl --update' }
Write-OK 'The watch is posted.'

# ---------------------------------------------------------------------------
# Bootstrap
# ---------------------------------------------------------------------------

Write-Step 'Building the castle (about 10-15 minutes; the model download is ~5 GB)'
wsl -d $DISTRO_NAME -- bash /opt/sovereignclaw/bootstrap/bootstrap.sh
if ($LASTEXITCODE -ne 0) { Write-Fail 'Bootstrap failed. See the output above.' }

Write-Host ''
Write-Host '  Your castle stands, Majesty. To enter:' -ForegroundColor Magenta
Write-Host ''
Write-Host '    .\start.ps1     open the gates   (then visit http://localhost:18789)' -ForegroundColor White
Write-Host '    .\stop.ps1      close the castle (frees all GPU memory and RAM)' -ForegroundColor White
Write-Host '    .\uninstall.ps1 raze it entirely' -ForegroundColor White
Write-Host ''
Write-Host '  The Ollama model finishes downloading in the background; your first' -ForegroundColor Magenta
Write-Host '  audience may wait a few minutes. I shall be robing in the meantime.' -ForegroundColor Magenta
Write-Host ''
