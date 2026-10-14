param(
    [string]$Message = ""
)

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot

if (-not $Message) {
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $Message = "Workspace update: $timestamp"
}

Write-Host "=== Ace-uevr-test NAS Backup ===" -ForegroundColor Cyan

# 1. Check ogaki-ac8vr git status
$ac8vrDir = Join-Path $root "ogaki-ac8vr"
if (Test-Path $ac8vrDir) {
    Push-Location $ac8vrDir
    try {
        $ac8vrStatus = git status --porcelain
        if ($ac8vrStatus) {
            Write-Host "[Info] ogaki-ac8vr has uncommitted changes:" -ForegroundColor Yellow
            $ac8vrStatus | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
            Write-Host "  (Reminder: commit in ogaki-ac8vr before creating pull requests)" -ForegroundColor DarkGray
        } else {
            Write-Host "[OK] ogaki-ac8vr is clean." -ForegroundColor Green
        }
    } finally {
        Pop-Location
    }
}

# 2. Commit and push in root workspace
Push-Location $root
try {
    Write-Host "[1/3] Adding workspace changes..." -ForegroundColor Cyan
    git add .

    $rootStatus = git status --porcelain
    if ($rootStatus) {
        Write-Host "[2/3] Committing with message: '$Message'..." -ForegroundColor Cyan
        git commit -m "$Message"
    } else {
        Write-Host "[2/3] No new changes to commit in workspace root." -ForegroundColor DarkGray
    }

    Write-Host "[3/3] Pushing to NAS (\\Ogaki_NAS\OgakisProject\gits\AC8VR)..." -ForegroundColor Cyan
    git push origin main
    Write-Host "`n=== Backup to NAS completed successfully! ===" -ForegroundColor Green
} catch {
    Write-Host "`n[Error] Backup failed: $_" -ForegroundColor Red
} finally {
    Pop-Location
}
