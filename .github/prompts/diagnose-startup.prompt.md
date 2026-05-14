---
description: "Diagnose and fix local Docker Compose startup failures where ironclaw or postgres won't start cleanly without a manual reboot. Use when containers exit on first boot, when the DB is unhealthy, when migrations fail, or when the ironclaw container needs multiple attempts to start."
---

# Diagnose Local Container Startup Failures

Use this when `docker compose up` leaves `ironclaw` or `postgres` in a stopped/unhealthy state and you have to reboot containers manually to recover.

## Ground Rules

- Never use `docker compose down -v` — this destroys the external `ironclaw-pgdata` volume.
- Never print secret values from `.env`.
- Treat `.env`, `IRONCLAW_HOME_DIR`, and the `ironclaw-pgdata` volume as operator-owned state.

## Inspect These Sources Together

- [docker-compose.yml](../../docker-compose.yml)
- [local-ops.instructions.md](../instructions/local-ops.instructions.md)
- [update-local-docker-runtime.prompt.md](update-local-docker-runtime.prompt.md)

---

## Step 1 — Capture the current state

```powershell
docker compose ps
docker compose logs --tail=100 postgres
docker compose logs --tail=100 ironclaw
```

Identify which service exited and what error appears in the logs.

---

## Step 2 — Check the external Postgres volume

The compose file declares `pgdata` as an **external** named volume (`ironclaw-pgdata`). If it does not exist yet, Postgres will fail silently on `docker compose up`.

```powershell
docker volume inspect ironclaw-pgdata
```

If the command returns `Error: No such volume`, create it once:

```powershell
docker volume create ironclaw-pgdata
```

Then retry:

```powershell
docker compose up -d --no-build postgres
docker compose ps postgres
```

---

## Step 3 — Check Postgres health

`ironclaw` uses `condition: service_healthy`, so if `pg_isready` never succeeds the app container will never start.

```powershell
docker compose exec postgres pg_isready -U ironclaw
docker compose inspect postgres --format "{{json .State.Health}}"
```

Common causes of unhealthy Postgres:

| Symptom | Fix |
|---------|-----|
| "FATAL: data directory has wrong ownership" | Volume created as root; recreate with correct user or `docker compose down && docker volume rm ironclaw-pgdata && docker volume create ironclaw-pgdata` (destructive — back up first) |
| Healthcheck passes but container exits immediately | Check `POSTGRES_USER`/`POSTGRES_DB` env mismatch against `DATABASE_URL` in `.env` |
| Port 5432 already in use | Stop the host Postgres service: `Stop-Service postgresql*` (Windows) or `sudo systemctl stop postgresql` (Linux) |

---

## Step 4 — Check ironclaw startup failure

If Postgres is healthy but `ironclaw` still exits:

```powershell
docker compose logs ironclaw --tail=200
```

Look for these patterns:

| Log pattern | Cause | Fix |
|-------------|-------|-----|
| `could not connect to server` | Container started before Postgres was fully ready despite healthcheck | Add `restart: on-failure:3` to the `ironclaw` service in compose, or simply `docker compose up -d ironclaw` after Postgres is healthy |
| `migration failed` / `relation already exists` | Migration version conflict | See Step 5 |
| `Error: missing required env var` | `.env` is incomplete | Compare `.env` against `deploy/env.example` |
| `permission denied: /home/ironclaw/.ironclaw` | Bind-mount ownership issue | `docker compose exec ironclaw chown -R 0:0 /home/ironclaw/.ironclaw` (container runs as root) |
| `address already in use :3000` | Another process on host port 3231→3000 | Find and stop the conflicting process |

---

## Step 5 — Migration conflicts

If logs show a migration error after pulling a new image:

```powershell
# See which migrations have already run
docker compose exec postgres psql -U ironclaw -d ironclaw \
  -c "SELECT version, success FROM schema_version ORDER BY installed_rank DESC LIMIT 20;"
```

If a migration version in `migrations/` conflicts with one already applied:

1. Check `migrations/` for the conflicting file version.
2. Compare against the upstream change (`git log --oneline migrations/`).
3. If the migration is safe to re-run, mark it resolved; if it is a version number collision, renumber the local migration file and reset the checksum.

---

## Step 6 — Quick restart after fixing root cause

Once the root cause is resolved, restart cleanly without recreating volumes:

```powershell
docker compose up -d --no-build postgres ironclaw
docker compose ps
Invoke-WebRequest http://127.0.0.1:3231/api/health | Select-Object -ExpandProperty Content
```

Expected: `{"status":"ok"}` or similar from the health endpoint.

---

## Step 7 — Prevent future manual reboots

If `ironclaw` consistently needs one manual restart after the very first `up`:

Add `restart: on-failure:3` to the `ironclaw` service block in `docker-compose.yml`. This tells Docker to automatically retry the container up to 3 times when it exits with a non-zero code, covering the race between the healthcheck passing and the database accepting connections.

```yaml
  ironclaw:
    image: ${IRONCLAW_APP_IMAGE:-ghcr.io/jzkk720/ironclaw:latest}
    restart: on-failure:3   # ← add this line
    depends_on:
      postgres:
        condition: service_healthy
```

Commit this change to `docker-compose.yml` after verifying it resolves the startup race.
