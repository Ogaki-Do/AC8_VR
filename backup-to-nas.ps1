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
Write-Host "Commit Message: $Message`n"

# 1. Commit and push in ogaki-ac8vr (MOD repo)
$ac8vrDir = Join-Path $root "ogaki-ac8vr"
if (Test-Path $ac8vrDir) {
    Write-Host "--- [1/2] Backing up ogaki-ac8vr (MOD Repository) ---" -ForegroundColor Cyan
    Push-Location $ac8vrDir
    try {
        $ac8vrBranch = (git rev-parse --abbrev-ref HEAD).Trim()
        Write-Host "Current branch: $ac8vrBranch"
        
        $ac8vrStatus = git status --porcelain
        if ($ac8vrStatus) {
            Write-Host "Changes detected in ogaki-ac8vr. Staging and committing..." -ForegroundColor Yellow
            git add .
            git commit -m "$Message"
        } else {
            Write-Host "No uncommitted changes in ogaki-ac8vr." -ForegroundColor DarkGray
        }

        Write-Host "Pushing ogaki-ac8vr ($ac8vrBranch) to NAS..." -ForegroundColor Cyan
        git push origin HEAD
        Write-Host "[OK] ogaki-ac8vr backed up successfully.`n" -ForegroundColor Green
    } catch {
        Write-Warning "Failed to push ogaki-ac8vr to NAS: $_"
    } finally {
        Pop-Location
    }
}

# 2. Commit and push in root workspace (Ace-uevr-test)
Write-Host "--- [2/2] Backing up Ace-uevr-test (Root Workspace) ---" -ForegroundColor Cyan
Push-Location $root
try {
    $rootBranch = (git rev-parse --abbrev-ref HEAD).Trim()
    Write-Host "Current branch: $rootBranch"

    Write-Host "Adding workspace changes..." -ForegroundColor Cyan
    git add .

    $rootStatus = git status --porcelain
    if ($rootStatus) {
        Write-Host "Committing with message: '$Message'..." -ForegroundColor Cyan
        git commit -m "$Message"
    } else {
        Write-Host "No new changes to commit in workspace root." -ForegroundColor DarkGray
    }

    Write-Host "Pushing workspace root ($rootBranch) to NAS..." -ForegroundColor Cyan
    git push origin HEAD
    Write-Host "`n=== All backups to NAS completed successfully! ===" -ForegroundColor Green
} catch {
    Write-Host "`n[Error] Workspace backup failed: $_" -ForegroundColor Red
} finally {
    Pop-Location
}

