# Build IronClaw Docker Image
# Usage: .\scripts\build.ps1

$ErrorActionPreference = "Stop"

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  Building IronClaw Docker Image" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# Check Docker
try {
    $null = docker version 2>$null
    Write-Host "✓ Docker is running" -ForegroundColor Green
} catch {
    Write-Host "✗ Docker is not running. Please start Docker Desktop first." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Step 1: Pulling base images..." -ForegroundColor Yellow

Write-Host "  → rust:1.92-slim-bookworm (1.2GB, may take 3-5 min)..." -ForegroundColor Gray
docker pull rust:1.92-slim-bookworm

Write-Host "  → debian:bookworm-slim..." -ForegroundColor Gray
docker pull debian:bookworm-slim

Write-Host "  ✓ Base images ready" -ForegroundColor Green
Write-Host ""

Write-Host "Step 2: Building ironclaw:latest..." -ForegroundColor Yellow
Write-Host "  → This will take 15-25 minutes..." -ForegroundColor Gray
Write-Host "  → Compiling Telegram WASM channel..." -ForegroundColor Gray
Write-Host "  → Building IronClaw binary..." -ForegroundColor Gray
Write-Host ""

docker build --platform linux/amd64 -t ironclaw:latest .

Write-Host ""
Write-Host "==========================================" -ForegroundColor Green
Write-Host "  Build Complete!" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Image: ironclaw:latest" -ForegroundColor White
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  .\scripts\setup.ps1    # Run interactive onboarding" -ForegroundColor Gray
Write-Host "  .\scripts\start.ps1    # Start all services" -ForegroundColor Gray
Write-Host ""
