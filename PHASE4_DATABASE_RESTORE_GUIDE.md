# Phase 4: Database-Backed State Restoration Guide

## Key Discovery (2026-04-02)

IronClaw v0.19/v0.24 **use PostgreSQL as the primary state store**, not the filesystem.

**Implications**:
- File-based backups (settings.json, workspace/, skills/) are **minimal/supplementary**
- Actual configuration stored in PostgreSQL tables
- In a fresh v0.24 onboarding, the database is empty until populated by wizard or migration
- **Backup strategy**: PostgreSQL dump is what matters

## Database Backup Status

✅ **Created**: `C:\Users\ninex\git-pr\ironclaw0.19-backup\postgres-dump-v0.19.sql`
- Size: 712.3 KB
- Format: SQL (psql export)
- Contains: All v0.19 schemas, tables, data

## Phase 4 Execution: Database Restore

### 4.1 Start Clean v0.24 with Fresh Database

First, ensure v0.24 container is running with PostgreSQL:

```powershell
# Verify postgres is healthy
docker ps -f "name=postgres" --format="table {{.Names}}\t{{.Status}}"
# Expected: ironclaw-postgres-1  Up X minutes (healthy)

# Verify v0.24 agent can connect
docker exec ironclaw-v0.24-fresh sh -c "ironclaw --version"  
# Expected: ironclaw 0.24.0 or similar
```

### 4.2 Option A: Migrate v0.19 Data to v0.24 (RECOMMENDED)

**Restore the database dump to PostgreSQL:**

```powershell
# Restore pg dump into postgres
$dumpFile = "C:\Users\ninex\git-pr\ironclaw0.19-backup\postgres-dump-v0.19.sql"

# Method 1: Direct psql from container
docker exec -i ironclaw-postgres-1 psql -U ironclaw -d ironclaw < $dumpFile

# OR Method 2: If docker exec stdin has issues, copy to container first
docker cp $dumpFile ironclaw-postgres-1:/tmp/dump.sql
docker exec ironclaw-postgres-1 psql -U ironclaw -d ironclaw -f /tmp/dump.sql

Write-Host "✅ Database restore complete" -ForegroundColor Green
```

**Verify restore:**
```powershell
# Check table count
docker exec ironclaw-postgres-1 psql -U ironclaw -d ironclaw -c "\dt" | tail -5

# Expected output: List of v0.19 tables (conversations, settings, embeddings, etc.)
```

### 4.3 Option B: Fresh Start (Schema only, no data)

If you prefer a clean slate with just the schema:

```powershell
# Run migrations on empty database (v0.24 will handle this on startup)
docker exec ironclaw-v0.24-fresh sh -c "ironclaw --run-migrations"  # if available

# Or let the onboarding wizard create fresh schema
```

### 4.4 Verify v0.24 Agent Sees the Data

```powershell
# Start v0.24 agent  
docker exec -d ironclaw-v0.24-fresh ironclaw run

# Check logs for successful database connection
docker logs ironclaw-v0.24-fresh | grep -i "postgres\|database\|migration" | tail -5

# Expected: Successful database connection logs, no errors
```

## Potential Issues & Troubleshooting

### Issue: "psql: could not translate host name"

**Cause**: psql can't resolve postgres hostname from host machine  
**Solution**: Use container-based psql instead:

```powershell
# ✗ Wrong (from Windows)
psql -U ironclaw -d ironclaw -h localhost -p 5432 < dump.sql

# ✓ Correct (via container)
docker exec -i ironclaw-postgres-1 psql -U ironclaw -d ironclaw < dump.sql
```

### Issue: "database ironclaw already exists"

**Cause**: Previous restore attempt or v0.24 already initialized  
**Solution**: Drop and recreate:

```powershell
docker exec ironclaw-postgres-1 psql -U ironclaw -c "DROP DATABASE IF EXISTS ironclaw;"
docker exec ironclaw-postgres-1 psql -U ironclaw -c "CREATE DATABASE ironclaw;"

# Then restore
docker exec -i ironclaw-postgres-1 psql -U ironclaw -d ironclaw < $dumpFile
```

### Issue: "permission denied" on dump file

**Cause**: Windows path permissions or Docker mount issues  
**Solution**: Convert path to WSL or Docker volume:

```powershell
# WSL path
$wslPath = "/mnt/c/Users/ninex/git-pr/ironclaw0.19-backup/postgres-dump-v0.19.sql"
wsl cat $wslPath | docker exec -i ironclaw-postgres-1 psql -U ironclaw -d ironclaw
```

## Data Compatibility Notes

- **v0.19 → v0.24 schema compatibility**: Generally compatible (forward-compatible migrations)
- **API key encryption**: May need to re-encrypt if SECRETS_MASTER_KEY differs
- **Embeddings**: Existing embeddings vectors may be incompatible if model changed
- **Timestamps**: Check timezone handling in settings

## Next Steps: Phase 5 (Smoke Tests)

Once database is restored:

```pow
ershell
# Verify v0.24 can read v0.19 configuration
docker exec ironclaw-v0.24-fresh ironclaw memory-search "test" --limit 5

# Check conversation history was restored
docker exec ironclaw-v0.24-fresh curl -s http://localhost:3000/api/conversations | jq 'length'

# Test LLM connectivity with restored config
docker exec ironclaw-v0.24-fresh echo "Hello" | ironclaw chat
```

---

**Status**: Ready for Phase 4 execution  
**Action**: Choose Option A (migrate data) or Option B (fresh start), then execute commands above
