# Start IronClaw Services with Docker Compose
# Usage: .\scripts\start.ps1

$ErrorActionPreference = "Stop"

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  Starting IronClaw Services" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# Check if image exists
$imageExists = docker images ironclaw:latest --format "{{.Repository}}"
if (-not $imageExists) {
    Write-Host "✗ Image 'ironclaw:latest' not found!" -ForegroundColor Red
    Write-Host "  Please build first: .\scripts\build.ps1" -ForegroundColor Yellow
    exit 1
}

# Check docker-compose.yml exists
if (-not (Test-Path "docker-compose.yml")) {
    Write-Host "✗ docker-compose.yml not found!" -ForegroundColor Red
    Write-Host "  Please run from project root directory" -ForegroundColor Yellow
    exit 1
}

# Check .env file exists (warn but don't fail - IronClaw can use env vars directly)
if (-not (Test-Path ".env")) {
    Write-Host "⚠ .env file not found!" -ForegroundColor Yellow
    Write-Host "  IronClaw will use environment variables." -ForegroundColor Gray
    Write-Host "  Create .env file or ensure required vars are set." -ForegroundColor Gray
    Write-Host ""
}

Write-Host "Step 1: Checking existing containers..." -ForegroundColor Yellow

# Stop and remove existing containers (both running and stopped)
$existing = docker ps -a --filter "name=ironclaw" --format "{{.Names}}"
if ($existing) {
    Write-Host "  → Removing existing containers..." -ForegroundColor Gray
    try {
        docker compose down -v 2>&1 | Out-Null
        docker rm -f ironclaw-postgres ironclaw-app 2>&1 | Out-Null
    } catch {
        # Ignore errors during shutdown
    }
}

Write-Host "  ✓ Ready to start" -ForegroundColor Green
Write-Host ""

Write-Host "Step 2: Starting services with docker-compose..." -ForegroundColor Yellow
docker compose up -d

Write-Host "  → Waiting for services to be ready..." -ForegroundColor Gray
Start-Sleep -Seconds 3

# Check status
$postgresStatus = docker ps --filter "name=ironclaw-postgres" --format "{{.Status}}"
$appStatus = docker ps --filter "name=ironclaw-app" --format "{{.Status}}"

Write-Host ""
Write-Host "==========================================" -ForegroundColor Green
Write-Host "  Services Started!" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green
Write-Host ""
Write-Host "PostgreSQL:  " -NoNewline; Write-Host "localhost:5433" -ForegroundColor White
Write-Host "Web Gateway: " -NoNewline; Write-Host "http://localhost:3231" -ForegroundColor White
Write-Host "HTTP:        " -NoNewline; Write-Host "http://localhost:8281" -ForegroundColor White
Write-Host ""
Write-Host "Useful commands:" -ForegroundColor Yellow
Write-Host "  docker compose logs -f    # View logs" -ForegroundColor Gray
Write-Host "  docker compose ps         # Check status" -ForegroundColor Gray
Write-Host "  .\scripts\stop.ps1        # Stop services" -ForegroundColor Gray
Write-Host ""
