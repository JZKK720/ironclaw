---
description: "Backup-first guide to pull updated GHCR images and recreate the local Docker Compose runtime without losing .env, IRONCLAW_HOME_DIR, or the external Postgres volume. Use when you want to directly pull and update local containers, keep local env and data safe and backed up, roll forward after a fork sync or GHCR publish, or prepare a rollback."
---

# Update Local Docker Runtime

Use this when you need to answer: "Can we safely pull the new images into this machine right now, and how do we keep local env and data recoverable if the rollout fails?"

## Ground Rules

- Never print secret values from `.env`.
- Operator-owned state lives in `.env`, the `IRONCLAW_HOME_DIR` bind mount (or repo-local `extensions/ironclaw-home` fallback), and the external `ironclaw-pgdata` volume.
- `docker compose down -v` is destructive. Do not use it unless the user explicitly asks to delete state.
- If the target tag is still uncertain, run [Validate GHCR Upgrade](validate-ghcr-upgrade.prompt.md) first.

## Inspect These Sources Together

- [docker-compose.yml](../../docker-compose.yml)
- [AGENTS.md](../../AGENTS.md)
- [Updating draft](../../docs/drafts/install/updating.mdx)
- [Docker Compose platform doc](../../docs/drafts/platforms/docker-compose.mdx)

## Workflow

1. Capture the current runtime and intended target.

```powershell
docker compose ps
docker compose images
docker compose config
Invoke-WebRequest http://127.0.0.1:3231/api/health | Select-Object -ExpandProperty Content
```

2. Back up operator state before pulling anything.

```powershell
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backupDir = Join-Path (Get-Location) "backups\$stamp"
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null

Copy-Item .env (Join-Path $backupDir ".env")
docker compose images | Out-File (Join-Path $backupDir "compose-images.txt")
docker volume inspect ironclaw-pgdata | Out-File (Join-Path $backupDir "pgdata-volume.json")
docker compose exec -T postgres pg_dump -U ironclaw -d ironclaw --format=custom --compress=9 > (Join-Path $backupDir "postgres.dump")

# Replace the source path below with IRONCLAW_HOME_DIR from .env when it is set.
Copy-Item .\extensions\ironclaw-home (Join-Path $backupDir "ironclaw-home") -Recurse -Force
```

If `.env` points `IRONCLAW_HOME_DIR` at a host path outside the repo, back up that directory instead of `extensions/ironclaw-home`.

3. Pull the exact target images declared by compose and `.env`.

```powershell
docker compose pull ironclaw
docker compose pull ironclaw-worker
```

If `.env` pins `IRONCLAW_APP_IMAGE` or `SANDBOX_IMAGE` to a release tag or digest, keep those pins and pull that exact target instead of assuming `:latest`.

4. Recreate the runtime without deleting state.

```powershell
docker compose up -d --no-build postgres ironclaw
docker compose ps
docker compose logs --tail=200 ironclaw
Invoke-WebRequest http://127.0.0.1:3231/api/health | Select-Object -ExpandProperty Content
```

5. Validate the post-update state.

- Confirm the logs show startup completed and any migrations finished cleanly.
- Confirm the app is serving on the expected gateway and webhook ports.
- If the rollout was tied to a specific upstream intake such as `v0.28`, record the exact image tag or digest now running locally.

6. Roll back only if the update is unhealthy.

- Restore the previous image tag or digest from `compose-images.txt` by pinning `.env` or the compose override back to the known-good value, then recreate `postgres` and `ironclaw` with `docker compose up -d --no-build postgres ironclaw`.
- Restore the backed-up `IRONCLAW_HOME_DIR` copy if local config or extension state needs to be reverted.
- Restore `postgres.dump` only when a migration or data change requires a real data rollback:

```powershell
docker compose exec -T postgres pg_restore -U ironclaw -d ironclaw --clean --if-exists < .\backups\20260101-120000\postgres.dump
```

## Required Output

Report findings first, then end with:

1. `Backups created`: exact backup directory and artifacts
2. `Runtime target`: the image tag or digest pulled for `ironclaw` and `ironclaw-worker`
3. `Local rollout verdict`: `success`, `blocked`, or `rolled back`
4. `Rollback readiness`: `ready`, `partial`, or `not ready`
5. `Manual follow-ups`: any remaining smoke tests, pin updates, or restore steps