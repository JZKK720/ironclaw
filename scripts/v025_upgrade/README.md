# Windows v0.25 Upgrade Pack

This folder is the repeatable upgrade path for the next Windows machine that
needs to move to the current `v0.25.x` fork state.

It is intentionally fork-only:

- it syncs from `origin/main`
- it does not push to or modify `upstream`
- it assumes the repo already contains the machine-specific `.env`

## What the installer does

`install-v025.ps1` performs the upgrade steps that matched the working setup on
this machine:

1. verifies `git`, `docker`, and `ollama`
2. verifies the repo is clean unless you explicitly allow a dirty tree
3. fast-forwards the local checkout from `origin/main`
4. builds the `ironclaw-worker:latest` sandbox image from `Dockerfile.worker`
5. rebuilds and starts the Docker stack defined in `docker-compose.yml`
6. waits for the gateway health endpoint to come back
7. verifies Ollama is reachable from the host
8. optionally probes a model with a minimal `Reply with exactly OK` request
9. automatically restarts Ollama once if the probe fails with the stuck-model
   error we hit on this machine (`model failed to load`)

## Before you run it

Make sure the target machine already has:

- Git
- Docker Desktop
- Ollama installed locally
- a clone of this fork with `origin` pointing at your fork
- the correct `.env` copied into the repo root

If the machine needs to preserve an existing database, restore or migrate that
data before first boot. The current Compose file uses the `pgdata_v025` volume.

## Recommended command

From the repo root on the target Windows machine:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\v025_upgrade\install-v025.ps1 -RepoDir . -OllamaModel gemma4:e4b-it-q8_0
```

If the machine is already on the correct commit and you only want the runtime
rebuild plus health checks:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\v025_upgrade\install-v025.ps1 -RepoDir . -SkipGitSync -OllamaModel gemma4:e4b-it-q8_0
```

## Useful switches

- `-AllowDirtyRepo`: only use this if you intentionally want to upgrade on top
  of local changes
- `-SkipGitSync`: skip `git fetch` and `git pull --ff-only origin main`
- `-SkipDockerBuild`: skip `docker compose up -d --build ...`
- `-SkipGatewayHealthCheck`: skip the `http://127.0.0.1:3231/api/health` wait
- `-SkipOllamaCheck`: skip Ollama reachability and model probing entirely
- `-OllamaModel <name>`: strongly recommended; enables the exact model probe and
  the automatic Ollama restart fallback

## Post-upgrade checks

After the script finishes, verify:

1. `docker compose ps` shows `ironclaw` and `postgres` up
2. `ollama ps` shows the expected model loaded after a test prompt
3. the gateway UI opens and returns a real model response
4. Telegram DMs work from the intended account

If Telegram prompts for pairing on a new account, approve it from the running
container:

```powershell
docker compose exec ironclaw sh -lc "ironclaw pairing list telegram --json"
docker compose exec ironclaw sh -lc "ironclaw pairing approve telegram <PAIRING_CODE>"
```

## Known failure mode handled by the script

On this Windows setup, IronClaw surfaced `LLM error 500` when Ollama itself was
stuck returning:

```text
model failed to load, this may be due to resource limitations or an internal error
```

That was not an IronClaw code bug. A clean Ollama restart fixed it. The script
now performs that restart automatically once when the direct generate probe hits
that exact failure pattern.