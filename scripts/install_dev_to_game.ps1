param(
    [string]$GameRoot = "C:\Program Files (x86)\Steam\steamapps\common\MECCHA CHAMELEON",
    [string]$BuildDir = "",
    [string]$ModName = "MecchaCamouflage"
)

$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
if (-not $BuildDir) {
    $BuildDir = Join-Path $RepoRoot "build-dev"
}

$Dll = Get-ChildItem $BuildDir -Recurse -Filter "MecchaCamouflage.dll" |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
if (-not $Dll) {
    throw "MecchaCamouflage.dll was not found under $BuildDir. Run scripts\build_dev.ps1 first."
}

$ModsRootCandidates = @(
    (Join-Path $GameRoot "Chameleon\Binaries\Win64\ue4ss\Mods"),
    (Join-Path $GameRoot "Chameleon\Binaries\Win64\Mods")
)
$ModsRoot = ""
foreach ($Candidate in $ModsRootCandidates) {
    if (Test-Path $Candidate) {
        $ModsRoot = $Candidate
        break
    }
}
if (-not $ModsRoot) {
    throw "UE4SS Mods folder was not found. Checked: $($ModsRootCandidates -join '; ')"
}

$DllDir = Join-Path $ModsRoot "$ModName\dlls"
New-Item -ItemType Directory -Force -Path $DllDir | Out-Null
$TargetDll = Join-Path $DllDir "main.dll"
$Installed = $true
try {
    Copy-Item -Force $Dll.FullName $TargetDll
} catch {
    $Installed = $false
    $PendingDll = Join-Path $DllDir "main.pending.dll"
    Copy-Item -Force $Dll.FullName $PendingDll
    $WatcherScript = Join-Path $RepoRoot "scripts\replace_pending_when_unlocked.ps1"
    if (Test-Path $WatcherScript) {
        $Quote = {
            param([string]$Value)
            '"' + ($Value -replace '"', '\"') + '"'
        }
        $Arguments = @(
            "-NoProfile",
            "-ExecutionPolicy Bypass",
            "-File $(& $Quote $WatcherScript)",
            "-TargetDll $(& $Quote $TargetDll)",
            "-PendingDll $(& $Quote $PendingDll)"
        ) -join " "
        Start-Process -WindowStyle Hidden -FilePath "powershell.exe" -ArgumentList $Arguments | Out-Null
        Write-Warning "Could not replace $TargetDll because it is in use. Staged new DLL at $PendingDll and started a watcher to replace it when the game exits."
    } else {
        Write-Warning "Could not replace $TargetDll because it is in use. Close the game and run this script again. Staged new DLL at $PendingDll"
    }
}

$ModsTxt = Join-Path $ModsRoot "mods.txt"
if (-not (Test-Path $ModsTxt)) {
    New-Item -ItemType File -Force -Path $ModsTxt | Out-Null
}

$Lines = Get-Content $ModsTxt -ErrorAction SilentlyContinue
$Filtered = @()
foreach ($Line in $Lines) {
    if ($Line -match '^\s*MecchaCamouflage\s*:' -or $Line -match '^\s*MecchaCamouflageDev\s*:') {
        continue
    }
    $Filtered += $Line
}
$Filtered += "MecchaCamouflage : 1"
$Filtered += "MecchaCamouflageDev : 0"
Set-Content -Path $ModsTxt -Value $Filtered -Encoding ASCII

if ($Installed) {
    $Hash = (Get-FileHash -Algorithm SHA256 $TargetDll).Hash.ToLowerInvariant()
    Write-Host "Installed dev DLL:"
    Write-Host "  $TargetDll"
    Write-Host "  sha256=$Hash"
} else {
    $Hash = (Get-FileHash -Algorithm SHA256 $PendingDll).Hash.ToLowerInvariant()
    Write-Host "Staged dev DLL:"
    Write-Host "  $PendingDll"
    Write-Host "  sha256=$Hash"
}
Write-Host "Enabled MecchaCamouflage and disabled MecchaCamouflageDev in:"
Write-Host "  $ModsTxt"
