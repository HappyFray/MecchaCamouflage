param(
    [string]$GameRoot = "C:\Program Files (x86)\Steam\steamapps\common\MECCHA CHAMELEON",
    [string]$ExePath = "",
    [string]$ConfigPath = "",
    [string]$GameExecutable = "PenguinHotel-Win64-Shipping.exe",
    [string]$InstallSubDir = "Chameleon\Binaries\Win64",
    [string]$ExeName = "meccha-camouflage.exe"
)

$ErrorActionPreference = "Stop"

$RuntimeRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
if (-not (Test-Path $GameRoot -PathType Container)) { throw "Game root was not found or not a directory: $GameRoot" }
if (-not $ExePath) {
    $RuntimeName = [System.IO.Path]::GetFileNameWithoutExtension($ExeName)
    $ExePath = Join-Path $RuntimeRoot ".build\bin\$RuntimeName.exe"
}
if (-not (Test-Path $ExePath -PathType Leaf)) { throw "Executable not found: $ExePath. Run scripts/build_native.ps1 first." }

$GameBin = Join-Path $GameRoot $InstallSubDir
if (-not (Test-Path $GameBin)) { throw "Target game folder was not found: $GameBin" }
$GameExe = Join-Path $GameBin $GameExecutable
if (-not (Test-Path $GameExe)) { throw "Expected game executable was not found: $GameExe. Ensure -GameRoot points to game root." }

$TargetExe = Join-Path $GameBin $ExeName
try {
    Copy-Item -Force $ExePath $TargetExe
} catch {
    throw "Could not replace $TargetExe. Close the running runtime/game process and retry. Original error: $($_.Exception.Message)"
}

if ($ConfigPath -and (Test-Path $ConfigPath)) { Copy-Item -Force $ConfigPath $GameBin }

$TargetHash = (Get-FileHash -Algorithm SHA256 $TargetExe).Hash.ToLowerInvariant()
Write-Host "Copied:"
Write-Host "  $TargetExe"
Write-Host "  sha256=$TargetHash"
