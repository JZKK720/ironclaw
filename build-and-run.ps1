# IronClaw Docker Build and Run Script for Windows PowerShell
# Usage: .\build-and-run.ps1

param(
    [switch]$SkipBuild,
    [switch]$SkipPostgres,
    [switch]$Interactive
)

$ErrorActionPreference = "Stop"

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  IronClaw Docker Setup for Windows" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# Check Docker is running
try {
    $dockerVersion = docker version --format '{{.Server.Version}}' 2>$null
    Write-Host "✓ Docker is running (version $dockerVersion)" -ForegroundColor Green
} catch {
    Write-Host "✗ Docker is not running. Please start Docker Desktop first." -ForegroundColor Red
    exit 1
}

Write-Host ""

# Step 1: Pull base images (if not skipping build)
if (-not $SkipBuild) {
    Write-Host "Step 1: Pulling base images..." -ForegroundColor Yellow
    
    Write-Host "  → Pulling rust:1.92-slim-bookworm (this may take a few minutes)..." -ForegroundColor Gray
    docker pull rust:1.92-slim-bookworm
    
    Write-Host "  → Pulling debian:bookworm-slim..." -ForegroundColor Gray
    docker pull debian:bookworm-slim
    
    Write-Host "  ✓ Base images pulled" -ForegroundColor Green
    Write-Host ""
    
    # Step 2: Build IronClaw image
    Write-Host "Step 2: Building IronClaw image..." -ForegroundColor Yellow
    Write-Host "  → This will take 15-25 minutes..." -ForegroundColor Gray
    docker build --platform linux/amd64 -t ironclaw:latest .
    Write-Host "  ✓ IronClaw image built successfully" -ForegroundColor Green
    Write-Host ""
} else {
    Write-Host "Step 1-2: Skipping build (using existing image)" -ForegroundColor Yellow
    Write-Host ""
}

# Step 3: Start PostgreSQL
if (-not $SkipPostgres) {
    Write-Host "Step 3: Starting PostgreSQL..." -ForegroundColor Yellow
    
    # Check if postgres container already exists
    $postgresExists = docker ps -a --filter "name=ironclaw-postgres" --format "{{.Names}}"
    if ($postgresExists) {
        Write-Host "  → Removing existing PostgreSQL container..." -ForegroundColor Gray
        docker rm -f ironclaw-postgres
    }
    
    docker run -d --name ironclaw-postgres `
        -p 5433:5432 `
        -e POSTGRES_DB=ironclaw `
        -e POSTGRES_USER=ironclaw `
        -e POSTGRES_PASSWORD=ironclaw `
        -v ironclaw_pgdata:/var/lib/postgresql/data `
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
    
    Write-Host "  ✓ PostgreSQL is ready on port 5433" -ForegroundColor Green
    Write-Host ""
}

# Step 4: Interactive mode or run normally
if ($Interactive) {
    Write-Host "Step 4: Starting IronClaw in INTERACTIVE mode..." -ForegroundColor Yellow
    Write-Host "  → You can now run: ironclaw onboard" -ForegroundColor Cyan
    Write-Host "  → Or just: ironclaw (to start the web gateway)" -ForegroundColor Cyan
    Write-Host "  → Press Ctrl+C to exit" -ForegroundColor Gray
    Write-Host ""
    
    docker run -it --rm `
        -p 3231:3000 `
        -p 8281:8080 `
        -e DATABASE_URL=postgres://ironclaw:ironclaw@host.docker.internal:5433/ironclaw `
        ironclaw:latest
} else {
    Write-Host "Step 4: Starting IronClaw with docker-compose..." -ForegroundColor Yellow
    
    # Check if already running
    $ironclawRunning = docker ps --filter "name=ironclaw-app" --format "{{.Names}}"
    if ($ironclawRunning) {
        Write-Host "  → Stopping existing IronClaw container..." -ForegroundColor Gray
        docker compose down
    }
    
    docker compose up -d
    
    Write-Host "  ✓ IronClaw started!" -ForegroundColor Green
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "  Services are running!" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Web Gateway:  http://localhost:3231" -ForegroundColor White
    Write-Host "  HTTP Webhook: http://localhost:8281" -ForegroundColor White
    Write-Host "  PostgreSQL:   localhost:5433" -ForegroundColor White
    Write-Host ""
    Write-Host "  View logs: docker compose logs -f" -ForegroundColor Gray
    Write-Host "  Stop:      docker compose down" -ForegroundColor Gray
    Write-Host ""
}
