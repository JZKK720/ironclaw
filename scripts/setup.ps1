# IronClaw Interactive Setup (Onboarding)
# Usage: .\scripts\setup.ps1

$ErrorActionPreference = "Stop"

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  IronClaw Interactive Setup" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# Check if image exists
$imageExists = docker images ironclaw:latest --format "{{.Repository}}"
if (-not $imageExists) {
    Write-Host "✗ Image 'ironclaw:latest' not found!" -ForegroundColor Red
    Write-Host "  Please build first: .\scripts\build.ps1" -ForegroundColor Yellow
    exit 1
}

# Check if PostgreSQL is running
$postgresRunning = docker ps --filter "name=ironclaw-postgres" --format "{{.Names}}"
if (-not $postgresRunning) {
    Write-Host "⚠ PostgreSQL is not running. Starting it now..." -ForegroundColor Yellow
    
    $postgresExists = docker ps -a --filter "name=ironclaw-postgres" --format "{{.Names}}"
    if ($postgresExists) {
        docker rm -f ironclaw-postgres
    }
    
    docker run -d --name ironclaw-postgres `
        -p 5433:5432 `
        -e POSTGRES_DB=ironclaw `
        -e POSTGRES_USER=ironclaw `
        -e POSTGRES_PASSWORD=ironclaw `
        pgvector/pgvector:pg16
    
    Write-Host "  → Waiting for PostgreSQL to be ready..." -ForegroundColor Gray
    $maxRetries = 30
    $retry = 0
    while ($retry -lt $maxRetries) {
        $ready = docker exec ironclaw-postgres pg_isready -U ironclaw 2>$null
        if ($ready -match "accepting connections") {
            break
        }
        Start-Sleep -Seconds 1
        $retry++
    }
}

Write-Host "✓ PostgreSQL is ready on port 5433" -ForegroundColor Green
Write-Host ""

Write-Host "Starting interactive IronClaw container..." -ForegroundColor Yellow
Write-Host "  → This will open a shell inside the container" -ForegroundColor Gray
Write-Host "  → Run 'ironclaw onboard' to configure" -ForegroundColor Cyan
Write-Host "  → Or run 'ironclaw' to start directly" -ForegroundColor Cyan
Write-Host "  → Press Ctrl+C to exit" -ForegroundColor Gray
Write-Host ""

# Set environment variable for this session
$env:DATABASE_URL = "postgres://ironclaw:ironclaw@host.docker.internal:5433/ironclaw"

docker run -it --rm `
    -p 3231:3000 `
    -p 8281:8080 `
    -e DATABASE_URL=postgres://ironclaw:ironclaw@host.docker.internal:5433/ironclaw `
    -v ironclaw-data:/home/ironclaw/.ironclaw `
    ironclaw:latest

Write-Host ""
Write-Host "==========================================" -ForegroundColor Green
Write-Host "  Interactive session ended" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green
Write-Host ""
Write-Host "To start services: .\scripts\start.ps1" -ForegroundColor Yellow
Write-Host ""
