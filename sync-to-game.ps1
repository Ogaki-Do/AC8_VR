$ErrorActionPreference = "Stop"

$root = $PSScriptRoot
$src = Join-Path $root "ogaki-ac8vr"
$dst = Join-Path $env:APPDATA "UnrealVRMod\AceCombat8"

if (-not (Test-Path $src)) {
    throw "Source folder not found: $src"
}
if (-not (Test-Path $dst)) {
    throw "Target UEVR profile folder not found: $dst"
}

Write-Host "=== Syncing ogaki-ac8vr to UEVR Profile ===" -ForegroundColor Cyan
Write-Host "From: $src"
Write-Host "To:   $dst`n"

# Folders to sync: scripts, data, plugins
$foldersToSync = @("scripts", "data", "plugins")
foreach ($folder in $foldersToSync) {
    $srcFolder = Join-Path $src $folder
    $dstFolder = Join-Path $dst $folder
    if (Test-Path $srcFolder) {
        Write-Host "Syncing $folder/ ..." -ForegroundColor Cyan
        try {
            Copy-Item -Path "$srcFolder\*" -Destination $dstFolder -Recurse -Force -ErrorAction Stop
        } catch {
            Write-Warning "Could not copy some files in $folder (possibly in-use by running game/UEVR): $_"
        }
    }
}

# Key config files if needed
$filesToSync = @("VERSION", "config.txt", "cvars_data.txt")
foreach ($file in $filesToSync) {
    $srcFile = Join-Path $src $file
    $dstFile = Join-Path $dst $file
    if (Test-Path $srcFile) {
        Copy-Item -Path $srcFile -Destination $dstFile -Force
    }
}

Write-Host "`n=== Sync completed! Restart game or reload scripts in UEVR menu to test ===" -ForegroundColor Green
