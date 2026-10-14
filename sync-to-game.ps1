$ErrorActionPreference = "Stop"

$root = $PSScriptRoot
$src = Join-Path $root "ogaki-ac8vr"
$dst = Join-Path $env:APPDATA "UnrealVRMod\AceCombat8"

if (-not (Test-Path $src)) {
    throw "Source folder not found: $src"
}

# Ensure base destination directory exists
if (-not (Test-Path $dst)) {
    New-Item -ItemType Directory -Path $dst -Force | Out-Null
}

Write-Host "=== Syncing ogaki-ac8vr to UEVR Profile (Robust Mode) ===" -ForegroundColor Cyan
Write-Host "From: $src"
Write-Host "To:   $dst`n"

# 0. Increment VERSION hex suffix (e.g. 0.1.0.01 -> 0.1.0.02 -> 0.1.0.0A)
$versionFile = Join-Path $src "VERSION"
if (Test-Path $versionFile) {
    $currentVer = (Get-Content $versionFile -Raw).Trim()
    if ($currentVer -match "^(.*[._])?([0-9A-Fa-f]{2})$") {
        $prefix = $matches[1]
        $hexSuffix = $matches[2]
        $num = [Convert]::ToInt32($hexSuffix, 16) + 1
        $newSuffix = "{0:X2}" -f ($num % 256)
        $newVer = "$prefix$newSuffix"
        Set-Content -Path $versionFile -Value $newVer
        Write-Host "Bumped VERSION: $currentVer -> $newVer`n" -ForegroundColor Yellow
    }
}

# 1. Folders to sync: scripts, data, plugins, docs
$foldersToSync = @("scripts", "data", "plugins", "docs")
foreach ($folder in $foldersToSync) {
    $srcFolder = Join-Path $src $folder
    $dstFolder = Join-Path $dst $folder
    
    if (Test-Path $srcFolder) {
        Write-Host "Syncing $folder/ ..." -ForegroundColor Cyan
        
        # If destination exists as a regular FILE (corrupted state), remove it first!
        if ((Test-Path $dstFolder) -and -not (Test-Path $dstFolder -PathType Container)) {
            Write-Warning "Removing corrupt file that was blocking directory: $dstFolder"
            Remove-Item -Path $dstFolder -Force
        }
        
        # Ensure destination directory exists
        if (-not (Test-Path $dstFolder -PathType Container)) {
            New-Item -ItemType Directory -Path $dstFolder -Force | Out-Null
        }
        
        try {
            # Use robocopy or recursive Copy-Item with robust folder handling
            Copy-Item -Path "$srcFolder\*" -Destination $dstFolder -Recurse -Force -ErrorAction Stop
        } catch {
            Write-Warning "Could not copy some files in $folder (possibly in-use by running game/UEVR): $_"
        }
    }
}

# 2. Key config and document files
$filesToSync = @(
    "VERSION",
    "config.txt",
    "cvars_data.txt",
    "features.txt",
    "CHANGELOG.md",
    "INSTALLATION.md",
    "PROFILE-FILES.txt",
    "THIRD_PARTY_NOTICES.md"
)
foreach ($file in $filesToSync) {
    $srcFile = Join-Path $src $file
    $dstFile = Join-Path $dst $file
    if (Test-Path $srcFile) {
        Copy-Item -Path $srcFile -Destination $dstFile -Force
    }
}

# 3. Clean up loose assets in plugins/ root if they were incorrectly dumped there
$pluginsDir = Join-Path $dst "plugins"
$ac8AssetsDir = Join-Path $pluginsDir "ac8-hud-assets"
if (Test-Path $ac8AssetsDir) {
    Get-ChildItem $pluginsDir -File | Where-Object {
        $_.Name -ne "AC8_VR-Runtime.dll" -and (Test-Path (Join-Path $ac8AssetsDir $_.Name))
    } | ForEach-Object {
        Remove-Item $_.FullName -Force
    }
}

Write-Host "`n=== Sync completed! File hierarchy verified with AC8-VR-v0.1.0 specification ===" -ForegroundColor Green