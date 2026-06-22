param(
    [Parameter(Mandatory = $true)]
    [string]$TargetDll,
    [Parameter(Mandatory = $true)]
    [string]$PendingDll,
    [int]$TimeoutSeconds = 1800
)

$ErrorActionPreference = "Stop"

$DllDir = Split-Path -Parent $TargetDll
$LogPath = Join-Path $DllDir "main.pending.install.log"

function Write-WatcherLog {
    param([string]$Message)
    $Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss.fff")
    Add-Content -Path $LogPath -Value "[$Timestamp] $Message" -Encoding ASCII
}

Write-WatcherLog "watcher started target=$TargetDll pending=$PendingDll timeout_seconds=$TimeoutSeconds"

$Deadline = (Get-Date).AddSeconds($TimeoutSeconds)
while ((Get-Date) -lt $Deadline) {
    if (-not (Test-Path $PendingDll)) {
        Write-WatcherLog "pending missing; nothing to install"
        exit 2
    }

    try {
        Copy-Item -Force $PendingDll $TargetDll
        $TargetHash = (Get-FileHash -Algorithm SHA256 $TargetDll).Hash.ToLowerInvariant()
        $PendingHash = (Get-FileHash -Algorithm SHA256 $PendingDll).Hash.ToLowerInvariant()
        if ($TargetHash -ne $PendingHash) {
            throw "hash mismatch target=$TargetHash pending=$PendingHash"
        }
        Remove-Item -Force $PendingDll
        Write-WatcherLog "installed pending dll sha256=$TargetHash"
        exit 0
    } catch {
        Start-Sleep -Seconds 2
    }
}

Write-WatcherLog "timed out waiting for target unlock"
exit 1
