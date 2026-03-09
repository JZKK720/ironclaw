# IronClaw PowerShell Scripts

PowerShell automation scripts for building and running IronClaw on Windows.

## Prerequisites

- Docker Desktop for Windows (running)
- PowerShell 5.1 or later
- Run from project root directory

## Scripts

| Script | Purpose | Usage |
|--------|---------|-------|
| `build.ps1` | Build Docker image | `.\scripts\build.ps1` |
| `setup.ps1` | Interactive onboarding | `.\scripts\setup.ps1` |
| `start.ps1` | Start all services | `.\scripts\start.ps1` |
| `stop.ps1` | Stop all services | `.\scripts\stop.ps1` |
| `full-setup.ps1` | One-click full setup | `.\scripts\full-setup.ps1` |

## Quick Start

### Option 1: Full Automation (One Command)
```powershell
.\scripts\full-setup.ps1
```

### Option 2: Step-by-Step

**Step 1: Build the Docker image** (15-25 min)
```powershell
.\scripts\build.ps1
```

**Step 2: Run interactive onboarding** (configure LLM, auth, etc.)
```powershell
.\scripts\setup.ps1
```

Inside the container, run:
```bash
ironclaw onboard
```

**Step 3: Start services**
```powershell
.\scripts\start.ps1
```

## Access URLs

After starting:
- **Web Gateway**: http://localhost:3231
- **HTTP Webhook**: http://localhost:8281
- **PostgreSQL**: localhost:5433

## Common Commands

```powershell
# View logs
docker compose logs -f

# Check status
docker compose ps

# Stop services
.\scripts\stop.ps1
# or
docker compose down

# Rebuild and restart
docker compose up -d --build
```

## Troubleshooting

### "Docker is not running"
Start Docker Desktop first.

### "Image not found"
Run `.\scripts\build.ps1` first.

### Port conflicts
Edit `docker compose.yml` to change port mappings.
