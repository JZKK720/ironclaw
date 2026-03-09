# Stop IronClaw Services
# Usage: .\scripts\stop.ps1

$ErrorActionPreference = "SilentlyContinue"

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  Stopping IronClaw Services" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# Check if running
$running = docker ps --filter "name=ironclaw" --format "{{.Names}}"

if (-not $running) {
    Write-Host "No IronClaw containers are running." -ForegroundColor Yellow
    exit 0
}

Write-Host "Stopping containers..." -ForegroundColor Yellow

if (Test-Path "docker-compose.yml") {
    docker compose down 2>&1 | Out-Null
} else {
    docker stop ironclaw-app ironclaw-postgres 2>&1 | Out-Null
    docker rm ironclaw-app ironclaw-postgres 2>&1 | Out-Null
}

Write-Host ""
Write-Host "✓ All services stopped" -ForegroundColor Green
Write-Host ""
Write-Host "To remove data volumes as well:" -ForegroundColor Yellow
Write-Host "  docker volume rm ironclaw_pgdata ironclaw-data" -ForegroundColor Gray
Write-Host ""
