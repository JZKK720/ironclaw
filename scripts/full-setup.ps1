# One-Click Full Setup for IronClaw
# Usage: .\scripts\full-setup.ps1

param(
    [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  IronClaw - Full Setup" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "This script will:" -ForegroundColor White
Write-Host "  1. Pull base Docker images" -ForegroundColor Gray
Write-Host "  2. Build IronClaw Docker image" -ForegroundColor Gray
Write-Host "  3. Start PostgreSQL" -ForegroundColor Gray
Write-Host "  4. Start IronClaw web gateway" -ForegroundColor Gray
Write-Host ""

$confirm = Read-Host "Continue? (y/N)"
if ($confirm -ne 'y' -and $confirm -ne 'Y') {
    Write-Host "Cancelled." -ForegroundColor Yellow
    exit 0
}

Write-Host ""

# Step 1: Build (if not skipped)
if (-not $SkipBuild) {
    & "$PSScriptRoot\build.ps1"
} else {
    Write-Host "Step 1: Skipping build (-SkipBuild specified)" -ForegroundColor Yellow
    Write-Host ""
}

# Step 2: Start services
& "$PSScriptRoot\start.ps1"

Write-Host ""
Write-Host "==========================================" -ForegroundColor Green
Write-Host "  Setup Complete!" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green
Write-Host ""
Write-Host "IronClaw is running at: http://localhost:3231" -ForegroundColor White
Write-Host ""
Write-Host "If this is your first time:" -ForegroundColor Yellow
Write-Host "  Run .\scripts\setup.ps1 for interactive onboarding" -ForegroundColor Gray
Write-Host ""
